import 'calendar_day.dart';
import 'calendar_event.dart';
import 'daily_task_capacity.dart';
import 'experience_options.dart';
import 'planning_time_zone.dart';
import 'task.dart';

enum DailyTaskUnscheduledReason {
  unsupportedRecurrence,
  missingEstimate,
  waiting,
  blocked,
  incompleteDependencies,
  incompleteSubtasks,
  startsAfterDay,
  nonworkingDay,
  workdayEnded,
  deadlinePassed,
  deadlineCannotFit,
  capacityExceeded,
  noContiguousTime,
  planningLimitReached,
}

class DailyTaskPlacement {
  const DailyTaskPlacement({
    required this.taskId,
    required this.start,
    required this.end,
  });

  final String taskId;
  final DateTime start, end;
}

class DailyTaskUnscheduled {
  const DailyTaskUnscheduled({required this.taskId, required this.reason});

  final String taskId;
  final DailyTaskUnscheduledReason reason;
}

/// A proposal for review. Constructing a plan never edits task records.
class DailyTaskPlan {
  DailyTaskPlan._({
    required this.day,
    required this.timeZone,
    required this.workdayStart,
    required this.workdayEnd,
    required this.capacityMinutes,
    required this.fixedTaskMinutes,
    required Iterable<DailyTaskPlacement> placements,
    required Iterable<DailyTaskUnscheduled> unscheduled,
    required Iterable<String> excludedTaskIds,
    required Iterable<String> fixedTaskIds,
  })  : placements = List.unmodifiable(placements),
        unscheduled = List.unmodifiable(unscheduled),
        excludedTaskIds = List.unmodifiable(excludedTaskIds),
        fixedTaskIds = List.unmodifiable(fixedTaskIds);

  final CalendarDay day;
  final String timeZone;
  final DateTime workdayStart, workdayEnd;

  /// The configured daily budget after calendar commitments, using the same
  /// accounting as [DailyTaskCapacity]. Existing task effort is separate.
  final int capacityMinutes, fixedTaskMinutes;
  final List<DailyTaskPlacement> placements;
  final List<DailyTaskUnscheduled> unscheduled;

  /// Archived, completed, untimed inbox, disabled-workspace, future-day, and
  /// inactive recurring tasks are outside this proposal. Their records remain
  /// intact. A timed inbox task still reserves its existing calendar block.
  final List<String> excludedTaskIds;

  /// Existing timed commitments and active recurring work are never moved.
  final List<String> fixedTaskIds;

  int get plannedMinutes => placements.fold(
      0,
      (sum, placement) =>
          sum + placement.end.difference(placement.start).inMinutes);

  int get remainingCapacityMinutes =>
      (capacityMinutes - fixedTaskMinutes - plannedMinutes)
          .clamp(0, capacityMinutes);
}

