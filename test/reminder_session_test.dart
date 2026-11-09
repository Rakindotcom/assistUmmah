import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/prayer_alerts.dart';
import 'package:ummah_assist/src/prayer_times_service.dart';
import 'package:ummah_assist/src/reminder_service.dart';
import 'package:ummah_assist/src/reminder_session.dart';

import 'support/native_ui_channels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Future<void> Function(MethodCall)? intercept;
  var deviceZone = 'Asia/Dhaka';

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    configureNativeUiChannels();
    deviceZone = 'Asia/Dhaka';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (call) async {
      if (call.method == 'getLocalTimezone') return deviceZone;
      throw UnsupportedError(call.method);
    });
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    calls.clear();
    intercept = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      calls.add(call);
      await intercept?.call(call);
      return switch (call.method) {
        'initialize' ||
        'areNotificationsEnabled' ||
        'canScheduleExactNotifications' =>
          true,
        'cancel' || 'cancelAll' || 'zonedSchedule' => null,
        _ => throw StateError('Unexpected method ${call.method}'),
      };
    });
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
      'refreshes daily and prayer alerts without opening settings or prayer screens',
      () async {
    final repository = _SettingsRepository();
    repository.response.complete({
      'remindersConfigured': true,
      'notifications': {'tasks': true}
    });
    await PrayerTimeStore(repository.uid).save(PrayerTimeConfig(
        latitude: 23.81,
        longitude: 90.41,
        placeName: 'ঢাকা',
        timeZoneId: 'Asia/Dhaka'));
    await PrayerAlertStore(repository.uid)
        .save(PrayerAlertSettings(enabled: true));
    final session = ReminderSession(repository: repository);
    expect(await session.refresh(), isTrue);
    final scheduledIds = calls
        .where((c) => c.method == 'zonedSchedule')
        .map((c) => (c.arguments as Map)['id'])
        .toList();
    expect(scheduledIds, contains(1001));
    expect(scheduledIds, contains(prayerAlertRenewalId));
    // Remaining prayers today plus nine complete days, then renewal.
    expect(scheduledIds.where((id) => id != 1001).length,
        inInclusiveRange(46, 51));
    expect(calls.where((c) => c.method.contains('request')), isEmpty);
    session.dispose();
  });

  test('daily reminders follow the changed device timezone on refresh',
      () async {
    final service = ReminderService.instance;
    await service.sync({'tasks': true});
    var scheduled = calls.lastWhere((call) => call.method == 'zonedSchedule');
    expect((scheduled.arguments as Map)['timeZoneName'], 'Asia/Dhaka');
    deviceZone = 'America/New_York';
    await service.sync({'tasks': true});
    scheduled = calls.lastWhere((call) => call.method == 'zonedSchedule');
    expect((scheduled.arguments as Map)['timeZoneName'], 'America/New_York');
  });

  test('daily reminder timezone is isolated from another module timezone state',
      () async {
    final service = ReminderService.instance;
    await service.sync({'tasks': true});
    // Initializing the prayer timezone database resets timezone.local to UTC.
    tz.setLocalLocation(tz.UTC);
    await service.sync({'tasks': true});
    final scheduled = calls.lastWhere((call) => call.method == 'zonedSchedule');
    expect((scheduled.arguments as Map)['timeZoneName'], 'Asia/Dhaka');
  });

  test('daily opt-out cancels alarms even if device timezone lookup fails',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async => throw PlatformException(code: 'unavailable'));
    expect(await ReminderService.instance.sync({'tasks': false}), isTrue);
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
    expect(calls.where((call) => call.method == 'cancel'), hasLength(3));
  });

  test('late refresh cannot overwrite a newer explicit reminder preference',
      () async {
    final repository = _SettingsRepository();
    final session = ReminderSession(repository: repository);
    final refreshing = session.refresh();
    await ReminderService.instance.sync({'tasks': false});
    repository.response.complete({
      'remindersConfigured': true,
      'notifications': {'tasks': true}
    });
    expect(await refreshing, isTrue);
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    session.dispose();
  });

  test('disposed session ignores late settings and reports failures for retry',
      () async {
    final repository = _SettingsRepository();
    final session = ReminderSession(repository: repository);
    final refreshing = session.refresh();
    session.dispose();
    repository.response.complete({
      'remindersConfigured': true,
      'notifications': {'tasks': true}
    });
    expect(await refreshing, isTrue);
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);

    final failedRepository = _SettingsRepository();
    final failedSession = ReminderSession(repository: failedRepository);
    final failedRefresh = failedSession.refresh();
    failedRepository.response.completeError(StateError('offline'));
    expect(await failedRefresh, isFalse);
    failedSession.dispose();
  });

  test('disabled Faith cancels legacy reminders without fetching settings',
      () async {
    final repository = _SettingsRepository();
    final session = ReminderSession(
        repository: repository,
        enabledDailyKeys: const {},
        prayerAlertsEnabled: false);
    expect(await session.refresh(), isTrue);
    final cancelledIds = calls
        .where((call) => call.method == 'cancel')
        .map((call) => (call.arguments as Map)['id'])
        .toSet();
    expect(cancelledIds, contains(1001));
    expect(cancelledIds, contains(prayerAlertIdBase));
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
    session.dispose();
  });

  test(
      'sign-out cancellation finishes in-flight work and invalidates queued schedules',
      () async {
    final started = Completer<void>();
    final release = Completer<void>();
    intercept = (call) async {
      if (call.method == 'zonedSchedule' && !started.isCompleted) {
        started.complete();
        await release.future;
      }
    };
    final service = ReminderService.instance;
    final first = service.sync({'tasks': true});
    await started.future;
    final queued = service.sync({'growth': true});
    final cancelled = service.cancelAll();
    release.complete();
    await first;
    expect(await queued, isFalse);
    await cancelled;
    final scheduled = calls.where((c) => c.method == 'zonedSchedule').toList();
    expect(scheduled, hasLength(1));
    expect((scheduled.single.arguments as Map)['id'], 1001);
    final lastSchedule =
        calls.lastIndexWhere((c) => c.method == 'zonedSchedule');
    expect(calls.skip(lastSchedule + 1).any((c) => c.method == 'cancelAll'),
        isTrue);
  });
}

class _SettingsRepository extends AppRepository {
  _SettingsRepository() : super(uid: 'reminder-test', firebaseReady: false);
  final response = Completer<Map<String, dynamic>?>();
  @override
  bool get canSync => true;
  @override
  Future<Map<String, dynamic>?> loadSettings() => response.future;
}
