import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/calendar_event_repository.dart';
import 'package:ummah_assist/src/productivity/data/daily_planning_repository.dart';
import 'package:ummah_assist/src/productivity/data/experience_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_event.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/ui/calendar_page.dart';
import 'package:ummah_assist/src/productivity/ui/daily_planning_page.dart';

void main() {
  var sequence = 0;
  final day = CalendarDay(2026, 11, 9);
  final now = DateTime.utc(2026, 11, 9, 8);
  final options = ExperienceOptions(
      language: 'en', timeZone: 'UTC', completedOnboarding: true);

  Future<ProductivityDatabase> fixture() async {
    final db = await ProductivityDatabase.open(
        uid: 'daily-plan-ui',
        factory: databaseFactoryMemory,
        path: 'daily-plan-ui-${sequence++}');
    await ExperienceRepository(db).completeOnboarding(options);
    await TaskRepository(db).createTask(ProductivityTask(
        id: 'report',
        workspaceId: 'personal',
        title: 'Write the report',
        estimatedMinutes: 60,
        scheduledDay: day,
        inbox: false));
    return db;
  }

  testWidgets('small phone reviews and applies a plan from Calendar',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(fixture))!;
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: ProductivityCalendarPage(
            repository: CalendarEventRepository(db),
            taskRepository: TaskRepository(db),
            options: options,
            clock: () => now)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan this day'));
    await tester.pumpAndSettle();
    expect(find.byType(DailyPlanningPage), findsOneWidget);
    expect(find.text('Apply plan').hitTestable(), findsOneWidget);
    expect(
        (await tester.runAsync(() => db.get(RecordKind.task, 'report')))!
            .fields['scheduledAt'],
        isNull);
    await tester.tap(find.text('Apply plan'));
    await tester.pumpAndSettle();
    final saved =
        (await tester.runAsync(() => db.get(RecordKind.task, 'report')))!;
    expect(saved.fields['scheduledAt'], '2026-11-09T09:00:00.000Z');
    expect(find.byType(DailyPlanningPage), findsNothing);
    expect(find.byTooltip('Show agenda'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed calendar prevents saving until the owner reviews again',
      (tester) async {
    final db = (await tester.runAsync(fixture))!;
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: DailyPlanningPage(
            repository: DailyPlanningRepository(db, clock: () => now),
            day: day,
            options: options)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => CalendarEventRepository(db).create(
        CalendarEvent(
            id: 'new-meeting',
            workspaceId: 'personal',
            title: 'New meeting',
            start: DateTime.utc(2026, 11, 9, 9),
            end: DateTime.utc(2026, 11, 9, 10),
            timeZone: 'UTC')));
    await tester.tap(find.text('Apply plan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tasks, events or preferences changed.'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Apply plan'))
            .onPressed,
        isNull);
    expect(
        (await tester.runAsync(() => db.get(RecordKind.task, 'report')))!
            .fields['scheduledAt'],
        isNull);
    await tester.tap(find.byTooltip('Refresh plan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('10:00'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Apply plan'))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated DST hour shows both offsets and elapsed effort',
      (tester) async {
    final fallDay = CalendarDay(2026, 11, 1);
    final fallOptions = ExperienceOptions(
        language: 'en',
        timeZone: 'America/New_York',
        workdayStartsAt: 90,
        workdayEndsAt: 180,
        workingDays: [7],
        dailyCapacityMinutes: 120,
        completedOnboarding: true,
        use24HourClock: true);
    final db = (await tester.runAsync(() async {
      final db = await ProductivityDatabase.open(
          uid: 'fall-plan-ui',
          factory: databaseFactoryMemory,
          path: 'fall-plan-ui-${sequence++}');
      await ExperienceRepository(db).completeOnboarding(fallOptions);
      await TaskRepository(db).createTask(ProductivityTask(
          id: 'fall-work',
          workspaceId: 'personal',
          title: 'Review notes',
          scheduledDay: fallDay,
          estimatedMinutes: 30,
          inbox: false));
      return db;
    }))!;
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: DailyPlanningPage(
            repository: DailyPlanningRepository(db,
                clock: () => DateTime.utc(2026, 10, 31)),
            day: fallDay,
            options: fallOptions)));
    await tester.pumpAndSettle();
    expect(find.text('01:30 EDT–01:00 EST'), findsOneWidget);
    expect(find.text('30 min · Personal · Normal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
