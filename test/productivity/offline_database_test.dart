import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/calendar_event_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_remote.dart';
import 'package:ummah_assist/src/productivity/data/sync_coordinator.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/data/workspace_backup.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_event.dart';

void main() {
  var sequence = 0;
  Future<ProductivityDatabase> memory({String uid = 'alice', String? path}) =>
      ProductivityDatabase.open(
          uid: uid,
          factory: databaseFactoryMemory,
          path: path ?? 'test-${sequence++}');
  Future<WorkspaceRecord> task(ProductivityDatabase db, String id,
          {String title = 'Write proposal'}) =>
      db.mutate(
          kind: RecordKind.task,
          id: id,
          workspaceId: 'personal',
          patch: {'title': title, 'status': 'open'});

  Future<(WorkspaceRecord, FieldConflict)> createTitleConflict(
      ProductivityDatabase db) async {
    await TaskRepository(db).createTask(ProductivityTask(
        id: 'proposal', workspaceId: 'personal', title: 'Write proposal'));
    final created = (await db.get(RecordKind.task, 'proposal'))!;
    final create = (await db.pending()).single;
    final canonical = WorkspaceRecord(
        ownerId: db.uid,
        kind: RecordKind.task,
        id: created.id,
        fields: created.fields,
        clocks: created.clocks,
        revision: 1,
        modifiedAtMillis: created.modifiedAtMillis);
    await db.acknowledge(create, canonical);
    await db.mutate(
        kind: RecordKind.task,
        id: 'proposal',
        workspaceId: 'personal',
        patch: {'title': 'My title'});
    final edit = (await db.pending()).single;
    final cloud = WorkspaceRecord(
        ownerId: db.uid,
        kind: RecordKind.task,
        id: created.id,
        fields: {...created.fields, 'title': 'Cloud title'},
        clocks: {...created.clocks, 'title': VersionStamp(25, 'other_device')},
        revision: 2,
        modifiedAtMillis: created.modifiedAtMillis);
    await db.acknowledge(edit, cloud, rejectedFields: ['title']);
    return (cloud, (await db.fieldConflicts()).single);
  }

  test('rejected same-field edit stays reviewable across a real file restart',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('productivity-conflict-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/account.db';
    var db = await ProductivityDatabase.open(
        uid: 'alice', factory: databaseFactoryIo, path: path);
    final (_, conflict) = await createTitleConflict(db);
    expect(conflict.localValue, 'My title');
    expect(conflict.cloudValue, 'Cloud title');
    expect((await db.get(RecordKind.task, 'proposal'))!.fields['title'],
        'Cloud title');
    expect((await db.syncSnapshot()).needsAttention, 1);
    expect((await db.syncSnapshot()).synchronized, isFalse);
    await db.close();
    db = await ProductivityDatabase.open(
        uid: 'alice', factory: databaseFactoryIo, path: path);
    addTearDown(db.close);
    expect((await db.fieldConflicts()).single.toJson(), conflict.toJson());
    await db.keepCloudValue(conflict);
    expect(await db.fieldConflicts(), isEmpty);
    expect((await db.get(RecordKind.task, 'proposal'))!.fields['title'],
        'Cloud title');
    expect((await db.syncSnapshot()).needsAttention, 0);
    expect(
        (await db.history(RecordKind.task, 'proposal')).firstWhere(
            (item) => item['id'] == conflict.operationId)['conflictResolution'],
        'cloud');
  });

  test('reviewed local value gets a fresh clock and can win a later retry',
      () async {
    final db = await memory();
    addTearDown(db.close);
    final (cloud, conflict) = await createTitleConflict(db);
    final retry = await db.retryMyValue(conflict, validate: (_, __) {});
    expect(retry.patch, {'title': 'My title'});
    expect(retry.stamp.counter, greaterThan(conflict.cloudStamp.counter));
    expect(await db.fieldConflicts(), isEmpty);
    expect((await db.pending()).single.id, retry.id);
    final applied = applyRecordOperation(cloud, retry);
    expect(applied.rejectedFields, isEmpty);
    expect(applied.record.fields['title'], 'My title');
    await db.acknowledge(retry, applied.record);
    expect((await db.get(RecordKind.task, 'proposal'))!.fields['title'],
        'My title');
  });

  test('a newer cloud value invalidates an old review selection', () async {
    final db = await memory();
    addTearDown(db.close);
    final (cloud, conflict) = await createTitleConflict(db);
    final newer = WorkspaceRecord(
        ownerId: db.uid,
        kind: cloud.kind,
        id: cloud.id,
        fields: {...cloud.fields, 'title': 'New cloud title'},
        clocks: {...cloud.clocks, 'title': VersionStamp(30, 'other_device')},
        revision: 3,
        modifiedAtMillis: cloud.modifiedAtMillis);
    await db.acceptPage([newer], null);
    await expectLater(
        db.retryMyValue(conflict, validate: (_, __) {}), throwsStateError);
    await expectLater(db.keepCloudValue(conflict), throwsStateError);
    final refreshed = (await db.fieldConflicts()).single;
    expect(refreshed.cloudValue, 'New cloud title');
    await db.retryMyValue(refreshed, validate: (_, __) {});
    expect((await db.pending()).single.stamp.counter, 31);
  });

  test('failed domain validation leaves the conflict and queue untouched',
      () async {
    final db = await memory();
    addTearDown(db.close);
    final (_, conflict) = await createTitleConflict(db);
    await expectLater(
        db.retryMyValue(conflict,
            validate: (_, __) => throw const FormatException('invalid task')),
        throwsFormatException);
    expect((await db.fieldConflicts()).single.toJson(), conflict.toJson());
    expect(await db.pending(), isEmpty);
    expect((await db.get(RecordKind.task, 'proposal'))!.fields['title'],
        'Cloud title');
  });

  test('a later intentional edit clears its old field conflict', () async {
    final db = await memory();
    addTearDown(db.close);
    await createTitleConflict(db);
    await db.mutate(
        kind: RecordKind.task,
        id: 'proposal',
        workspaceId: 'personal',
        patch: {'title': 'New intentional title'});
    expect(await db.fieldConflicts(), isEmpty);
    expect((await db.pending()).single.patch['title'], 'New intentional title');
  });

  test('edit and outbox survive a real file-backed close and reopen', () async {
    final directory =
        await Directory.systemTemp.createTemp('productivity-test-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/account.db';
    var db = await ProductivityDatabase.open(
        uid: 'alice', factory: databaseFactoryIo, path: path);
    await task(db, 'proposal');
    final operation = (await db.pending()).single;
    final device = db.deviceId;
    await db.close();
    db = await ProductivityDatabase.open(
        uid: 'alice', factory: databaseFactoryIo, path: path);
    addTearDown(db.close);
    expect(db.deviceId, device);
    expect((await db.get(RecordKind.task, 'proposal'))!.fields['title'],
        'Write proposal');
    expect((await db.pending()).single.fingerprint, operation.fingerprint);
    expect((await db.history(RecordKind.task, 'proposal')).single['source'],
        'local');
  });

  test('a database cannot be reused by another UID', () async {
    final path = 'owner-${sequence++}';
    final db = await memory(path: path);
    await task(db, 'secret');
    await db.close();
    await expectLater(memory(uid: 'bob', path: path), throwsStateError);
    final reopened = await memory(path: path);
    addTearDown(reopened.close);
    expect((await reopened.get(RecordKind.task, 'secret'))!.ownerId, 'alice');
  });

  test('validation failure leaves records, queue and audit unchanged',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await expectLater(
        db.mutate(
            kind: RecordKind.task,
            id: 'bad',
            workspaceId: 'personal',
            patch: {'bad.field': 'private', 'title': 'invalid'}),
        throwsFormatException);
    expect(await db.list(), isEmpty);
    expect(await db.pending(), isEmpty);
    expect(await db.history(RecordKind.task, 'bad'), isEmpty);
    await task(db, 'good');
    expect((await db.pending()).single.stamp.counter, 1);
  });

  test(
      'rapid edits serialize their logical clocks and preserve every operation',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await task(db, 'proposal');
    await Future.wait(List.generate(
        30,
        (index) => db.mutate(
            kind: RecordKind.task,
            id: 'proposal',
            workspaceId: 'personal',
            patch: {'title': 'Draft $index'})));
    final operations = await db.queued();
    expect(operations, hasLength(31));
    expect(await db.pending(), hasLength(1));
    expect(operations.map((o) => o.stamp.counter),
        orderedEquals(List.generate(31, (i) => i + 1)));
    expect((await db.get(RecordKind.task, 'proposal'))!.fields['title'],
        'Draft 29');
  });

  test(
      'late acknowledgement cannot replace a newer local edit or clear its outbox',
      () async {
    final db = await memory();
    addTearDown(db.close);
    final first = await task(db, 'proposal');
    final operation = (await db.pending()).single;
    await db.mutate(
        kind: RecordKind.task,
        id: 'proposal',
        workspaceId: 'personal',
        patch: {'title': 'New local title'});
    await db.acknowledge(
        operation,
        WorkspaceRecord(
            ownerId: first.ownerId,
            kind: first.kind,
            id: first.id,
            fields: first.fields,
            clocks: first.clocks,
            revision: 1,
            modifiedAtMillis: first.modifiedAtMillis));
    expect((await db.get(RecordKind.task, 'proposal'))!.fields['title'],
        'New local title');
    expect(await db.pending(), hasLength(1));
    expect((await db.pending()).single.stamp.counter, 2);
  });

  test('independent edits converge in either delivery order', () {
    final a = VersionStamp(1, 'device_a'), b = VersionStamp(2, 'device_b');
    final local = WorkspaceRecord(
        ownerId: 'alice',
        kind: RecordKind.task,
        id: 't',
        fields: {
          'workspaceId': 'personal',
          '_deleted': false,
          'title': 'Local',
          'priority': 1
        },
        clocks: {'workspaceId': a, '_deleted': a, 'title': b, 'priority': a},
        modifiedAtMillis: 1);
    final remote = WorkspaceRecord(
        ownerId: 'alice',
        kind: RecordKind.task,
        id: 't',
        fields: {
          'workspaceId': 'personal',
          '_deleted': false,
          'title': 'Original',
          'priority': 4
        },
        clocks: {'workspaceId': a, '_deleted': a, 'title': a, 'priority': b},
        modifiedAtMillis: 2);
    final one = mergeRecords(local, remote), two = mergeRecords(remote, local);
    expect(one.fields['title'], 'Local');
    expect(one.fields['priority'], 4);
    expect(canonicalJson(one.toJson()), canonicalJson(two.toJson()));
  });

  test(
      'concurrent same-field edits use a stable device tie-break, not wall time',
      () {
    WorkspaceRecord record(String device, String title, int time) {
      final stamp = VersionStamp(2, device);
      return WorkspaceRecord(
          ownerId: 'alice',
          kind: RecordKind.task,
          id: 't',
          fields: {
            'workspaceId': 'personal',
            '_deleted': false,
            'title': title
          },
          clocks: {
            'workspaceId': VersionStamp(1, 'origin'),
            '_deleted': VersionStamp(1, 'origin'),
            'title': stamp
          },
          modifiedAtMillis: time);
    }

    final a = record('a', 'A', 999999), b = record('b', 'B', 1);
    expect(mergeRecords(a, b).fields['title'], 'B');
    expect(mergeRecords(b, a).fields['title'], 'B');
  });

  test(
      'a deleted record stays deleted through stale edits and supports explicit restore',
      () async {
    final db = await memory();
    addTearDown(db.close);
    final original = await task(db, 'proposal');
    await db.mutate(
        kind: RecordKind.task,
        id: 'proposal',
        workspaceId: 'personal',
        patch: {},
        deleted: true);
    await db.acceptPage([original], const SyncCursor(1, 0, 'task--proposal'));
    expect(await db.list(), isEmpty);
    expect((await db.list(includeDeleted: true)).single.deleted, isTrue);
    await db.mutate(
        kind: RecordKind.task,
        id: 'proposal',
        workspaceId: 'personal',
        patch: {},
        deleted: false);
    expect((await db.list()).single.deleted, isFalse);
  });

  test('a mixed-account remote page rolls back all records and its cursor',
      () async {
    final db = await memory(), bob = await memory(uid: 'bob');
    addTearDown(db.close);
    addTearDown(bob.close);
    final valid = await task(db, 'first');
    final invalid = await task(bob, 'second');
    final fresh = await memory();
    addTearDown(fresh.close);
    await expectLater(
        fresh.acceptPage([valid, invalid], const SyncCursor(5, 0, 'last')),
        throwsStateError);
    expect(await fresh.list(), isEmpty);
    expect(await fresh.cursor, isNull);
  });

  test('observing remote clocks advances subsequent local edits', () async {
    final db = await memory();
    addTearDown(db.close);
    final stamp = VersionStamp(100, 'other');
    await db.acceptPage([
      WorkspaceRecord(
          ownerId: 'alice',
          kind: RecordKind.task,
          id: 'remote',
          fields: {
            'workspaceId': 'personal',
            '_deleted': false,
            'title': 'Remote'
          },
          clocks: {'workspaceId': stamp, '_deleted': stamp, 'title': stamp},
          modifiedAtMillis: 1)
    ], null);
    await db.mutate(
        kind: RecordKind.task,
        id: 'remote',
        workspaceId: 'personal',
        patch: {'title': 'Updated'});
    expect((await db.pending()).single.stamp.counter, 101);
  });

  test(
      'record data is deeply immutable and rejects oversized or non-JSON payloads',
      () async {
    final db = await memory();
    addTearDown(db.close);
    final nested = {
      'parts': <String>['first']
    };
    final record = await db.mutate(
        kind: RecordKind.note,
        id: 'n',
        workspaceId: 'personal',
        patch: {'content': nested});
    nested['parts']!.add('not persisted');
    expect((record.fields['content'] as Map)['parts'], ['first']);
    expect(
        () =>
            ((record.fields['content'] as Map)['parts'] as List).add('illegal'),
        throwsUnsupportedError);
    await expectLater(
        db.mutate(
            kind: RecordKind.note,
            id: 'large',
            workspaceId: 'personal',
            patch: {'content': 'a' * 270000}),
        throwsFormatException);
    await expectLater(
        db.mutate(
            kind: RecordKind.note,
            id: 'nan',
            workspaceId: 'personal',
            patch: {'amount': double.nan}),
        throwsFormatException);
  });

  test('fingerprints remain stable across serialization and dictionary order',
      () {
    SyncOperation operation(Map<String, Object?> patch) => SyncOperation(
        id: 'op',
        ownerId: 'alice',
        kind: RecordKind.task,
        recordId: 't',
        patch: patch,
        stamp: VersionStamp(1, 'device'),
        createdAtMillis: 1);
    final a = operation({
      'title': 'A',
      'labels': ['one', 'two']
    });
    final b = operation({
      'labels': ['one', 'two'],
      'title': 'A'
    });
    expect(a.fingerprint, b.fingerprint);
    expect(SyncOperation.fromJson(a.toJson()).fingerprint, a.fingerprint);
  });

  test('frozen accounts reject new edits, remote pages and acknowledgements',
      () async {
    final db = await memory();
    addTearDown(db.close);
    final existing = await task(db, 't');
    final operation = (await db.pending()).single;
    await db.freeze();
    await expectLater(task(db, 'new'), throwsStateError);
    await expectLater(db.acceptPage([existing], null), throwsStateError);
    await expectLater(db.acknowledge(operation, existing), throwsStateError);
    expect(await db.pending(), hasLength(1));
  });

  test('failed operations retain data and persisted exponential retry state',
      () async {
    var now = DateTime.utc(2026, 10, 30);
    final db = await ProductivityDatabase.open(
        uid: 'alice',
        factory: databaseFactoryMemory,
        path: 'retry-${sequence++}',
        clock: () => now);
    addTearDown(db.close);
    await task(db, 't');
    final operation = (await db.pending()).single;
    await db.recordFailure(operation, 'unavailable');
    expect(await db.pending(), isEmpty);
    final failed = (await db.pending(includeDelayed: true)).single;
    expect(failed.attempts, 1);
    expect(failed.retryAtMillis,
        now.add(const Duration(seconds: 5)).millisecondsSinceEpoch);
    now = now.add(const Duration(seconds: 6));
    expect(await db.pending(), hasLength(1));
    await db.recordFailure(failed, 'permission-denied', permanent: true);
    final status = await db.syncSnapshot();
    expect(status.pending, 1);
    expect(status.needsAttention, 1);
    expect(status.failed, 1);
    expect((await db.get(RecordKind.task, 't'))!.fields['title'],
        'Write proposal');
  });

  test('a rejected create blocks later patches while unrelated work syncs',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await task(db, 'conflicted');
    await db.mutate(
        kind: RecordKind.task,
        id: 'conflicted',
        workspaceId: 'personal',
        patch: {'title': 'Edited offline'});
    await task(db, 'independent');
    final remote = _Remote()..rejectedRecordKeys.add('task--conflicted');
    final coordinator = SyncCoordinator(database: db, remote: remote);
    addTearDown(coordinator.dispose);
    await coordinator.sync();
    expect(remote.records.containsKey('task--conflicted'), isFalse);
    expect(
        remote.records['task--independent']!.fields['title'], 'Write proposal');
    expect((await db.attention()).single.recordId, 'conflicted');
    expect((await db.queued()).map((operation) => operation.recordId),
        orderedEquals(['conflicted', 'conflicted']));
    expect(await db.pending(includeDelayed: true), isEmpty);
    expect((await db.syncSnapshot()).needsAttention, 1);
    expect((await db.get(RecordKind.task, 'conflicted'))!.fields['title'],
        'Edited offline');
  });

  test(
      'a late invalid batch mutation rolls back earlier edits and all outbox entries',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await task(db, 'existing');
    await expectLater(
        db.mutateBatch([
          RecordMutation(
              kind: RecordKind.task,
              id: 'new',
              workspaceId: 'personal',
              patch: {'title': 'New'}),
          RecordMutation(
              kind: RecordKind.task,
              id: 'existing',
              workspaceId: 'another',
              patch: {'title': 'Wrong workspace'}),
        ]),
        throwsArgumentError);
    expect(await db.get(RecordKind.task, 'new'), isNull);
    expect((await db.get(RecordKind.task, 'existing'))!.fields['title'],
        'Write proposal');
    expect(await db.pending(), hasLength(1));
  });

  test(
      'create-if-absent migration is safe to repeat and preserves later user edits',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await task(db, 'legacy', title: 'Original');
    await db.mutate(
        kind: RecordKind.task,
        id: 'legacy',
        workspaceId: 'personal',
        patch: {'title': 'Edited'});
    await db.mutate(
        kind: RecordKind.task,
        id: 'legacy',
        workspaceId: 'personal',
        patch: {'title': 'Original'},
        ifAbsent: true);
    expect(
        (await db.get(RecordKind.task, 'legacy'))!.fields['title'], 'Edited');
    expect(await db.queued(), hasLength(2));
    expect(await db.pending(), hasLength(1));
  });

  test(
      'backup round trip preserves unsynced records, deleted notes and history',
      () async {
    final original = await memory(), restored = await memory();
    addTearDown(original.close);
    addTearDown(restored.close);
    await task(original, 'task');
    await original.mutate(
        kind: RecordKind.note,
        id: 'note',
        workspaceId: 'personal',
        patch: {'content': 'Private draft'});
    await original.mutate(
        kind: RecordKind.note,
        id: 'note',
        workspaceId: 'personal',
        patch: {},
        deleted: true);
    final archive = await original.exportArchive();
    expect(await restored.importArchive(archive), 2);
    expect((await restored.get(RecordKind.task, 'task'))!.fields['title'],
        'Write proposal');
    expect((await restored.get(RecordKind.note, 'note'))!.deleted, isTrue);
    expect(await restored.pending(), hasLength(2));
    expect(await restored.history(RecordKind.note, 'note'), hasLength(3));
    expect(await restored.importArchive(archive), 0);
    expect(await restored.pending(), hasLength(2));
  });

  test('backup restores reviewable conflict and accepts old format', () async {
    final original = await memory(), restored = await memory();
    addTearDown(original.close);
    addTearDown(restored.close);
    await createTitleConflict(original);
    final archive = await original.exportArchive();
    final decoded = jsonDecode(archive) as Map<String, dynamic>;
    expect(decoded['formatVersion'], 3);
    expect(decoded['conflicts'], hasLength(1));
    expect(
        await restored.importArchive(archive,
            validateRecords: WorkspaceBackup.validateRecords),
        1);
    final conflict = (await restored.fieldConflicts()).single;
    expect(conflict.localValue, 'My title');
    expect(conflict.cloudValue, 'Cloud title');
    await restored.retryMyValue(conflict, validate: (_, __) {});
    expect(await restored.fieldConflicts(), isEmpty);
    expect((await restored.get(RecordKind.task, 'proposal'))!.fields['title'],
        'My title');

    final legacy = await memory();
    addTearDown(legacy.close);
    final payload = {...decoded}
      ..remove('checksum')
      ..remove('conflicts')
      ..['formatVersion'] = 1;
    final oldArchive = jsonEncode({
      ...payload,
      'checksum': sha256.convert(utf8.encode(canonicalJson(payload))).toString()
    });
    expect(await legacy.importArchive(oldArchive), 1);
    expect((await legacy.get(RecordKind.task, 'proposal'))!.fields['title'],
        'Cloud title');
    expect(await legacy.fieldConflicts(), isEmpty);

    final previous = await memory();
    addTearDown(previous.close);
    final previousPayload = {...decoded}
      ..remove('checksum')
      ..['format'] = 'legacy-workspace'
      ..['formatVersion'] = 2;
    expect(
        await previous.importArchive(jsonEncode({
          ...previousPayload,
          'checksum': sha256
              .convert(utf8.encode(canonicalJson(previousPayload)))
              .toString()
        })),
        1);
    expect(await previous.fieldConflicts(), hasLength(1));
  });

  test('recomputed checksum cannot hide inconsistent conflict values',
      () async {
    final original = await memory(), restored = await memory();
    addTearDown(original.close);
    addTearDown(restored.close);
    await createTitleConflict(original);
    final archive = await original.exportArchive();
    for (final field in ['cloudValue', 'localValue']) {
      final payload = jsonDecode(archive) as Map<String, dynamic>;
      payload.remove('checksum');
      final conflicts = payload['conflicts'] as List;
      (conflicts.single as Map<String, dynamic>)[field] = 'Forged';
      final tampered = jsonEncode({
        ...payload,
        'checksum':
            sha256.convert(utf8.encode(canonicalJson(payload))).toString(),
      });
      await expectLater(
          restored.importArchive(tampered), throwsFormatException);
      expect(await restored.list(), isEmpty);
      expect(await restored.fieldConflicts(), isEmpty);
    }
  });

  test(
      'restore clocks advance beyond archived clocks instead of losing to old cloud data',
      () async {
    final original = await memory(), restored = await memory();
    addTearDown(original.close);
    addTearDown(restored.close);
    await task(original, 'task');
    for (var i = 0; i < 15; i++) {
      await original.mutate(
          kind: RecordKind.task,
          id: 'task',
          workspaceId: 'personal',
          patch: {'title': 'Version $i'});
    }
    await restored.importArchive(await original.exportArchive());
    expect((await restored.pending()).single.stamp.counter, greaterThan(16));
  });

  test(
      'backup integrity, schema, owner and duplicate validation happen before any write',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await task(db, 'task');
    final source = jsonDecode(await db.exportArchive()) as Map<String, dynamic>;
    String checked(Map<String, dynamic> data) {
      final payload = {...data}..remove('checksum');
      return jsonEncode({
        ...payload,
        'checksum':
            sha256.convert(utf8.encode(canonicalJson(payload))).toString()
      });
    }

    final invalid = <String>[
      jsonEncode({...source, 'checksum': 'wrong'}),
      checked({...source, 'ownerId': 'bob'}),
      checked({...source, 'formatVersion': 99}),
      checked({
        ...source,
        'records': [
          ...source['records'] as List,
          ...(source['records'] as List)
        ]
      }),
      checked({
        ...source,
        'history': [
          ...source['history'] as List,
          ...(source['history'] as List)
        ]
      }),
      checked({
        ...source,
        'records': [(source['records'] as List).single..['ownerId'] = 'bob']
      }),
    ];
    for (final archive in invalid) {
      await expectLater(db.importArchive(archive), throwsFormatException);
      expect(await db.pending(), hasLength(1));
      expect((await db.list()).single.id, 'task');
    }
  });

  test(
      'sync status emits the last-success update even when the outbox is empty',
      () async {
    final db = await memory();
    addTearDown(db.close);
    final observed = Completer<SyncSnapshot>();
    final subscription = db.watchSync().listen((state) {
      if (state.lastSuccessMillis != null && !observed.isCompleted) {
        observed.complete(state);
      }
    });
    addTearDown(subscription.cancel);
    await db.recordSyncSuccess();
    expect(
        (await observed.future.timeout(const Duration(seconds: 2)))
            .synchronized,
        isTrue);
  });

  test('deep nesting and integers outside portable precision are rejected',
      () async {
    final db = await memory();
    addTearDown(db.close);
    Object? nested = 'value';
    for (var i = 0; i < 40; i++) {
      nested = [nested];
    }
    await expectLater(
        db.mutate(
            kind: RecordKind.note,
            id: 'deep',
            workspaceId: 'personal',
            patch: {'content': nested}),
        throwsFormatException);
    await expectLater(
        db.mutate(
            kind: RecordKind.goal,
            id: 'large',
            workspaceId: 'personal',
            patch: {'target': 9007199254740992}),
        throwsFormatException);
  });

  test('idempotent retry after a committed remote write loses its response',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await task(db, 't');
    final remote = _Remote()..loseNextResponse = true;
    final coordinator = SyncCoordinator(database: db, remote: remote);
    addTearDown(coordinator.dispose);
    await coordinator.sync();
    expect((await db.syncSnapshot()).pending, 1);
    expect(remote.receipts, hasLength(1));
    await coordinator.sync(force: true);
    expect((await db.syncSnapshot()).pending, 0);
    expect(remote.receipts, hasLength(1));
    expect(remote.records['task--t']!.revision, 1);
    expect(coordinator.errorCode, isNull);
  });

  test(
      'stopping an in-flight sync discards its late response and leaves work retryable',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await task(db, 't');
    final gate = Completer<void>();
    final remote = _Remote()..gate = gate;
    final coordinator = SyncCoordinator(database: db, remote: remote);
    addTearDown(coordinator.dispose);
    final sync = coordinator.sync();
    await remote.started.future;
    coordinator.stop();
    gate.complete();
    await sync;
    expect((await db.syncSnapshot()).pending, 1);
    expect(remote.receipts, hasLength(1));
    final resumed = SyncCoordinator(database: db, remote: remote);
    addTearDown(resumed.dispose);
    await resumed.sync(force: true);
    expect((await db.syncSnapshot()).pending, 0);
    expect(remote.receipts, hasLength(1));
  });

  test('two offline clients converge without losing independent task fields',
      () async {
    final a = await memory(), b = await memory();
    addTearDown(a.close);
    addTearDown(b.close);
    final remote = _Remote();
    final syncA = SyncCoordinator(database: a, remote: remote);
    final syncB = SyncCoordinator(database: b, remote: remote);
    addTearDown(syncA.dispose);
    addTearDown(syncB.dispose);
    await task(a, 'proposal');
    await syncA.sync();
    await syncB.sync();
    await a.mutate(
        kind: RecordKind.task,
        id: 'proposal',
        workspaceId: 'personal',
        patch: {'title': 'Offline edit A'});
    await b.mutate(
        kind: RecordKind.task,
        id: 'proposal',
        workspaceId: 'personal',
        patch: {'priority': 4});
    await syncA.sync();
    await syncB.sync();
    await syncA.sync();
    final one = (await a.get(RecordKind.task, 'proposal'))!;
    final two = (await b.get(RecordKind.task, 'proposal'))!;
    expect(one.fields['title'], 'Offline edit A');
    expect(one.fields['priority'], 4);
    expect(canonicalJson(one.toJson()), canonicalJson(two.toJson()));
    expect(
        (await a.syncSnapshot()).pending + (await b.syncSnapshot()).pending, 0);
  });

  test(
      'generated records never overwrite an existing completion from another device',
      () async {
    final a = await memory(), b = await memory();
    addTearDown(a.close);
    addTearDown(b.close);
    final remote = _Remote();
    final first = SyncCoordinator(database: a, remote: remote),
        second = SyncCoordinator(database: b, remote: remote);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await a.mutate(
        kind: RecordKind.taskOccurrence,
        id: 'occurrence',
        workspaceId: 'personal',
        patch: {'status': 'completed'},
        ifAbsent: true);
    await first.sync();
    final stamp = VersionStamp(100, 'another_device');
    await b.acceptPage([
      WorkspaceRecord(
          ownerId: 'alice',
          kind: RecordKind.workspace,
          id: 'seed',
          fields: {'workspaceId': 'personal', '_deleted': false},
          clocks: {'workspaceId': stamp, '_deleted': stamp},
          modifiedAtMillis: 1)
    ], null);
    await b.mutate(
        kind: RecordKind.taskOccurrence,
        id: 'occurrence',
        workspaceId: 'personal',
        patch: {'status': 'notStarted'},
        ifAbsent: true);
    await b.mutate(
        kind: RecordKind.taskOccurrence,
        id: 'occurrence',
        workspaceId: 'personal',
        patch: {'notes': 'Keep this later edit'});
    await second.sync();
    final restored = (await b.get(RecordKind.taskOccurrence, 'occurrence'))!;
    expect(restored.fields['status'], 'completed');
    expect(restored.fields['notes'], 'Keep this later edit');
    expect(remote.records[restored.key]!.fields['status'], 'completed');
    expect(remote.records[restored.key]!.revision, 2);
  });

  test(
      'write timeout retains the exact operation and retries a late remote commit safely',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await task(db, 'timeout');
    final operation = (await db.pending()).single;
    final gate = Completer<void>();
    final remote = _Remote()..gate = gate;
    final coordinator = SyncCoordinator(
        database: db,
        remote: remote,
        requestTimeout: const Duration(milliseconds: 30));
    addTearDown(coordinator.dispose);
    await coordinator.sync();
    expect(coordinator.errorCode, 'unavailable');
    expect(coordinator.busy, isFalse);
    expect((await db.pending(includeDelayed: true)).single.id, operation.id);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    await coordinator.sync(force: true);
    expect((await db.syncSnapshot()).pending, 0);
    expect(remote.receipts, hasLength(1));
    expect(remote.records.values.single.revision, 1);
  });

  test(
      'resume during an old request schedules another sync after discarding its response',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await task(db, 'resume');
    final gate = Completer<void>();
    final remote = _Remote()..gate = gate;
    final coordinator = SyncCoordinator(database: db, remote: remote);
    addTearDown(coordinator.dispose);
    coordinator.start();
    await remote.started.future;
    coordinator.setActive(false);
    coordinator.setActive(true);
    final drained = db
        .watchSync()
        .firstWhere((snapshot) => snapshot.pending == 0)
        .timeout(const Duration(seconds: 3));
    gate.complete();
    await drained;
    await coordinator.drain();
    expect(remote.receipts, hasLength(1));
    expect((await db.syncSnapshot()).lastSuccessMillis, isNotNull);
  });

  test(
      'account deletion detected by sync freezes local writes without dropping pending data',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await task(db, 't');
    final coordinator = SyncCoordinator(
        database: db,
        remote: _Remote()
          ..failure = const SyncFailure('account-deleting', permanent: true));
    addTearDown(coordinator.dispose);
    await coordinator.sync();
    expect(await db.frozen, isTrue);
    expect((await db.syncSnapshot()).pending, 1);
    await expectLater(task(db, 'new'), throwsStateError);
  });

  test('a rejected calendar event does not block unrelated task sync',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await CalendarEventRepository(db).create(CalendarEvent(
        id: 'meeting',
        workspaceId: 'personal',
        title: 'Meeting',
        start: DateTime.utc(2026, 11, 5, 9),
        end: DateTime.utc(2026, 11, 5, 10),
        timeZone: 'Asia/Dhaka'));
    await TaskRepository(db).createTask(ProductivityTask(
        id: 'proposal', workspaceId: 'personal', title: 'Proposal'));
    final remote = _Remote()..rejectedEventKeys.add('calendarEvent--meeting');
    final coordinator = SyncCoordinator(database: db, remote: remote);
    addTearDown(coordinator.dispose);
    await coordinator.sync();
    expect(remote.records.containsKey('task--proposal'), isTrue);
    expect(remote.records.containsKey('calendarEvent--meeting'), isFalse);
    expect((await db.attention()).single.errorCode, 'invalid-calendar-event');
  });
}

