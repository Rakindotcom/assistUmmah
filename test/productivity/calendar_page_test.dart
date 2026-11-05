import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/calendar_event_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_event.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/ui/calendar_page.dart';

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
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'), 'Dentist appointment');
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Save event'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    expect(find.text('Dentist appointment'), findsOneWidget);
    expect(
        (await tester.runAsync(() => db.get(RecordKind.calendarEvent, 'a')))!
            .fields['title'],
        'Dentist appointment');
    expect(tester.takeException(), isNull);
  });
}
