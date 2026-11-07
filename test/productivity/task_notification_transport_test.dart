import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/prayer_alerts.dart';
import 'package:ummah_assist/src/prayer_times_service.dart';
import 'package:ummah_assist/src/productivity/domain/task_reminder_plan.dart';
import 'package:ummah_assist/src/reminder_service.dart';

import '../support/task_notification_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TaskNotificationPlatform platform;
  TaskReminderPlan plan(String uid, {int count = 1}) => TaskReminderPlan(
          owner: taskReminderOwner(uid),
          language: 'bn',
          totalCount: count,
          reminders: [
            for (var i = 0; i < count && i < taskAlertSlotCount; i++)
              PlannedTaskReminder(
                  taskId: 'task_$i',
                  workspaceId: 'personal',
                  title: 'Task $i',
                  time: DateTime.utc(2090, 1, 1, 0, i))
          ]);
  setUp(() {
    platform = TaskNotificationPlatform()..install();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
      'schedules absolute UTC reminders without permission prompts, with inexact fallback',
      () async {
    platform.exact = false;
    final service = ReminderService.instance;
    final scope = service.claimTaskReminderScope('owner');
    final result = await service.syncTaskAlerts(scope, plan('owner', count: 2));
    expect(result!.scheduledCount, 2);
    expect(result.exact, isFalse);
    final schedules =
        platform.calls.where((c) => c.method == 'zonedSchedule').toList();
    final args = schedules.first.arguments as Map;
    expect(args['timeZoneName'], 'UTC');
    expect((args['platformSpecifics'] as Map)['scheduleMode'],
        'inexactAllowWhileIdle');
    expect(jsonDecode(args['payload'] as String),
        containsPair('owner', taskReminderOwner('owner')));
    expect(
        platform.calls.where((c) => c.method.startsWith('request')), isEmpty);
    await service.releaseTaskReminderScope(scope);
    expect(platform.pending, isEmpty);
  });

  test(
      'iOS reserves slots before prayer/daily updates and refills after Faith is disabled',
      () async {
    platform.install(platform: TargetPlatform.iOS);
    final service = ReminderService.instance;
    final scope = service.claimTaskReminderScope('owner');
    await service.syncTaskAlerts(scope, plan('owner', count: 100));
    expect(platform.pending.length, 64);
    await service.sync({'tasks': true, 'growth': true, 'prayer': true});
    await service.syncPrayerAlerts(
        config: PrayerTimeConfig(
            latitude: 23.81,
            longitude: 90.41,
            placeName: 'Dhaka',
            timeZoneId: 'Asia/Dhaka'),
        settings: PrayerAlertSettings(enabled: true));
    final result = service.taskDelivery.value!.result;
    expect(result.scheduledCount, inInclusiveRange(9, 14));
    expect(result.deferredCount, 100 - result.scheduledCount);
    expect(platform.pending.length, 64);
    expect(platform.pending.keys,
        containsAll([1001, 1002, 1003, prayerAlertRenewalId]));
    expect(
        platform.pending.keys
            .where((id) => id >= prayerAlertIdBase && id < prayerAlertRenewalId)
            .length,
        inInclusiveRange(45, 50));
    expect(platform.pending, contains(taskAlertRenewalId));
    await service.syncPrayerAlerts(
        config: null, settings: PrayerAlertSettings());
    expect(service.taskDelivery.value!.result.scheduledCount, 60);
    expect(platform.pending.keys, containsAll([1001, 1002, 1003]));
    expect(platform.pending.length, 64);
    await service.releaseTaskReminderScope(scope);
    expect(platform.pending.keys.toSet(), {1001, 1002, 1003});
  });

  test('a late old-account schedule and release cannot replace the new account',
      () async {
    final service = ReminderService.instance;
    final scopeA = service.claimTaskReminderScope('owner-a');
    final started = Completer<void>(), release = Completer<void>();
    platform.intercept = (call) async {
      if (call.method == 'zonedSchedule' && !started.isCompleted) {
        started.complete();
        await release.future;
      }
    };
    final a = service.syncTaskAlerts(scopeA, plan('owner-a', count: 3));
    await started.future;
    final scopeB = service.claimTaskReminderScope('owner-b');
    final b = service.syncTaskAlerts(scopeB, plan('owner-b'));
    await service.releaseTaskReminderScope(scopeA);
    release.complete();
    expect(await a, isNull);
    expect((await b)!.scheduledCount, 1);
    expect(platform.pending.length, 1);
    expect(
        jsonDecode(
            platform.pending.values.single['payload'] as String)['owner'],
        taskReminderOwner('owner-b'));
    expect(() => service.syncTaskAlerts(scopeB, plan('owner-a')),
        throwsStateError);
    await service.releaseTaskReminderScope(scopeB);
  });

  test('permission revocation cancels tasks and never prompts during refresh',
      () async {
    final service = ReminderService.instance;
    final scope = service.claimTaskReminderScope('owner');
    await service.syncTaskAlerts(scope, plan('owner'));
    platform.permission = false;
    final result = await service.syncTaskAlerts(scope, plan('owner'));
    expect(result!.permissionGranted, isFalse);
    expect(platform.pending, isEmpty);
    expect(
        platform.calls.where((c) => c.method.startsWith('request')), isEmpty);
    await service.releaseTaskReminderScope(scope);
  });

  test(
      'an exact-alarm revocation during scheduling retries with an inexact alarm',
      () async {
    final service = ReminderService.instance;
    final scope = service.claimTaskReminderScope('owner');
    platform.intercept = (call) async {
      if (call.method == 'zonedSchedule' &&
          ((call.arguments as Map)['platformSpecifics']
                  as Map)['scheduleMode'] ==
              'exactAllowWhileIdle') {
        throw PlatformException(code: 'exact_alarms_not_permitted');
      }
    };
    final result = await service.syncTaskAlerts(scope, plan('owner', count: 2));
    expect(result!.scheduledCount, 2);
    expect(result.exact, isFalse);
    expect(platform.pending.length, 2);
    expect(
        platform.calls.where((c) => c.method.startsWith('request')), isEmpty);
    await service.releaseTaskReminderScope(scope);
  });

  test(
      'partial native failure rolls back alarms already scheduled in that batch',
      () async {
    final service = ReminderService.instance;
    final scope = service.claimTaskReminderScope('owner');
    var schedules = 0;
    platform.intercept = (call) async {
      if (call.method == 'zonedSchedule' && ++schedules == 2) {
        throw PlatformException(code: 'native-failed');
      }
    };
    await expectLater(service.syncTaskAlerts(scope, plan('owner', count: 3)),
        throwsA(isA<PlatformException>()));
    expect(platform.pending, isEmpty);
    platform.intercept = null;
    expect((await service.syncTaskAlerts(scope, plan('owner')))!.scheduledCount,
        1);
    await service.cancelAll();
    expect(platform.pending, isEmpty);
    expect(await service.syncTaskAlerts(scope, plan('owner')), isNull);
  });

  test('account cancellation works even when timezone initialization is broken',
      () async {
    platform.pending[taskAlertIdBase] = {
      'id': taskAlertIdBase,
      'title': 'Private task',
      'body': 'Saved',
      'payload': ''
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_timezone'),
            (call) async =>
                throw PlatformException(code: 'timezone-unavailable'));
    await ReminderService.instance.cancelAll();
    expect(platform.pending, isEmpty);
    expect(platform.calls.map((c) => c.method), ['cancelAll']);
  });

  test('opting out clears pending and displayed tasks without timezone setup',
      () async {
    platform.pending[taskAlertIdBase] = {
      'id': taskAlertIdBase,
      'title': 'Pending task',
      'body': 'Saved',
      'payload': ''
    };
    platform.displayed[taskAlertIdBase + 1] = {
      'id': taskAlertIdBase + 1,
      'title': 'Displayed task',
      'body': 'Saved',
      'payload': ''
    };
    platform.pending[1002] = {'id': 1002, 'title': 'Prayer', 'body': 'Saved'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_timezone'),
            (call) async =>
                throw PlatformException(code: 'timezone-unavailable'));
    final service = ReminderService.instance;
    final scope = service.claimTaskReminderScope('owner');
    await service.syncTaskAlerts(scope, null);
    expect(platform.pending.keys.toSet(), {1002});
    expect(platform.displayed, isEmpty);
    expect(platform.calls.where((c) => c.method == 'initialize'), isEmpty);
    await service.releaseTaskReminderScope(scope);
  });

  test(
      'refilling preserves delivered alerts; opting out clears only task alerts',
      () async {
    final service = ReminderService.instance;
    final scope = service.claimTaskReminderScope('owner');
    final first = plan('owner', count: 2);
    await service.syncTaskAlerts(scope, first);
    platform.displayed[taskAlertIdBase] =
        platform.pending.remove(taskAlertIdBase)!;
    platform.displayed[1002] = {
      'id': 1002,
      'title': 'Prayer log',
      'body': 'Saved'
    };
    await service.syncTaskAlerts(
        scope,
        TaskReminderPlan(
            owner: first.owner,
            language: first.language,
            reminders: [first.reminders.last],
            totalCount: 1));
    expect(platform.displayed, contains(taskAlertIdBase));
    await service.syncTaskAlerts(scope, null);
    expect(platform.pending, isEmpty);
    expect(platform.displayed.keys.toSet(), {1002});
    await service.releaseTaskReminderScope(scope);
  });
}
