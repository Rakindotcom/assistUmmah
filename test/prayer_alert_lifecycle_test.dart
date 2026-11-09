import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';
import 'package:ummah_assist/src/prayer_alerts.dart';
import 'package:ummah_assist/src/prayer_times_service.dart';
import 'package:ummah_assist/src/reminder_session.dart';

import 'support/native_ui_channels.dart';

void main() {
  testWidgets(
      'resume during exact access request cannot cancel the new prayer alerts',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    configureNativeUiChannels();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final permissionStarted = Completer<void>();
    final permissionResult = Completer<bool>();
    final pending = <int>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      switch (call.method) {
        case 'initialize':
        case 'areNotificationsEnabled':
        case 'requestNotificationsPermission':
          return true;
        case 'canScheduleExactNotifications':
          return false;
        case 'requestExactAlarmsPermission':
          permissionStarted.complete();
          return permissionResult.future;
        case 'cancel':
          pending.remove((call.arguments as Map)['id']);
          return null;
        case 'zonedSchedule':
          pending.add((call.arguments as Map)['id'] as int);
          return null;
        default:
          throw StateError('Unexpected platform call ${call.method}');
      }
    });
    final repository = _PrayerRepository();
    await PrayerTimeStore(repository.uid).save(PrayerTimeConfig(
        latitude: 23.81,
        longitude: 90.41,
        placeName: 'ঢাকা',
        timeZoneId: 'Asia/Dhaka'));
    await tester.pumpWidget(UmmahAssistApp(
        firebaseReady: false,
        home: Scaffold(
            body: PrayerPage(repository: repository, day: DateTime.now()))));
    await tester.pumpAndSettle();
    final control =
        find.widgetWithText(SwitchListTile, 'নামাজের সময়ের অ্যালার্ট');
    await tester.scrollUntilVisible(control, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester
        .tap(find.descendant(of: control, matching: find.byType(Switch)));
    for (var i = 0; i < 30 && !permissionStarted.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(permissionStarted.isCompleted, isTrue);
    // HomeShell resumes while Android's permission activity is returning. The
    // local preference is still disabled until scheduling and persistence finish.
    final session = ReminderSession(repository: repository);
    final refreshing = session.refresh();
    await tester.pump();
    await tester.pump();
    permissionResult.complete(false);
    await tester.pumpAndSettle();
    expect(await refreshing, isTrue);
    expect(tester.widget<SwitchListTile>(control).value, isTrue);
    expect((await PrayerAlertStore(repository.uid).load()).enabled, isTrue);
    expect(pending, contains(prayerAlertRenewalId));
    expect(
        pending.where(
            (id) => id >= prayerAlertIdBase && id < prayerAlertRenewalId),
        isNotEmpty);
    expect(tester.takeException(), isNull);
    session.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}

class _PrayerRepository extends AppRepository {
  _PrayerRepository()
      : super(uid: 'prayer-lifecycle-test', firebaseReady: false);
  @override
  bool get canSync => true;
  @override
  Future<Map<String, dynamic>?> loadPrayerDocument(String date) async => {};
  @override
  Future<Map<String, dynamic>?> loadSettings() async => {
        'remindersConfigured': false,
        'notifications': {'prayer': false, 'tasks': false, 'growth': false},
      };
}
