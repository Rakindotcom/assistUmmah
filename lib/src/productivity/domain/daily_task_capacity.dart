import 'calendar_day.dart';
import 'experience_options.dart';
import 'planning_time_zone.dart';
import 'task.dart';

/// Capacity used by planned tasks only. Calendar events and buffers are not
/// included until those records join the planning engine.
class DailyTaskCapacity {
  const DailyTaskCapacity({
    required this.capacityMinutes,
    required this.plannedMinutes,
    required this.plannedCount,
    required this.unestimatedCount,
    required this.nonworkingDay,
  });

  final int capacityMinutes;
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
  }) {
    final nonworkingDay = !options.workingDays.contains(day.weekday);
    final windowMinutes = options.workdayEndsAt - options.workdayStartsAt;
    final capacity = nonworkingDay
        ? 0
        : options.dailyCapacityMinutes < windowMinutes
            ? options.dailyCapacityMinutes
            : windowMinutes;
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
        plannedMinutes: minutes,
        plannedCount: count,
        unestimatedCount: unknown,
        nonworkingDay: nonworkingDay);
  }
}
