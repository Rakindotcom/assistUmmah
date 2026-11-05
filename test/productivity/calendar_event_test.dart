import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/calendar_event_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/workspace_backup.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_event.dart';
import 'package:ummah_assist/src/productivity/domain/planning_time_zone.dart';

void main() {
  var sequence = 0;
  late ProductivityDatabase db;
  late CalendarEventRepository events;
  setUp(() async {
    db = await ProductivityDatabase.open(
        uid: 'alice',
        factory: databaseFactoryMemory,
        path: 'calendar-events-${sequence++}');
    events = CalendarEventRepository(db);
  });
  tearDown(() => db.close());

  CalendarEvent event(String id,
          {DateTime? start, DateTime? end, String workspace = 'personal'}) =>
      CalendarEvent(
          id: id,
          workspaceId: workspace,
          title: 'Visit',
          start: start ?? DateTime.utc(2026, 11, 5, 9),
          end: end ?? DateTime.utc(2026, 11, 5, 10),
          timeZone: 'Asia/Dhaka');

  test('local events round trip through the outbox and backup validator',
      () async {
    await events.create(event('visit'));
    final record = (await db.get(RecordKind.calendarEvent, 'visit'))!;
    expect(record.fields['start'], '2026-11-05T09:00:00.000Z');
    expect(CalendarEvent.fromRecord(record).title, 'Visit');
    expect(await db.pending(), hasLength(1));
    WorkspaceBackup.validateRecords([record]);
    final archive = await db.exportArchive();
    final copy = await ProductivityDatabase.open(
        uid: 'alice',
        factory: databaseFactoryMemory,
        path: 'calendar-events-copy-${sequence++}');
    addTearDown(copy.close);
    expect(
        await copy.importArchive(archive,
            validateRecords: WorkspaceBackup.validateRecords),
        1);
    expect((await copy.get(RecordKind.calendarEvent, 'visit'))!.fields['title'],
        'Visit');
  });

  test('edits validate combined interval, preserve other fields, and no-op',
      () async {
    await events.create(event('visit'));
    await events.edit('visit', {'notes': 'Bring documents'});
    final count = (await db.pending()).length;
    await events.edit('visit', {'notes': 'Bring documents'});
    expect(await db.pending(), hasLength(count));
    await expectLater(events.edit('visit', {'end': '2026-11-05T08:00:00.000Z'}),
        throwsFormatException);
    await expectLater(events.edit('visit', {'start': '2026-11-05T10:00:00'}),
        throwsFormatException);
    expect((await db.get(RecordKind.calendarEvent, 'visit'))!.fields['notes'],
        'Bring documents');
    expect(await db.pending(), hasLength(count));
  });

  test('half-open overlap and soft deletion', () async {
    final first = event('a');
    final adjacent = event('b',
        start: DateTime.utc(2026, 11, 5, 10),
        end: DateTime.utc(2026, 11, 5, 11));
    final overlapping = event('c',
        start: DateTime.utc(2026, 11, 5, 9, 30),
        end: DateTime.utc(2026, 11, 5, 10, 30));
    expect(first.overlaps(adjacent), isFalse);
    expect(first.overlaps(overlapping), isTrue);
    await events.create(first);
    await events.delete('a');
    expect((await db.get(RecordKind.calendarEvent, 'a'))!.deleted, isTrue);
    final count = (await db.pending()).length;
    await events.delete('a');
    expect(await db.pending(), hasLength(count));
  });

  test('DST gaps and overlaps have explicit candidate instants', () {
    expect(
        PlanningTimeZone.candidates(
            CalendarDay(2026, 3, 8), 2, 30, 'America/New_York'),
        isEmpty);
    expect(
        PlanningTimeZone.candidates(
            CalendarDay(2026, 11, 1), 1, 30, 'America/New_York'),
        hasLength(2));
  });
}
