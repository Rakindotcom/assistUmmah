import 'calendar_day.dart';
import 'calendar_event.dart';
import 'experience_options.dart';
import 'planning_time_zone.dart';
import 'task.dart';

/// Scheduled task effort versus the workday left after local commitments.
/// External calendars and travel buffers are not yet part of this estimate.
class DailyTaskCapacity {
  const DailyTaskCapacity({
    required this.capacityMinutes,
    required this.calendarBusyMinutes,
    required this.plannedMinutes,
    required this.plannedCount,
    required this.unestimatedCount,
    required this.nonworkingDay,
  });

  final int capacityMinutes;
  final int calendarBusyMinutes;
  final int plannedMinutes;
  final int plannedCount;
  final int unestimatedCount;
  final bool nonworkingDay;

  int get overByMinutes =>
      plannedMinutes > capacityMinutes ? plannedMinutes - capacityMinutes : 0;
  bool get overloaded => overByMinutes > 0;

  static DailyTaskCapacity calculate({
    required Iterable<ProductivityTask> tasks,
    required CalendarDay day,
    required ExperienceOptions options,
    required bool Function(ProductivityTask) isCompleted,
    Iterable<CalendarEvent> events = const [],
  }) {
    final nonworkingDay = !options.workingDays.contains(day.weekday);
    final windowMinutes = options.workdayEndsAt - options.workdayStartsAt;
    final baseCapacity = nonworkingDay
        ? 0
        : options.dailyCapacityMinutes < windowMinutes
            ? options.dailyCapacityMinutes
            : windowMinutes;
    final start = _boundary(day, options.workdayStartsAt, options.timeZone,
        laterOccurrence: false);
    final end = _boundary(day, options.workdayEndsAt, options.timeZone,
        laterOccurrence: true);
    final busy = nonworkingDay || !end.isAfter(start)
        ? 0
        : _busyMinutes(events, start, end);
    final actualWindow = end.difference(start).inMinutes;
    final boundedCapacity =
        baseCapacity < actualWindow ? baseCapacity : actualWindow;
    final capacity = (boundedCapacity - busy).clamp(0, windowMinutes);
    var minutes = 0;
    var count = 0;
    var unknown = 0;
    for (final task in tasks) {
      if (task.archived || isCompleted(task)) continue;
      final scheduledAtDay = task.scheduledAt == null
          ? null
          : CalendarDay.fromDate(
              PlanningTimeZone.inZone(task.scheduledAt!, options.timeZone));
      final occursToday = task.recurrence != null
          ? task.recurrence!.between(day, day).isNotEmpty
          : task.scheduledDay == day || scheduledAtDay == day;
      if (!occursToday) continue;
      count++;
      if (task.estimatedMinutes == 0) {
        unknown++;
      } else {
        minutes += task.estimatedMinutes;
      }
    }
    return DailyTaskCapacity(
        capacityMinutes: capacity,
        calendarBusyMinutes: busy,
        plannedMinutes: minutes,
        plannedCount: count,
        unestimatedCount: unknown,
        nonworkingDay: nonworkingDay);
  }

  static DateTime _boundary(CalendarDay day, int minute, String zone,
      {required bool laterOccurrence}) {
    // A transition can remove a wall-clock boundary. Start at the next valid
    // minute, and choose the later instant for an overlapping end boundary.
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

  static int _busyMinutes(
      Iterable<CalendarEvent> events, DateTime start, DateTime end) {
    final segments = <(DateTime, DateTime)>[];
    for (final event in events) {
      if (!event.end.isAfter(start) || !event.start.isBefore(end)) continue;
      segments.add((
        event.start.isAfter(start) ? event.start : start,
        event.end.isBefore(end) ? event.end : end,
      ));
    }
    segments.sort((a, b) => a.$1.compareTo(b.$1));
    DateTime? left, right;
    var milliseconds = 0;
    for (final segment in segments) {
      if (right == null) {
        left = segment.$1;
        right = segment.$2;
      } else if (!segment.$1.isAfter(right)) {
        if (segment.$2.isAfter(right)) right = segment.$2;
      } else {
        milliseconds += right.difference(left!).inMilliseconds;
        left = segment.$1;
        right = segment.$2;
      }
    }
    if (right != null) milliseconds += right.difference(left!).inMilliseconds;
    return (milliseconds / Duration.millisecondsPerMinute).ceil();
  }
}
