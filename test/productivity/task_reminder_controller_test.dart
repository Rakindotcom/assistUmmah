import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/notifications/task_reminder_controller.dart';
import 'package:ummah_assist/src/productivity/notifications/task_reminder_store.dart';

import '../support/task_notification_platform.dart';

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'Notification state did not settle.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TaskNotificationPlatform platform;
  var sequence = 0;
  final options = ExperienceOptions(language: 'en', timeZone: 'UTC');
  Future<(ProductivityDatabase, TaskReminderController)> open(String uid,
      {TaskReminderStore? store}) async {
    final db = await ProductivityDatabase.open(
        uid: uid,
        factory: databaseFactoryMemory,
        path: 'notifications-${sequence++}');
    final controller =
        TaskReminderController(database: db, options: options, store: store);
    addTearDown(() async {
      await controller.close();
      controller.dispose();
      await db.close();
    });
    await controller.start();
    return (db, controller);
  }

  Future<void> create(ProductivityDatabase db,
          {String id = 'task', String workspace = 'personal'}) =>
      TaskRepository(db).createTask(ProductivityTask(
          id: id,
          workspaceId: workspace,
          title: 'First title',
          reminders: [DateTime.utc(2090, 1, 1), DateTime.utc(2090, 1, 2)]));
  setUp(() {
    platform = TaskNotificationPlatform()..install();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
      'opt-in is explicit and edits/completion replace or cancel native alarms',
      () async {
    final (db, controller) = await open('owner');
    await create(db);
    await until(() => controller.delivery != null);
    expect(controller.enabled, isFalse);
    expect(platform.pending, isEmpty);
    expect(
        platform.calls.where((c) => c.method.startsWith('request')), isEmpty);
    await controller.setEnabled(true);
    await until(() => platform.pending.length == 2);
    expect(await TaskReminderStore('owner').load(), isTrue);
    await TaskRepository(db).editTask('task', {
      'title': 'Edited title',
      'reminders': [DateTime.utc(2090, 1, 2).toIso8601String()]
    });
    await until(() =>
        platform.pending.length == 1 &&
        platform.pending.values.single['title'] == 'Edited title');
    await TaskRepository(db).setStatus('task', TaskStatus.completed);
    await until(() => platform.pending.isEmpty);
    expect(controller.error, isNull);
  });

  test('denial is visible and does not save device consent', () async {
    platform.permission = false;
    final (db, controller) = await open('owner');
    await create(db);
    await until(() => controller.delivery != null);
    await controller.setEnabled(true);
    expect(controller.permissionDenied, isTrue);
    expect(controller.enabled, isFalse);
    expect(await TaskReminderStore('owner').load(), isFalse);
    expect(platform.pending, isEmpty);
    await controller.refresh();
    expect(controller.permissionDenied, isTrue);
    platform.permission = true;
    await controller.setEnabled(true);
    await until(() => platform.pending.length == 2);
    expect(controller.permissionDenied, isFalse);
    await controller.setEnabled(false);
    expect(platform.pending, isEmpty);
  });

  test('disabled workspaces and account deletion freeze cancel existing alarms',
      () async {
    final (db, controller) = await open('owner');
    await create(db, workspace: 'work');
    await until(() => controller.delivery != null);
    controller.updateOptions(ExperienceOptions(
        language: 'en',
        timeZone: 'UTC',
        modules: [WorkspaceModule.personal, WorkspaceModule.work]));
    await controller.setEnabled(true);
    await until(() => platform.pending.length == 2);
    controller.updateOptions(options);
    await until(() => platform.pending.isEmpty);
    controller.updateOptions(ExperienceOptions(
        language: 'en',
        timeZone: 'UTC',
        modules: [WorkspaceModule.personal, WorkspaceModule.work]));
    await until(() => platform.pending.length == 2);
    await db.freeze();
    await until(() => platform.pending.isEmpty);
  });

  test(
      'late consent reads from a disposed account cannot replace another account',
      () async {
    final delayed = _DelayedStore('owner-a');
    final dbA = await ProductivityDatabase.open(
        uid: 'owner-a',
        factory: databaseFactoryMemory,
        path: 'notifications-delayed');
    final a =
        TaskReminderController(database: dbA, options: options, store: delayed);
    final opening = a.start();
    await a.close();
    a.dispose();
    final (dbB, b) = await open('owner-b');
    await create(dbB);
    await until(() => b.delivery != null);
    await b.setEnabled(true);
    await until(() => platform.pending.length == 2);
    delayed.value.complete(true);
    await opening;
    expect(platform.pending.length, 2);
    expect(a.ready, isFalse);
    await dbA.close();
  });

  test('device consent is per account and is removed independently', () async {
    final a = TaskReminderStore('owner-a'), b = TaskReminderStore('owner-b');
    expect(await a.load(), isFalse);
    await a.save(true);
    expect(await b.load(), isFalse);
    await b.save(true);
    await a.remove();
    expect(await a.load(), isFalse);
    expect(await b.load(), isTrue);
  });

  test(
      'failed consent storage cancels stale native task alarms and exposes retry',
      () async {
    platform.pending[3000] = {
      'id': 3000,
      'title': 'Stale private task',
      'body': 'Saved'
    };
    final (_, controller) = await open('owner', store: _FailingStore('owner'));
    await until(() => platform.pending.isEmpty);
    expect(controller.ready, isFalse);
    expect(controller.error, 'storage');
    expect(controller.enabled, isFalse);
  });
}

class _DelayedStore extends TaskReminderStore {
  _DelayedStore(super.uid);
  final value = Completer<bool>();
  @override
  Future<bool> load() => value.future;
}

class _FailingStore extends TaskReminderStore {
  _FailingStore(super.uid);
  @override
  Future<bool> load() async => throw StateError('Storage unavailable');
}
