import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/account/deletion_plan.dart';

void main() {
  final plan = AccountDeletionPlan.fromJson(
      File('assets/legal/account-data-paths.json').readAsStringSync());
  test('all data paths are erased before identity; UID determines every path',
      () async {
    final calls = <String>[];
    await plan.execute(
        uid: 'owner',
        recordRequest: () async => calls.add('marker'),
        deleteCollection: (path) async => calls.add(path),
        deleteActivities: (name, field, uid) async =>
            calls.add('$name:$field=$uid'),
        deleteDocuments: (paths) async => calls.addAll(paths),
        deleteIdentity: () async => calls.add('identity'));
    expect(calls.first, 'marker');
    expect(calls.last, 'identity');
    expect(calls.where((path) => path.startsWith('user')), hasLength(16));
    expect(
        calls,
        containsAll([
          'userPrayers/owner/dailyPrayers',
          'userGrowth/owner/dailyGrowth',
          'userQuran/owner/dailyReading',
          'userDhikr/owner/dailyDhikr',
          'userActivities:userId=owner',
          'users/owner',
          'users/owner/productivity',
          'users/owner/productivityChanges'
        ]));
  });
  test('partial failure preserves the identity and permits safe resumption',
      () async {
    var identityDeleted = false;
    var fail = true;
    final removed = <String>{};
    Future<void> run() => plan.execute(
        uid: 'owner',
        recordRequest: () async {},
        deleteCollection: (path) async {
          if (fail && path.contains('userGrowth')) throw StateError('offline');
          removed.add(path);
        },
        deleteActivities: (_, field, uid) async {},
        deleteDocuments: (paths) async => removed.addAll(paths),
        deleteIdentity: () async => identityDeleted = true);
    await expectLater(run(), throwsStateError);
    expect(identityDeleted, isFalse);
    fail = false;
    await run();
    expect(identityDeleted, isTrue);
    expect(removed, hasLength(15));
  });
  test('a failed request cannot delete data or identity', () async {
    var touched = false;
    await expectLater(
        plan.execute(
            uid: 'owner',
            recordRequest: () async => throw StateError('permission denied'),
            deleteCollection: (_) async => touched = true,
            deleteActivities: (_, field, uid) async => touched = true,
            deleteDocuments: (_) async => touched = true,
            deleteIdentity: () async => touched = true),
        throwsStateError);
    expect(touched, isFalse);
  });
}
