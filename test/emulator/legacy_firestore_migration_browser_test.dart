import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/firestore_productivity_remote.dart';
import 'package:ummah_assist/src/productivity/data/firestore_portable_document.dart';
import 'package:ummah_assist/src/productivity/data/legacy_firestore_source.dart';
import 'package:ummah_assist/src/productivity/data/legacy_task_migration.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';

import 'firebase_web_registration_stub.dart'
    if (dart.library.js_interop) 'firebase_web_registration.dart';

// Opt-in real SDK/adapter checks against disposable local emulators only.
// Normal VM tests skip these rather than substituting a fake Firebase client.
const _enabled = kIsWeb &&
    bool.fromEnvironment('RUN_FIREBASE_EMULATOR_TESTS', defaultValue: false);
const _project = 'demo-ummah';
const _skip = _enabled ? false : 'Run tool/test_legacy_migration_browser.sh';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_enabled) registerFirebaseEmulatorTestPlugins();

  test('fenced Firestore import replay preserves later edits and tombstones',
      () async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final email = 'migration-$suffix@example.test';
    final a = await _client('migration-a-$suffix', email: email);
    final b =
        await _client('migration-b-$suffix', email: email, existing: true);
    addTearDown(a.close);
    addTearDown(b.close);
    final uid = a.auth.currentUser!.uid;
    final legacy = a.firestore.collection('userTasks').doc(uid);
    await legacy.set({
      'dateUpdated': '2026-11-06',
      'todayTasks': {
        'mustDo': [_item('a', 'Original title')],
        'goodToDo': [_item('b', 'Task to remove')],
      },
      'metadata': {
        'stamp': Timestamp(1234567, 123456000),
        'place': const GeoPoint(23.8, 90.4),
        'reference': a.firestore.doc('users/$uid'),
      },
    });
    // Seed server precision through REST: the Dart web SDK itself truncates
    // Timestamp writes/reads to milliseconds. The archive must retain what is
    // actually stored, including data written by a native client.
    final timestampUri = legacySnapshotUri(
            projectId: _project,
            databaseId: '(default)',
            uid: uid,
            host: '127.0.0.1:8787',
            sslEnabled: false)
        .replace(queryParameters: {'updateMask.fieldPaths': 'metadata.stamp'});
    final stampPrefix =
        DateTime.fromMillisecondsSinceEpoch(1234567 * 1000, isUtc: true)
            .toIso8601String()
            .split('.')
            .first;
    final precise = await http.patch(timestampUri,
        headers: {
          'Authorization': 'Bearer ${await a.auth.currentUser!.getIdToken()}',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          'fields': {
            'metadata': {
              'mapValue': {
                'fields': {
                  'stamp': {'timestampValue': '$stampPrefix.123456Z'}
                }
              }
            }
          }
        }));
    expect(precise.statusCode, 200);
    final sourceA =
        LegacyFirestoreSource(uid: uid, firestore: a.firestore, auth: a.auth);
    final first = await sourceA.freezeAndPrepare();
    expect(
        (await legacy.get(const GetOptions(source: Source.server)))
            .data()!['productivityMigrationVersion'],
        1);
    final archiveParts = first.records
        .where((record) => record.kind == RecordKind.note)
        .toList()
      ..sort((x, y) =>
          (x.patch['partIndex'] as int).compareTo(y.patch['partIndex'] as int));
    final archive = jsonDecode(
        archiveParts.map((part) => part.patch['body'] as String).join()) as Map;
    expect(archive['metadata']['stamp'], {
      '__firestoreType': 'timestamp',
      'seconds': 1234567,
      'nanoseconds': 123456000,
    });
    expect(archive['metadata']['place']['__firestoreType'], 'geoPoint');
    expect(archive['metadata']['reference']['path'], 'users/$uid');

    final localA = await ProductivityDatabase.open(
        uid: uid, factory: databaseFactoryMemory, path: 'migration-a-$suffix');
    final localB = await ProductivityDatabase.open(
        uid: uid, factory: databaseFactoryMemory, path: 'migration-b-$suffix');
    addTearDown(localA.close);
    addTearDown(localB.close);
    final remoteA = FirestoreProductivityRemote(
        uid: uid, firestore: a.firestore, auth: a.auth);
    final remoteB = FirestoreProductivityRemote(
        uid: uid, firestore: b.firestore, auth: b.auth);
    await first.apply(localA);
    await _push(localA, remoteA);
    final tasks = TaskRepository(localA);
    final edited = LegacyTaskMigration.taskId('a');
    final removed = LegacyTaskMigration.taskId('b');
    await tasks.editTask(edited, {'title': 'Edited after migration'});
    await tasks.trash(removed);
    await _push(localA, remoteA);

    final repeated = await LegacyFirestoreSource(
            uid: uid, firestore: b.firestore, auth: b.auth)
        .freezeAndPrepare();
    expect(repeated.sourceChecksum, first.sourceChecksum);
    await repeated.apply(localB);
    await _push(localB, remoteB);
    expect((await localB.get(RecordKind.task, edited))!.fields['title'],
        'Edited after migration');
    expect((await localB.get(RecordKind.task, removed))!.deleted, isTrue);
    expect(await localB.fieldConflicts(), isEmpty);
    await repeated.apply(localB);
    expect(await localB.queued(), isEmpty);

    // A stale legacy client may neither overwrite nor delete/recreate source.
    final stale = b.firestore.collection('userTasks').doc(uid);
    await expectLater(
        stale.set({'dateUpdated': '2026-11-07'}),
        throwsA(isA<FirebaseException>()
            .having((error) => error.code, 'code', 'permission-denied')));
    await expectLater(
        stale.delete(),
        throwsA(isA<FirebaseException>()
            .having((error) => error.code, 'code', 'permission-denied')));
  }, skip: _skip, timeout: const Timeout(Duration(minutes: 2)));

  test('invalid source, account change and deletion never freeze a new source',
      () async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final client = await _client('migration-boundaries-$suffix',
        email: 'migration-boundaries-$suffix@example.test');
    addTearDown(client.close);
    final uid = client.auth.currentUser!.uid;
    final ref = client.firestore.collection('userTasks').doc(uid);
    final source = LegacyFirestoreSource(
        uid: uid, firestore: client.firestore, auth: client.auth);
    await ref.set({
      'todayTasks': {
        'mustDo': [
          {'id': 'broken', 'text': 'Invalid completion', 'completed': 'yes'}
        ]
      }
    });
    await expectLater(
        source.freezeAndPrepare(), throwsA(isA<LegacyMigrationFailure>()));
    expect(
        (await ref.get(const GetOptions(source: Source.server)))
            .data()!
            .containsKey('productivityMigrationVersion'),
        isFalse);
    await ref.set({
      'todayTasks': {
        'mustDo': [
          {
            'id': 'invalid-date',
            'text': 'Non-civil date',
            'completed': false,
            'dateCreated': Timestamp(1234567, 0)
          }
        ]
      }
    });
    await expectLater(
        source.freezeAndPrepare(),
        throwsA(isA<LegacyMigrationFailure>()
            .having((error) => error.code, 'code', 'invalid-source-value')));
    expect(
        (await ref.get(const GetOptions(source: Source.server)))
            .data()!
            .containsKey('productivityMigrationVersion'),
        isFalse);
    await ref.set({'dateUpdated': '2026-11-06', 'todayTasks': {}});
    await client.firestore.collection('accountDeletions').doc(uid).set({});
    await expectLater(
        source.freezeAndPrepare(),
        throwsA(isA<LegacyMigrationFailure>()
            .having((error) => error.code, 'code', 'account-deleting')));
    expect(
        (await ref.get(const GetOptions(source: Source.server)))
            .data()!
            .containsKey('productivityMigrationVersion'),
        isFalse);
    await client.auth.signOut();
    await expectLater(
        source.freezeAndPrepare(),
        throwsA(isA<LegacyMigrationFailure>()
            .having((error) => error.code, 'code', 'account-changed')));
  }, skip: _skip, timeout: const Timeout(Duration(minutes: 2)));
}

