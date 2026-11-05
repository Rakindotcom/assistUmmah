import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/calendar_event_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_event.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/ui/calendar_page.dart';
import 'package:ummah_assist/src/productivity/ui/calendar_day_timeline.dart';

void main() {
  testWidgets('mobile calendar flags overlaps and edits a saved event',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = await tester.runAsync(() => ProductivityDatabase.open(
        uid: 'calendar-ui',
        factory: databaseFactoryMemory,
        path: 'calendar-mobile'));
    addTearDown(db!.close);
    final repo = CalendarEventRepository(db);
    await tester.runAsync(() async {
      await repo.create(CalendarEvent(
          id: 'a',
          workspaceId: 'personal',
          title: 'Doctor visit',
          start: DateTime.utc(2026, 11, 5, 9),
          end: DateTime.utc(2026, 11, 5, 10),
          timeZone: 'Asia/Dhaka'));
      await repo.create(CalendarEvent(
          id: 'b',
          workspaceId: 'work',
          title: 'Team meeting',
          start: DateTime.utc(2026, 11, 5, 9, 30),
          end: DateTime.utc(2026, 11, 5, 11),
          timeZone: 'Asia/Dhaka'));
    });
    final options = ExperienceOptions(
        language: 'en',
        timeZone: 'Asia/Dhaka',
        modules: [WorkspaceModule.personal, WorkspaceModule.work]);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: ProductivityCalendarPage(
            repository: repo,
            options: options,
            clock: () => DateTime.utc(2026, 11, 5))));
    await tester.pumpAndSettle();
    expect(find.text('Doctor visit'), findsOneWidget);
    expect(find.text('Team meeting'), findsOneWidget);
    expect(find.textContaining('Overlaps another event'), findsNWidgets(2));
    await tester.tap(find.text('Doctor visit'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => repo.edit('a', {'notes': 'Edited elsewhere'}));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'), 'Dentist appointment');
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Save event'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    final saved =
        (await tester.runAsync(() => db.get(RecordKind.calendarEvent, 'a')))!;
    expect(saved.fields['title'], 'Dentist appointment');
    await tester.runAsync(() => repo.watchEvents().firstWhere((events) =>
        events.any((event) =>
            event.id == 'a' && event.title == 'Dentist appointment')));
    await tester.pumpAndSettle();
    expect(find.text('Dentist appointment'), findsOneWidget);
    expect(
        (await tester.runAsync(() => db.get(RecordKind.calendarEvent, 'a')))!
            .fields['notes'],
        'Edited elsewhere');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bangla date and workspace labels use localized text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(() => ProductivityDatabase.open(
        uid: 'calendar-bangla',
        factory: databaseFactoryMemory,
        path: 'calendar-bangla')))!;
    addTearDown(db.close);
    await tester.runAsync(() => CalendarEventRepository(db).create(
        CalendarEvent(
            id: 'visit',
            workspaceId: 'personal',
            title: 'ডাক্তার দেখানো',
            start: DateTime.utc(2026, 11, 5, 9),
            end: DateTime.utc(2026, 11, 5, 10),
            timeZone: 'Asia/Dhaka')));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ProductivityCalendarPage(
            repository: CalendarEventRepository(db),
            options: ExperienceOptions(
                language: 'bn', timeZone: 'Asia/Dhaka', use24HourClock: true),
            clock: () => DateTime.utc(2026, 11, 5))));
    await tester.pumpAndSettle();
    expect(find.text('২০২৬-১১-০৫'), findsOneWidget);
    expect(find.textContaining('ব্যক্তিগত'), findsOneWidget);
    expect(find.textContaining('১৫'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hourly timeline places overlapping events in separate lanes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(() => ProductivityDatabase.open(
        uid: 'calendar-timeline',
        factory: databaseFactoryMemory,
        path: 'calendar-timeline')))!;
    addTearDown(db.close);
    final repo = CalendarEventRepository(db);
    await tester.runAsync(() async {
      await repo.create(CalendarEvent(
          id: 'left',
          workspaceId: 'personal',
          title: 'First meeting',
          start: DateTime.utc(2026, 11, 5, 9),
          end: DateTime.utc(2026, 11, 5, 10),
          timeZone: 'Asia/Dhaka'));
      await repo.create(CalendarEvent(
          id: 'right',
          workspaceId: 'personal',
          title: 'Second meeting',
          start: DateTime.utc(2026, 11, 5, 9, 30),
          end: DateTime.utc(2026, 11, 5, 10, 30),
          timeZone: 'Asia/Dhaka'));
    });
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: ProductivityCalendarPage(
            repository: repo,
            options: ExperienceOptions(language: 'en', timeZone: 'Asia/Dhaka'),
            clock: () => DateTime.utc(2026, 11, 5))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show hourly timeline'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('calendar-timeline-grid')), findsOneWidget);
    final first =
        tester.getTopLeft(find.byKey(const ValueKey('calendar-event-left')));
    final second =
        tester.getTopLeft(find.byKey(const ValueKey('calendar-event-right')));
    expect(first.dx, lessThan(second.dx));
    expect(first.dy, lessThan(second.dy));
    expect(find.byKey(const ValueKey('calendar-event-left')).hitTestable(),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-event-left')));
    await tester.pumpAndSettle();
    expect(find.text('Edit event'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hourly grid reflects 23 and 25 hour daylight-saving days',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> show(CalendarDay day) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarDayTimeline(
                day: day,
                events: const [],
                options: ExperienceOptions(
                    language: 'en',
                    timeZone: 'America/New_York',
                    use24HourClock: true),
                onOpen: (_) {}))));
    await show(CalendarDay(2026, 3, 8));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('calendar-timeline-grid')))
            .height,
        23 * CalendarDayTimeline.pixelsPerHour + 24);
    expect(find.textContaining('03:00 EDT'), findsOneWidget);
    expect(find.textContaining('02:00 EST'), findsNothing);
    await show(CalendarDay(2026, 11, 1));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('calendar-timeline-grid')))
            .height,
        25 * CalendarDayTimeline.pixelsPerHour + 24);
    expect(find.textContaining('01:00 EDT'), findsOneWidget);
    expect(find.textContaining('01:00 EST'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hourly timeline shows estimated task blocks and opens a task',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(() => ProductivityDatabase.open(
        uid: 'calendar-task',
        factory: databaseFactoryMemory,
        path: 'calendar-task')))!;
    addTearDown(db.close);
    final tasks = TaskRepository(db);
    await tester.runAsync(() async {
      await tasks.createTask(ProductivityTask(
          id: 'planned',
          workspaceId: 'personal',
          title: 'Write report',
          scheduledAt: DateTime.utc(2026, 11, 5, 9),
          estimatedMinutes: 90,
          inbox: false));
      await tasks.createTask(ProductivityTask(
          id: 'unestimated',
          workspaceId: 'personal',
          title: 'Unestimated',
          scheduledAt: DateTime.utc(2026, 11, 5, 10),
          inbox: false));
    });
    ProductivityTask? opened;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ProductivityCalendarPage(
            repository: CalendarEventRepository(db),
            taskRepository: tasks,
            onOpenTask: (task) => opened = task,
            options: ExperienceOptions(language: 'en', timeZone: 'Asia/Dhaka'),
            clock: () => DateTime.utc(2026, 11, 5, 9))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show hourly timeline'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-task-planned')).hitTestable(),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('calendar-task-unestimated')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-task-planned')));
    expect(opened?.id, 'planned');
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline clips a cross-midnight event at the day boundary',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final event = CalendarEvent(
        id: 'overnight',
        workspaceId: 'personal',
        title: 'Night shift',
        start: DateTime.utc(2026, 11, 4, 23, 30),
        end: DateTime.utc(2026, 11, 5, 1, 30),
        timeZone: 'UTC');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarDayTimeline(
                day: CalendarDay(2026, 11, 5),
                events: [event],
                options: ExperienceOptions(language: 'en', timeZone: 'UTC'),
                now: DateTime.utc(2026, 11, 5),
                onOpen: (_) {}))));
    final grid =
        tester.getTopLeft(find.byKey(const ValueKey('calendar-timeline-grid')));
    final block = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-event-overnight')));
    expect(block.dy - grid.dy, 6);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('calendar-event-overnight')))
            .height,
        90 * CalendarDayTimeline.pixelsPerHour / 60 - 4);
    expect(tester.takeException(), isNull);
  });
}
