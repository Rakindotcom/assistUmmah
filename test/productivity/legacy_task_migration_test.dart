import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/legacy_task_migration.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';

void main() {
  var sequence = 0;
  late ProductivityDatabase db;
  setUp(() async {
    db = await ProductivityDatabase.open(
        uid: 'alice',
        factory: databaseFactoryMemory,
        path: 'migration-${sequence++}');
  });
  tearDown(() => db.close());
  Map<String, Object?> item(String id, String text,
          {bool complete = false,
          String day = '2026-10-30',
          String series = '',
          String section = 'mustDo'}) =>
      {
        'id': id,
        'text': text,
        'completed': complete,
        'createdAt': '2026-10-25T10:00:00',
        'dateCreated': day,
        'dueDate': day,
        'section': section,
        'recurrenceId': series,
      };
  Map<String, Object?> source() => {
        'productivityMigrationVersion': 1,
        'dateUpdated': '2026-10-30',
        'todayTasks': {
          'mustDo': [
            item('proposal', 'Write proposal'),
            item('series:2026-10-30', 'Read', series: 'series', complete: true)
          ],
          'goodToDo': []
        },
        'missedTasks': {
          'mustDo': [item('missed', 'Old unfinished task', day: '2026-10-27')],
          'goodToDo': []
        },
        'recurringTasks': [
          {
            'id': 'series',
            'text': 'Read',
            'repeat': 'daily',
            'section': 'mustDo',
            'startDate': '2026-10-25'
          }
        ],
        'scheduledTasks': [
          item('future', 'Next week', day: '2026-11-03', section: 'goodToDo')
        ],
        'unknownMetadata': {'retained': true},
      };
  Matcher failure(String code) =>
      isA<LegacyMigrationFailure>().having((e) => e.code, 'code', code);

  test(
      'one-time import retains legacy history and separate recurring completions',
      () async {
    final raw = source();
    final migration = LegacyTaskMigration.prepare(raw);
    expect(migration.taskCount, 4);
    expect(migration.occurrenceCount, 1);
    await migration.apply(db);
    expect(await db.list(kind: RecordKind.task), hasLength(4));
    final recurring = LegacyTaskMigration.seriesId('series');
    final repository = TaskRepository(db);
    final occurrences = await repository.occurrences(
        'personal', CalendarDay(2026, 10, 30), CalendarDay(2026, 10, 31));
    expect(occurrences.first.status, TaskStatus.completed);
    expect(occurrences.last.status, TaskStatus.notStarted);
    expect((await db.get(RecordKind.task, recurring))!.fields['status'],
        'notStarted');
    expect(occurrences.first.completedAt, isNull,
        reason: 'Legacy data did not record an actual completion instant.');
    final future = ProductivityTask.fromRecord(
        (await db.get(RecordKind.task, LegacyTaskMigration.taskId('future')))!);
    expect(future.scheduledDay, CalendarDay(2026, 11, 3));
    expect(future.deadline, isNull,
        reason: 'A legacy schedule is not a hard deadline.');
    final missed =
        (await db.get(RecordKind.task, LegacyTaskMigration.taskId('missed')))!;
    expect(missed.fields['legacyBucket'], 'missedTasks');
    final parts = await db.list(kind: RecordKind.note);
    parts.sort((a, b) =>
        (a.fields['partIndex'] as int).compareTo(b.fields['partIndex'] as int));
    expect(
        jsonDecode(parts.map((r) => r.fields['body'] as String).join()), raw);
    expect(
        (await db.get(RecordKind.workspace, LegacyTaskMigration.checkpointId))!
            .fields['complete'],
        isTrue);
  });

  test(
      'interrupted batches replay without reverting edits or duplicating records',
      () async {
    final plan = LegacyTaskMigration.prepare(source());
    await db.mutateBatch(plan.records.take(2).toList());
    final id = LegacyTaskMigration.taskId('proposal');
    await TaskRepository(db).editTask(id, {'title': 'User renamed this'});
    await plan.apply(db);
    final count = (await db.pending()).length;
    await plan.apply(db);
    expect((await db.get(RecordKind.task, id))!.fields['title'],
        'User renamed this');
    expect(await db.pending(), hasLength(count));
    expect(await db.list(kind: RecordKind.task), hasLength(4));
  });

  test('changed immutable source is rejected after the final checkpoint',
      () async {
    await LegacyTaskMigration.prepare(source()).apply(db);
    final changed = source()..['unknownMetadata'] = 'changed';
    await expectLater(LegacyTaskMigration.prepare(changed).apply(db),
        throwsA(failure('source-changed-after-cutover')));
  });

  test('source validation finishes before any record or checkpoint is written',
      () async {
    expect(
        () => LegacyTaskMigration.prepare(
            {...source(), 'productivityMigrationVersion': null}),
        throwsA(failure('source-not-fenced')));
    final bad = source()
      ..['scheduledTasks'] = [item('bad-date', 'Bad', day: '2026-02-30')];
    expect(() => LegacyTaskMigration.prepare(bad), throwsFormatException);
    expect(await db.list(), isEmpty);
    expect(await db.pending(), isEmpty);
    final duplicate = source()
      ..['scheduledTasks'] = [item('proposal', 'Conflicting text')];
    expect(() => LegacyTaskMigration.prepare(duplicate),
        throwsA(failure('conflicting-source-identity')));
    expect(await db.list(), isEmpty);
  });

  test(
      'long Unicode content is preserved in descriptions and lossless archive chunks',
      () async {
    final text = List.filled(600, 'পথ🙂').join();
    final raw = source()..['scheduledTasks'] = [item('long', text)];
    raw['largeUnknownField'] = List.filled(12000, '🙂').join();
    final plan = LegacyTaskMigration.prepare(raw);
    await plan.apply(db);
    final record =
        (await db.get(RecordKind.task, LegacyTaskMigration.taskId('long')))!;
    final task = ProductivityTask.fromRecord(record);
    expect(task.title.length, lessThanOrEqualTo(500));
    expect(task.description, text);
    final parts = await db.list(kind: RecordKind.note);
    expect(parts.length, greaterThan(1));
    parts.sort((a, b) =>
        (a.fields['partIndex'] as int).compareTo(b.fields['partIndex'] as int));
    final recovered = parts.map((r) => r.fields['body'] as String).join();
    expect(utf8.decode(utf8.encode(recovered)), canonicalJson(raw));
  });

  test('orphan materialized series remain recoverable standalone tasks',
      () async {
    final raw = source()..['recurringTasks'] = [];
    final plan = LegacyTaskMigration.prepare(raw);
    await plan.apply(db);
    final record = (await db.get(
        RecordKind.task, LegacyTaskMigration.taskId('series:2026-10-30')))!;
    expect(record.fields['status'], 'completed');
    expect((record.fields['legacy'] as Map)['recurrenceId'], 'series');
  });
}