/// Deterministic, contiguous first-fit placement inside a civil workday.
///
/// Higher priorities are considered first, followed by earlier hard deadlines,
/// earlier scheduled days, manual order, and record ID. A task must fit in one
/// free interval, finish by its hard deadline, and fit the remaining daily
/// effort budget. Existing timed tasks and enabled-workspace events stay fixed.
/// Unfinished dependency chains and parent checklists require manual review;
/// planned work does not count as completed work for either relationship.
abstract final class DailyTaskPlanner {
  static DailyTaskPlan plan({
    required Iterable<ProductivityTask> tasks,
    required Iterable<CalendarEvent> events,
    required ExperienceOptions options,
    required CalendarDay day,
    required DateTime now,
    bool Function(ProductivityTask)? isCompleted,
    int maxPlacements = 500,
  }) {
    if (maxPlacements < 1 || maxPlacements > 500) {
      throw ArgumentError.value(
          maxPlacements, 'maxPlacements', 'Use 1 to 500.');
    }
    final ordered = tasks.toList()..sort(_compareTasks);
    final byId = <String, ProductivityTask>{};
    for (final task in ordered) {
      if (byId.containsKey(task.id)) {
        throw ArgumentError('Task IDs must be unique.');
      }
      byId[task.id] = task;
    }
    bool complete(ProductivityTask task) =>
        task.status == TaskStatus.completed || isCompleted?.call(task) == true;
    final unfinishedParents = {
      for (final task in ordered)
        if (task.parentId != null && task.status != TaskStatus.completed)
          task.parentId!,
    };
    final enabled = options.modules.map((module) => module.name).toSet()
      ..remove(WorkspaceModule.faith.name);
    final visibleEvents =
        events.where((event) => enabled.contains(event.workspaceId)).toList();
    final capacity = DailyTaskCapacity.calculate(
        tasks: const [],
        events: visibleEvents,
        day: day,
        options: options,
        isCompleted: (_) => false);
    final start = _boundary(day, options.workdayStartsAt, options.timeZone,
        laterOccurrence: false);
    final end = _boundary(day, options.workdayEndsAt, options.timeZone,
        laterOccurrence: true);
    final earliest =
        _ceilMinute(now.toUtc().isAfter(start) ? now.toUtc() : start);
    final busy = <(DateTime, DateTime)>[
      for (final event in visibleEvents) (event.start, event.end),
    ];
    final excluded = <String>[];
    final fixed = <String>[];
    final candidates = <ProductivityTask>[];
    final unscheduled = <DailyTaskUnscheduled>[];
    var fixedMinutes = 0;

    void reject(ProductivityTask task, DailyTaskUnscheduledReason reason) {
      unscheduled.add(DailyTaskUnscheduled(taskId: task.id, reason: reason));
    }

    for (final task in ordered) {
      if (task.archived ||
          complete(task) ||
          (task.inbox && task.scheduledAt == null) ||
          !enabled.contains(task.workspaceId)) {
        excluded.add(task.id);
        continue;
      }
      if (task.recurrence != null) {
        var active = true;
        try {
          active = task.recurrence!.between(day, day).isNotEmpty;
        } on ArgumentError {
          // An unsupported recurrence horizon cannot prove this time is free.
        }
        if (!active) {
          excluded.add(task.id);
          continue;
        }
        fixed.add(task.id);
        reject(task, DailyTaskUnscheduledReason.unsupportedRecurrence);
        if (task.estimatedMinutes == 0 ||
            (task.scheduledAt != null &&
                _dayOf(task.scheduledAt!, options.timeZone) != day)) {
          // There is no occurrence-specific time/estimate to safely reuse.
          busy.add((start, end));
          fixedMinutes += end.difference(start).inMinutes;
        } else {
          fixedMinutes += task.estimatedMinutes;
          if (task.scheduledAt != null) {
            busy.add((
              task.scheduledAt!.toUtc(),
              task.scheduledAt!
                  .toUtc()
                  .add(Duration(minutes: task.estimatedMinutes))
            ));
          }
        }
        continue;
      }
      if (task.scheduledAt != null) {
        final fixedStart = task.scheduledAt!.toUtc();
        final fixedDay = _dayOf(fixedStart, options.timeZone);
        final fixedEnd =
            fixedStart.add(Duration(minutes: task.estimatedMinutes));
        final overlaps = fixedStart.isBefore(end) && fixedEnd.isAfter(start);
        if (fixedDay != day && !overlaps) {
          excluded.add(task.id);
          continue;
        }
        fixed.add(task.id);
        if (task.estimatedMinutes == 0) {
          reject(task, DailyTaskUnscheduledReason.missingEstimate);
          // An unknown timed duration reserves the rest of the workday until
          // the user supplies an estimate. Never invent a default duration.
          final left = fixedStart.isAfter(start) ? fixedStart : start;
          if (end.isAfter(left)) {
            busy.add((left, end));
            fixedMinutes += end.difference(left).inMinutes;
          }
        } else {
          busy.add((fixedStart, fixedEnd));
          fixedMinutes += fixedDay == day
              ? task.estimatedMinutes
              : _clippedMinutes(fixedStart, fixedEnd, start, end);
        }
        continue;
      }
      if (task.scheduledDay != null && task.scheduledDay!.isAfter(day)) {
        excluded.add(task.id);
        continue;
      }
      candidates.add(task);
    }

    var free = _freeIntervals(earliest, end, busy);
    var remaining = (capacity.capacityMinutes - fixedMinutes)
        .clamp(0, capacity.capacityMinutes);
    final placements = <DailyTaskPlacement>[];
    for (final task in candidates) {
      DailyTaskUnscheduledReason? reason;
      if (task.status == TaskStatus.waiting) {
        reason = DailyTaskUnscheduledReason.waiting;
      } else if (task.status == TaskStatus.blocked) {
        reason = DailyTaskUnscheduledReason.blocked;
      } else if (task.dependencies
          .any((id) => byId[id] == null || !complete(byId[id]!))) {
        reason = DailyTaskUnscheduledReason.incompleteDependencies;
      } else if (unfinishedParents.contains(task.id)) {
        // Match task completion prerequisites: archiving does not complete a
        // child, and completing one occurrence does not complete its series.
        reason = DailyTaskUnscheduledReason.incompleteSubtasks;
      } else if (task.startDate != null && task.startDate!.isAfter(day)) {
        reason = DailyTaskUnscheduledReason.startsAfterDay;
      } else if (task.estimatedMinutes == 0) {
        reason = DailyTaskUnscheduledReason.missingEstimate;
      } else if (capacity.nonworkingDay) {
        reason = DailyTaskUnscheduledReason.nonworkingDay;
      } else if (!end.isAfter(earliest)) {
        reason = DailyTaskUnscheduledReason.workdayEnded;
      } else if (task.deadline != null &&
          !task.deadline!.toUtc().isAfter(earliest)) {
        reason = DailyTaskUnscheduledReason.deadlinePassed;
      } else if (placements.length >= maxPlacements) {
        reason = DailyTaskUnscheduledReason.planningLimitReached;
      } else if (task.estimatedMinutes > remaining) {
        reason = DailyTaskUnscheduledReason.capacityExceeded;
      }
      if (reason != null) {
        reject(task, reason);
        continue;
      }
      final duration = Duration(minutes: task.estimatedMinutes);
      var index = -1;
      DateTime? placementStart, placementEnd;
      for (var i = 0; i < free.length; i++) {
        final left = _ceilMinute(free[i].$1);
        final right = left.add(duration);
        if (right.isAfter(free[i].$2) ||
            (task.deadline != null && right.isAfter(task.deadline!.toUtc()))) {
          continue;
        }
        index = i;
        placementStart = left;
        placementEnd = right;
        break;
      }
      if (index == -1) {
        final limitedByDeadline = task.deadline != null &&
            free.any(
                (slot) => !_ceilMinute(slot.$1).add(duration).isAfter(slot.$2));
        reject(
            task,
            limitedByDeadline
                ? DailyTaskUnscheduledReason.deadlineCannotFit
                : DailyTaskUnscheduledReason.noContiguousTime);
        continue;
      }
      placements.add(DailyTaskPlacement(
          taskId: task.id, start: placementStart!, end: placementEnd!));
      remaining -= task.estimatedMinutes;
      final original = free[index];
      free = [
        ...free.take(index),
        if (original.$1.isBefore(placementStart)) (original.$1, placementStart),
        if (placementEnd.isBefore(original.$2)) (placementEnd, original.$2),
        ...free.skip(index + 1),
      ];
    }
    placements.sort((a, b) {
      final time = a.start.compareTo(b.start);
      return time != 0 ? time : a.taskId.compareTo(b.taskId);
    });
    unscheduled.sort((a, b) => _compareTasks(byId[a.taskId]!, byId[b.taskId]!));
    excluded.sort();
    fixed.sort();
    return DailyTaskPlan._(
        day: day,
        timeZone: options.timeZone,
        workdayStart: start,
        workdayEnd: end,
        capacityMinutes: capacity.capacityMinutes,
        fixedTaskMinutes: fixedMinutes,
        placements: placements,
        unscheduled: unscheduled,
        excludedTaskIds: excluded,
        fixedTaskIds: fixed);
  }
}

