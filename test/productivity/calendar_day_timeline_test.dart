import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_event.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/ui/calendar_day_timeline.dart';

void main() {
  testWidgets('adjacent short events keep separate readable tap targets',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final events = [
      for (var index = 0; index < 2; index++)
        CalendarEvent(
            id: 'short-$index',
            workspaceId: 'personal',
            title: 'Short meeting $index',
            start: DateTime.utc(2026, 11, 5, 9, index * 5),
            end: DateTime.utc(2026, 11, 5, 9, (index + 1) * 5),
            timeZone: 'UTC'),
    ];
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: Scaffold(
            body: CalendarDayTimeline(
                day: CalendarDay(2026, 11, 5),
                events: events,
                options: ExperienceOptions(
                    language: 'en', timeZone: 'UTC', use24HourClock: true),
                now: DateTime.utc(2026, 11, 5, 8, 30),
                onOpen: (event) => opened.add(event.id)))));
    final first = find.byKey(const ValueKey('calendar-event-short-0'));
    final second = find.byKey(const ValueKey('calendar-event-short-1'));
    expect(tester.getRect(first).overlaps(tester.getRect(second)), isFalse);
    expect(tester.getSize(first).height, greaterThanOrEqualTo(48));
    expect(
        tester
            .getSize(
                find.byKey(const ValueKey('calendar-duration-event-short-0')))
            .height,
        closeTo(6, .001));
    expect(find.text('09:00–09:05'), findsOneWidget);
    expect(find.text('09:05–09:10'), findsOneWidget);
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.ensureVisible(second);
    await tester.tap(second);
    expect(opened, ['short-0', 'short-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live current-time marker refreshes each minute and on resume',
      (tester) async {
    var current = DateTime.utc(2026, 11, 5, 9, 0, 10);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarDayTimeline(
                day: CalendarDay(2026, 11, 5),
                events: const [],
                options: ExperienceOptions(language: 'en', timeZone: 'UTC'),
                clock: () => current,
                onOpen: (_) {}))));
    double offset() =>
        tester
            .getTopLeft(find.byKey(const ValueKey('calendar-timeline-now')))
            .dy -
        tester
            .getTopLeft(find.byKey(const ValueKey('calendar-timeline-grid')))
            .dy;
    final initial = offset();
    current = current.add(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 50));
    expect(offset() - initial, closeTo(1.2, .001));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    current = current.add(const Duration(hours: 2));
    await tester.pump(const Duration(hours: 2));
    expect(offset() - initial, closeTo(1.2, .001));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(offset() - initial, closeTo(145.2, .001));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('last-minute event retains its full tap target below midnight',
      (tester) async {
    final event = CalendarEvent(
        id: 'last-minute',
        workspaceId: 'personal',
        title: 'Final reminder',
        start: DateTime.utc(2026, 11, 5, 23, 59),
        end: DateTime.utc(2026, 11, 6),
        timeZone: 'UTC');
    String? opened;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarDayTimeline(
                day: CalendarDay(2026, 11, 5),
                events: [event],
                options: ExperienceOptions(language: 'en', timeZone: 'UTC'),
                now: DateTime.utc(2026, 11, 5, 23),
                onOpen: (value) => opened = value.id))));
    final block = find.byKey(const ValueKey('calendar-event-last-minute'));
    await tester.ensureVisible(block);
    final grid =
        tester.getRect(find.byKey(const ValueKey('calendar-timeline-grid')));
    final rect = tester.getRect(block);
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(rect.bottom, lessThanOrEqualTo(grid.bottom));
    await tester.tap(block);
    expect(opened, 'last-minute');
    expect(tester.takeException(), isNull);
  });

  testWidgets('fixed snapshots do not create live clock updates',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarDayTimeline(
                day: CalendarDay(2026, 11, 5),
                events: const [],
                options: ExperienceOptions(language: 'en', timeZone: 'UTC'),
                now: DateTime.utc(2026, 11, 5, 9),
                clock: () {
                  reads++;
                  return DateTime.utc(2026, 11, 5, 12);
                },
                onOpen: (_) {}))));
    final before =
        tester.getTopLeft(find.byKey(const ValueKey('calendar-timeline-now')));
    await tester.pump(const Duration(hours: 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
        tester.getTopLeft(find.byKey(const ValueKey('calendar-timeline-now'))),
        before);
    expect(reads, 0);
    expect(tester.takeException(), isNull);
  });
}
