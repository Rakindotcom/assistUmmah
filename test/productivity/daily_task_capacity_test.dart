import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_event.dart';
import 'package:ummah_assist/src/productivity/domain/daily_task_capacity.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/recurrence.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';

void main() {
  final day = CalendarDay(2026, 11, 3);

  test('counts scheduled effort in the configured zone, excluding deadlines',
      () {
    final options = ExperienceOptions(
        language: 'en',
        timeZone: 'Asia/Dhaka',
        dailyCapacityMinutes: 120,
        workdayStartsAt: 9 * 60,
        workdayEndsAt: 11 * 60);
    final plan = DailyTaskCapacity.calculate(
        tasks: [
          ProductivityTask(
              id: 'all-day',
              workspaceId: 'personal',
              title: 'Plan',
              scheduledDay: day,
              estimatedMinutes: 90),
          ProductivityTask(
              id: 'instant',
              workspaceId: 'personal',
              title: 'Call',
              scheduledAt: DateTime.utc(2026, 11, 2, 19),
              estimatedMinutes: 45),
          ProductivityTask(
              id: 'unknown',
              workspaceId: 'personal',
              title: 'Unestimated',
              scheduledDay: day),
          ProductivityTask(
              id: 'deadline',
              workspaceId: 'personal',
              title: 'Due only',
              deadline: DateTime.utc(2026, 11, 3, 12),
              estimatedMinutes: 999),
          ProductivityTask(
              id: 'overdue',
              workspaceId: 'personal',
              title: 'Past planned work',
              scheduledDay: day.addDays(-1),
              estimatedMinutes: 999),
          ProductivityTask(
              id: 'completed',
              workspaceId: 'personal',
              title: 'Done',
              scheduledDay: day,
              estimatedMinutes: 120,
              status: TaskStatus.completed,
              completedAt: DateTime.utc(2026, 11, 3)),
          ProductivityTask(
              id: 'repeat',
              workspaceId: 'personal',
              title: 'Completed occurrence',
              recurrence: RecurrenceRule(
                  start: day, frequency: RecurrenceFrequency.daily),
              estimatedMinutes: 30),
        ],
        day: day,
        options: options,
        isCompleted: (task) =>
            task.status == TaskStatus.completed || task.id == 'repeat');
    expect(plan.plannedMinutes, 135);
    expect(plan.capacityMinutes, 120);
    expect(plan.plannedCount, 3);
    expect(plan.unestimatedCount, 1);
    expect(plan.overByMinutes, 15);
    expect(plan.overloaded, isTrue);
  });

  test('nonworking days have zero capacity and the work window is a ceiling',
      () {
    final options = ExperienceOptions(
        language: 'bn',
        timeZone: 'Asia/Dhaka',
        workingDays: [1, 2, 3, 4],
        dailyCapacityMinutes: 360,
        workdayStartsAt: 9 * 60,
        workdayEndsAt: 10 * 60);
    final friday = CalendarDay(2026, 11, 6);
    final task = ProductivityTask(
        id: 'friday',
        workspaceId: 'personal',
        title: 'Friday work',
        scheduledDay: friday,
        estimatedMinutes: 30);
    final rest = DailyTaskCapacity.calculate(
        tasks: [task],
        day: friday,
        options: options,
        isCompleted: (_) => false);
    expect(rest.nonworkingDay, isTrue);
    expect(rest.capacityMinutes, 0);
    expect(rest.overByMinutes, 30);

    final workday = DailyTaskCapacity.calculate(
        tasks: const [], day: day, options: options, isCompleted: (_) => false);
    expect(workday.capacityMinutes, 60);
  });

  test('active recurring work uses its occurrence, while a pause removes it',
      () {
    final options = ExperienceOptions(language: 'en', timeZone: 'Asia/Dhaka');
    ProductivityTask recurring(bool paused) => ProductivityTask(
        id: paused ? 'paused' : 'active',
        workspaceId: 'personal',
        title: 'Review',
        recurrence: RecurrenceRule(
            start: day, frequency: RecurrenceFrequency.daily, paused: paused),
        estimatedMinutes: 25);
    final plan = DailyTaskCapacity.calculate(
        tasks: [recurring(false), recurring(true)],
        day: day,
        options: options,
        isCompleted: (_) => false);
    expect(plan.plannedCount, 1);
    expect(plan.plannedMinutes, 25);
  });

  test('overlapping commitments reduce free work time once', () {
    final options = ExperienceOptions(
        language: 'en',
        timeZone: 'Asia/Dhaka',
        workdayStartsAt: 9 * 60,
        workdayEndsAt: 12 * 60,
        dailyCapacityMinutes: 180);
    CalendarEvent event(String id, int startHour, int endHour) => CalendarEvent(
        id: id,
        workspaceId: 'personal',
        title: id,
        start: DateTime.utc(2026, 11, 3, startHour - 6),
        end: DateTime.utc(2026, 11, 3, endHour - 6),
        timeZone: 'Asia/Dhaka');
    final plan = DailyTaskCapacity.calculate(tasks: [
      ProductivityTask(
          id: 'planned',
          workspaceId: 'personal',
          title: 'Plan',
          scheduledDay: day,
          estimatedMinutes: 100)
    ], events: [
      event('meeting', 9, 10),
      event('overlap', 9, 11),
      event('outside', 13, 14),
    ], day: day, options: options, isCompleted: (_) => false);
    expect(plan.calendarBusyMinutes, 120);
    expect(plan.capacityMinutes, 60);
    expect(plan.overByMinutes, 40);
  });

  test('commitment clipping honors a daylight-saving transition', () {
    final transition = CalendarDay(2026, 3, 8);
    final options = ExperienceOptions(
        language: 'en',
        timeZone: 'America/New_York',
        workingDays: [7],
        workdayStartsAt: 60,
        workdayEndsAt: 240,
        dailyCapacityMinutes: 180);
    final plan = DailyTaskCapacity.calculate(tasks: const [], events: [
      CalendarEvent(
          id: 'before-gap',
          workspaceId: 'personal',
          title: 'Before',
          start: DateTime.utc(2026, 3, 8, 6, 30),
          end: DateTime.utc(2026, 3, 8, 7, 30),
          timeZone: 'America/New_York')
    ], day: transition, options: options, isCompleted: (_) => false);
    expect(plan.calendarBusyMinutes, 60);
    expect(plan.capacityMinutes, 60);
  });
}
