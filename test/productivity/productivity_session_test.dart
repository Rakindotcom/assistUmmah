import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/productivity_session.dart';

void main() {
  var sequence = 0;
  test(
      'account session cannot be opened twice; close is repeatable and retains offline work',
      () async {
    final path = 'session-${sequence++}';
    Future<ProductivityDatabase> open() => ProductivityDatabase.open(
        uid: 'alice', factory: databaseFactoryMemory, path: path);
    final session =
        await ProductivitySession.open(uid: 'alice', openDatabase: open);
    addTearDown(session.close);
    await session.database.mutate(
        kind: RecordKind.task,
        id: 'task',
        workspaceId: 'personal',
        patch: {'title': 'Kept'});
    await expectLater(
        ProductivitySession.open(uid: 'alice', openDatabase: open),
        throwsStateError);
    await session.close();
    await session.close();
    final reopened =
        await ProductivitySession.open(uid: 'alice', openDatabase: open);
    addTearDown(reopened.close);
    expect(
        (await reopened.database.get(RecordKind.task, 'task'))!.fields['title'],
        'Kept');
    expect(await reopened.database.pending(), hasLength(1));
  });
  test(
      'deletion freezes writes before erasing records, outbox and local history',
      () async {
    final path = 'session-delete-${sequence++}';
    Future<ProductivityDatabase> open() => ProductivityDatabase.open(
        uid: 'alice', factory: databaseFactoryMemory, path: path);
    final session =
        await ProductivitySession.open(uid: 'alice', openDatabase: open);
    addTearDown(session.close);
    await session.database.mutate(
        kind: RecordKind.note,
        id: 'private',
        workspaceId: 'personal',
        patch: {'body': 'Private'});
    final device = session.database.deviceId;
    await ProductivitySession.freezeAccount('alice');
    expect(await session.database.frozen, isTrue);
    await expectLater(
        session.database.mutate(
            kind: RecordKind.note,
            id: 'later',
            workspaceId: 'personal',
            patch: {'body': 'Blocked'}),
        throwsStateError);
    await ProductivitySession.closeAccount('alice');
    await ProductivityDatabase.eraseAccountData('alice',
        factory: databaseFactoryMemory, path: path);
    final empty = await open();
    addTearDown(empty.close);
    expect(empty.deviceId, isNot(device));
    expect(await empty.list(), isEmpty);
    expect(await empty.pending(), isEmpty);
    expect(await empty.history(RecordKind.note, 'private'), isEmpty);
    expect(await empty.frozen, isFalse);
  });
  test('failed opening does not poison a later attempt', () async {
    await expectLater(
        ProductivitySession.open(
            uid: 'alice',
            openDatabase: () async =>
                throw StateError('Synthetic storage failure')),
        throwsStateError);
    final session = await ProductivitySession.open(
        uid: 'alice',
        openDatabase: () => ProductivityDatabase.open(
            uid: 'alice',
            factory: databaseFactoryMemory,
            path: 'session-retry-${sequence++}'));
    addTearDown(session.close);
    expect(session.database.uid, 'alice');
  });
}