class _Remote implements ProductivityRemote {
  final records = <String, WorkspaceRecord>{};
  final receipts = <String, String>{};
  final started = Completer<void>();
  bool loseNextResponse = false;
  Completer<void>? gate;
  SyncFailure? failure;
  final rejectedRecordKeys = <String>{};
  final rejectedEventKeys = <String>{};
  @override
  Future<RemoteAcknowledgement> apply(SyncOperation operation) async {
    if (!started.isCompleted) started.complete();
    await gate?.future;
    if (failure != null) throw failure!;
    if (rejectedEventKeys.contains(operation.recordKey)) {
      throw const SyncFailure('invalid-calendar-event', permanent: true);
    }
    if (rejectedRecordKeys.contains(operation.recordKey)) {
      throw const SyncFailure('circular-reference', permanent: true);
    }
    if (!receipts.containsKey(operation.id)) {
      final previous = records[operation.recordKey];
      final next = applyRecordOperation(previous, operation).record;
      records[next.key] = next;
      receipts[operation.id] = operation.fingerprint;
    } else {
      expect(receipts[operation.id], operation.fingerprint);
    }
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const SyncFailure('unavailable');
    }
    return RemoteAcknowledgement(records[operation.recordKey]!);
  }

  @override
  Future<RemotePage> pull(SyncCursor? cursor, {int limit = 100}) async {
    if (failure != null) throw failure!;
    return RemotePage(records.values.toList(), hasMore: false);
  }
}
