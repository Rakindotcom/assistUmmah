import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/firestore_productivity_remote.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/productivity_remote.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two Android clients review graph and field conflicts',
      (tester) async {
    const projectId = 'demo-ummah';
    assert(projectId.startsWith('demo-'));
    const options = FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:1234567890:android:abcd1234',
        messagingSenderId: '1234567890',
        projectId: projectId);
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final appA =
        await Firebase.initializeApp(name: 'graph-a-$suffix', options: options);
    final appB =
        await Firebase.initializeApp(name: 'graph-b-$suffix', options: options);
    final authA = FirebaseAuth.instanceFor(app: appA);
    final authB = FirebaseAuth.instanceFor(app: appB);
    await authA.useAuthEmulator('10.0.2.2', 9099);
    await authB.useAuthEmulator('10.0.2.2', 9099);
    final firestoreA = FirebaseFirestore.instanceFor(app: appA);
    final firestoreB = FirebaseFirestore.instanceFor(app: appB);
    firestoreA.useFirestoreEmulator('10.0.2.2', 8787);
    firestoreB.useFirestoreEmulator('10.0.2.2', 8787);
    final email = 'graph-$suffix@example.test';
    const password = 'Synthetic-only-42';
    final owner = await authA.createUserWithEmailAndPassword(
        email: email, password: password);
    await authB.signInWithEmailAndPassword(email: email, password: password);
    final uid = owner.user!.uid;
    final localA = await ProductivityDatabase.open(
        uid: uid, factory: databaseFactoryMemory, path: 'graph-a-$suffix');
    final localB = await ProductivityDatabase.open(
        uid: uid, factory: databaseFactoryMemory, path: 'graph-b-$suffix');
    addTearDown(() async {
      await localA.close();
      await localB.close();
      await appA.delete();
      await appB.delete();
    });
    final tasksA = TaskRepository(localA);
    final tasksB = TaskRepository(localB);
    final remoteA = FirestoreProductivityRemote(
        uid: uid, firestore: firestoreA, auth: authA);
    final remoteB = FirestoreProductivityRemote(
        uid: uid, firestore: firestoreB, auth: authB);

    for (final id in ['a', 'b']) {
      await tasksA.createTask(
          ProductivityTask(id: id, workspaceId: 'personal', title: 'Task $id'));
    }
    for (final operation in await localA.pending()) {
      final ack = await remoteA.apply(operation);
      await localA.acknowledge(operation, ack.record,
          rejectedFields: ack.rejectedFields);
    }
    final initial = await remoteB.pull(null);
    await localB.acceptPage(initial.records, initial.cursor);
    expect((await localB.list(kind: RecordKind.task)).length, 2);

    await tasksA.editTask('a', {
      'dependencies': ['b']
    });
    await tasksB.editTask('b', {
      'dependencies': ['a']
    });
    final editA = (await localA.pending()).single;
    final ackA = await remoteA.apply(editA);
    await localA.acknowledge(editA, ackA.record);
    final editB = (await localB.pending()).single;
    await expectLater(
        remoteB.apply(editB),
        throwsA(isA<SyncFailure>()
            .having((failure) => failure.code, 'code', 'circular-reference')));
    await localB.recordFailure(editB, 'circular-reference', permanent: true);
    expect((await localB.attention()).single.id, editB.id);

    // Foreground sync still pulls the accepted edit from the other device.
    // The local draft now shows the conflict until its owner corrects it.
    final conflictingPage = await remoteB.pull(null);
    await localB.acceptPage(conflictingPage.records, conflictingPage.cursor);
    expect((await localB.get(RecordKind.task, 'a'))!.fields['dependencies'],
        ['b']);

    await tasksB.editTask('b', {'dependencies': <String>[]});
    await tasksB.resubmitGraphConflict('b');
    final corrected = (await localB.pending()).single;
    final ackB = await remoteB.apply(corrected);
    await localB.acknowledge(corrected, ackB.record);
    expect(await localB.attention(), isEmpty);
    final remoteTasks = await remoteA.pull(null);
    final byId = {for (final record in remoteTasks.records) record.id: record};
    expect(byId['a']!.fields['dependencies'], ['b']);
    expect(byId['b']!.fields['dependencies'], isEmpty);
    final guard = await firestoreA
        .collection('users')
        .doc(uid)
        .collection('productivityControl')
        .doc('taskGraph')
        .get(const GetOptions(source: Source.server));
    expect(guard.data()!['revision'], 4);

    // A later same-field edit is never discarded just because the server's
    // clock wins. The losing value remains reviewable on this device.
    await tasksB.editTask('b', {'title': 'My task title'});
    for (var index = 0; index < 5; index++) {
      await tasksA.editTask('b', {'title': 'Cloud task title $index'});
    }
    while ((await localA.pending()).isNotEmpty) {
      final operation = (await localA.pending()).single;
      final acknowledgement = await remoteA.apply(operation);
      await localA.acknowledge(operation, acknowledgement.record,
          rejectedFields: acknowledgement.rejectedFields);
    }
    final losingEdit = (await localB.pending()).single;
    final losingAck = await remoteB.apply(losingEdit);
    expect(losingAck.rejectedFields, contains('title'));
    await localB.acknowledge(losingEdit, losingAck.record,
        rejectedFields: losingAck.rejectedFields);
    final conflict = (await localB.fieldConflicts()).single;
    expect(conflict.localValue, 'My task title');
    expect(conflict.cloudValue, 'Cloud task title 4');
    expect((await localB.get(RecordKind.task, 'b'))!.fields['title'],
        'Cloud task title 4');
    await localB.retryMyValue(conflict,
        validate: tasksB.validateTaskConflictCandidate);
    final reviewed = (await localB.pending()).single;
    final reviewedAck = await remoteB.apply(reviewed);
    await localB.acknowledge(reviewed, reviewedAck.record,
        rejectedFields: reviewedAck.rejectedFields);
    expect(await localB.fieldConflicts(), isEmpty);
    final finalPage = await remoteA.pull(null);
    expect(
        finalPage.records.singleWhere((record) => record.id == 'b').fields['title'],
        'My task title');
  });
}