Map<String, Object?> _item(String id, String title) => {
      'id': id,
      'text': title,
      'completed': false,
      'dateCreated': '2026-11-06',
      'dueDate': '2026-11-06',
    };

Future<void> _push(
    ProductivityDatabase local, FirestoreProductivityRemote remote) async {
  for (var round = 0; round < 100; round++) {
    final pending = await local.pending();
    if (pending.isEmpty) {
      expect(await local.queued(), isEmpty);
      return;
    }
    for (final operation in pending) {
      final ack = await remote.apply(operation);
      await local.acknowledge(operation, ack.record,
          rejectedFields: ack.rejectedFields);
    }
  }
  fail('Migration outbox did not drain.');
}

Future<_Client> _client(String name,
    {required String email, bool existing = false}) async {
  if (!_enabled || !_project.startsWith('demo-')) {
    throw StateError('This test requires opt-in local emulators.');
  }
  final app = await Firebase.initializeApp(
          name: name,
          options: const FirebaseOptions(
              apiKey: 'demo-key',
              appId: '1:1234567890:web:abcd1234',
              messagingSenderId: '1234567890',
              projectId: _project))
      .timeout(const Duration(seconds: 25),
          onTimeout: () =>
              throw StateError('Firebase JS SDK initialization timed out'));
  final auth = FirebaseAuth.instanceFor(app: app);
  await auth
      .useAuthEmulator('127.0.0.1', 9099)
      .timeout(const Duration(seconds: 15));
  final firestore = FirebaseFirestore.instanceFor(app: app);
  // Explicit settings keep the SDK and authenticated REST snapshot on the
  // same disposable backend. This web SDK version's useFirestoreEmulator()
  // does not expose its host through FirebaseFirestore.settings.
  firestore.settings = const Settings(
      persistenceEnabled: false, host: '127.0.0.1:8787', sslEnabled: false);
  try {
    if (existing) {
      await auth
          .signInWithEmailAndPassword(
              email: email, password: 'Synthetic-migration-42')
          .timeout(const Duration(seconds: 15));
    } else {
      await auth
          .createUserWithEmailAndPassword(
              email: email, password: 'Synthetic-migration-42')
          .timeout(const Duration(seconds: 15));
    }
    return _Client(app, auth, firestore);
  } catch (_) {
    await app.delete();
    rethrow;
  }
}

class _Client {
  const _Client(this.app, this.auth, this.firestore);
  final FirebaseApp app;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  Future<void> close() async {
    await firestore.terminate();
    await app.delete();
  }
}