int _compareTasks(ProductivityTask a, ProductivityTask b) {
  final priority = b.priority.index.compareTo(a.priority.index);
  if (priority != 0) return priority;
  final deadline = _compareNullable(a.deadline, b.deadline);
  if (deadline != 0) return deadline;
  final scheduled = _compareNullable(a.scheduledDay, b.scheduledDay);
  if (scheduled != 0) return scheduled;
  final order = a.order.compareTo(b.order);
  return order != 0 ? order : a.id.compareTo(b.id);
}

int _compareNullable<T extends Comparable<T>>(T? a, T? b) =>
    a == null ? (b == null ? 0 : 1) : (b == null ? -1 : a.compareTo(b));

CalendarDay _dayOf(DateTime instant, String zone) =>
    CalendarDay.fromDate(PlanningTimeZone.inZone(instant, zone));

DateTime _ceilMinute(DateTime instant) {
  final minute = Duration.microsecondsPerMinute;
  final value = instant.microsecondsSinceEpoch;
  final remainder = value % minute;
  return remainder == 0
      ? instant.toUtc()
      : DateTime.fromMicrosecondsSinceEpoch(value + minute - remainder,
          isUtc: true);
}

DateTime _boundary(CalendarDay day, int minute, String zone,
    {required bool laterOccurrence}) {
  // Match capacity accounting: shift missing boundary minutes forward and
  // preserve both occurrences of a repeated hour inside the work window.
  for (var offset = 0; offset <= 180; offset++) {
    final total = minute + offset;
    final localDay = day.addDays(total ~/ 1440);
    final candidates = PlanningTimeZone.candidates(
        localDay, (total % 1440) ~/ 60, total % 60, zone);
    if (candidates.isNotEmpty) {
      return laterOccurrence ? candidates.last : candidates.first;
    }
  }
  throw const FormatException('Could not resolve workday boundary.');
}

int _clippedMinutes(DateTime from, DateTime to, DateTime start, DateTime end) {
  final left = from.isAfter(start) ? from : start;
  final right = to.isBefore(end) ? to : end;
  return right.isAfter(left)
      ? (right.difference(left).inMicroseconds / Duration.microsecondsPerMinute)
          .ceil()
      : 0;
}

List<(DateTime, DateTime)> _freeIntervals(
    DateTime start, DateTime end, List<(DateTime, DateTime)> busy) {
  if (!end.isAfter(start)) return [];
  final ordered = busy
      .where((slot) => slot.$1.isBefore(end) && slot.$2.isAfter(start))
      .toList()
    ..sort((a, b) {
      final left = a.$1.compareTo(b.$1);
      return left != 0 ? left : a.$2.compareTo(b.$2);
    });
  final result = <(DateTime, DateTime)>[];
  var cursor = start;
  for (final slot in ordered) {
    if (slot.$1.isAfter(cursor)) {
      result.add((cursor, slot.$1.isBefore(end) ? slot.$1 : end));
    }
    if (slot.$2.isAfter(cursor)) cursor = slot.$2;
    if (!cursor.isBefore(end)) break;
  }
  if (cursor.isBefore(end)) result.add((cursor, end));
  return result;
}
