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
    expect((record.fields['interval'] as Map)['start'],
        '2026-11-05T09:00:00.000000Z');
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

  test('concurrent valid time edits cannot merge into an invalid interval',
      () async {
    await events.create(event('meeting'));
    final base = (await db.get(RecordKind.calendarEvent, 'meeting'))!;
    WorkspaceRecord changed(int counter, DateTime start, DateTime end) {
      final value = event('meeting', start: start, end: end);
      return WorkspaceRecord(
          ownerId: db.uid,
          kind: RecordKind.calendarEvent,
          id: 'meeting',
          fields: {...base.fields, 'interval': value.toFields()['interval']},
          clocks: {
            ...base.clocks,
            'interval': VersionStamp(counter, 'other-device')
          },
          revision: counter,
          modifiedAtMillis: counter);
    }

    final laterStart = changed(
        10, DateTime.utc(2026, 11, 5, 9, 30), DateTime.utc(2026, 11, 5, 10));
    final earlierEnd = changed(
        11, DateTime.utc(2026, 11, 5, 9), DateTime.utc(2026, 11, 5, 9, 15));
    await db.acceptPage([laterStart, earlierEnd], null);
    final merged = (await db.get(RecordKind.calendarEvent, 'meeting'))!;
    expect(
        CalendarEvent.fromRecord(merged).end, DateTime.utc(2026, 11, 5, 9, 15));
    expect(merged.clocks['interval'], VersionStamp(11, 'other-device'));
  });

  test('invalid remote event page rolls back every record and cursor',
      () async {
    await events.create(event('meeting'));
    final base = (await db.get(RecordKind.calendarEvent, 'meeting'))!;
    final invalid = WorkspaceRecord(
        ownerId: db.uid,
        kind: RecordKind.calendarEvent,
        id: 'meeting',
        fields: {
          ...base.fields,
          'interval': {
            'start': '2026-11-05T10:00:00.000Z',
            'end': '2026-11-05T09:00:00.000Z',
            'timeZone': 'Asia/Dhaka',
          }
        },
        clocks: {...base.clocks, 'interval': VersionStamp(20, 'other-device')},
        revision: 20,
        modifiedAtMillis: 20);
    final another = event('another');
    final fields = {...another.toFields(), '_deleted': false};
    final valid = WorkspaceRecord(
        ownerId: db.uid,
        kind: RecordKind.calendarEvent,
        id: another.id,
        fields: fields,
        clocks: {
          for (final key in fields.keys) key: VersionStamp(2, 'other-device')
        },
        revision: 1,
        modifiedAtMillis: 2);
    await expectLater(
        db.acceptPage(
            [valid, invalid], const SyncCursor(4, 0, 'calendarEvent--meeting')),
        throwsFormatException);
    expect(await db.get(RecordKind.calendarEvent, 'another'), isNull);
    expect((await db.get(RecordKind.calendarEvent, 'meeting'))!.fields,
        base.fields);
    expect(await db.cursor, isNull);
  });

  test('legacy preview events upgrade their interval when edited or deleted',
      () async {
    for (final id in ['edit-legacy', 'delete-legacy']) {
      await db.mutate(
          kind: RecordKind.calendarEvent,
          id: id,
          workspaceId: 'personal',
          patch: {
            'title': 'Preview event',
            'start': '2026-11-05T09:00:00.000Z',
            'end': '2026-11-05T10:00:00.000Z',
            'timeZone': 'Asia/Dhaka',
          });
    }
    expect(
        CalendarEvent.fromRecord(
                (await db.get(RecordKind.calendarEvent, 'edit-legacy'))!)
            .title,
        'Preview event');
    await events.edit('edit-legacy', {'notes': 'Keep'});
    final edited = (await db.get(RecordKind.calendarEvent, 'edit-legacy'))!;
    expect((edited.fields['interval'] as Map)['start'],
        '2026-11-05T09:00:00.000000Z');
    await events.delete('delete-legacy');
    final deleted = (await db.get(RecordKind.calendarEvent, 'delete-legacy'))!;
    expect(deleted.deleted, isTrue);
    expect(deleted.fields['interval'], isA<Map>());
  });

  test('UTC microseconds have fixed-width ordering in the stored interval', () {
    final early = event('early',
        start: DateTime.utc(2026, 11, 5, 9),
        end: DateTime.utc(2026, 11, 5, 10));
    final later = event('later',
        start: DateTime.utc(2026, 11, 5, 9, 0, 0, 0, 1),
        end: DateTime.utc(2026, 11, 5, 10));
    final first = (early.toFields()['interval'] as Map)['start'] as String;
    final second = (later.toFields()['interval'] as Map)['start'] as String;
    expect(first, '2026-11-05T09:00:00.000000Z');
    expect(second, '2026-11-05T09:00:00.000001Z');
    expect(first.compareTo(second), lessThan(0));
  });

  test('reviewed calendar failure replaces stale queue without losing audit',
      () async {
    await events.create(event('meeting'));
    final rejected = (await db.pending()).single;
    await db.recordFailure(rejected, 'invalid-calendar-event', permanent: true);
    await events.edit('meeting', {'title': 'Corrected meeting'});
    final corrected = (await db.queued()).last;
    final retry = await db.resubmitCalendarEventFailure('meeting');
    expect((await db.pending()).single.id, retry.id);
    expect(retry.patch['title'], 'Corrected meeting');
    expect(retry.patch['interval'], isA<Map>());
    expect(
        CalendarEvent.fromRecord(applyRecordOperation(null, retry).record)
            .title,
        'Corrected meeting');
    final history = await db.history(RecordKind.calendarEvent, 'meeting');
    expect(
        history
            .firstWhere((entry) => entry['id'] == rejected.id)['supersededBy'],
        retry.id);
    expect(
        history
            .firstWhere((entry) => entry['id'] == corrected.id)['supersededBy'],
        retry.id);
  });
}
