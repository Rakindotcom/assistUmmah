import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/prayer_alerts.dart';
import 'package:ummah_assist/src/pages/prayer_alert_card.dart';
import 'package:ummah_assist/src/prayer_times_service.dart';

void main() {
  final dhaka = PrayerTimeConfig(
    latitude: 23.81,
    longitude: 90.41,
    placeName: 'Dhaka',
    timeZoneId: 'Asia/Dhaka',
  );
  final localMidnight = DateTime.utc(2026, 10, 24, 18);

  test('schedules every prayer over ten days with distinct bounded IDs', () {
    final alerts = PrayerAlertPlanner.upcoming(
      config: dhaka,
      settings: PrayerAlertSettings(enabled: true),
      now: localMidnight,
    );

    expect(alerts, hasLength(50));
    expect(alerts.map((alert) => alert.id).toSet(), hasLength(50));
    expect(alerts.first.id, prayerAlertIdBase);
    expect(alerts.last.id, prayerAlertIdBase + 49);
    expect(alerts.every((alert) => alert.time.isAfter(localMidnight)), isTrue);
    for (var index = 1; index < alerts.length; index++) {
      expect(alerts[index].time.isAfter(alerts[index - 1].time), isTrue);
    }
  });

  test('lead time, selected prayers, and quiet hours affect the plan', () {
    final settings = PrayerAlertSettings(
      enabled: true,
      selectedPrayers: {'fajr': true, 'isha': true},
      leadMinutes: 10,
      quietEnabled: true,
      quietStartMinute: 22 * 60,
      quietEndMinute: 6 * 60,
    );
    final alerts = PrayerAlertPlanner.upcoming(
      config: dhaka,
      settings: settings,
      now: localMidnight,
      daysAhead: 1,
    );
    final schedule = PrayerTimeService.forDay(dhaka, DateTime(2026, 10, 25));

    expect(alerts.map((alert) => alert.prayerKey), ['isha']);
    expect(
      alerts.single.time,
      schedule.entries.last.time.subtract(const Duration(minutes: 10)),
    );
  });

  test('disabled alerts plan nothing and renewal stays inside the horizon', () {
    expect(
      PrayerAlertPlanner.upcoming(
        config: dhaka,
        settings: PrayerAlertSettings(),
        now: localMidnight,
      ),
      isEmpty,
    );
    final renewal = PrayerAlertPlanner.renewalTime(dhaka, localMidnight);
    expect(renewal.year, 2026);
    expect(renewal.month, 11);
    expect(renewal.day, 2);
    expect(renewal.hour, 12);
  });

  test('settings round trip, validation, and user scoped storage', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final settings = PrayerAlertSettings(
      enabled: true,
      selectedPrayers: {'fajr': true, 'dhuhr': false},
      leadMinutes: 15,
      silent: true,
      quietEnabled: true,
      quietStartMinute: 23 * 60,
      quietEndMinute: 5 * 60,
    );
    final store = PrayerAlertStore('first-user');
    await store.save(settings);
    final restored = await store.load();

    expect(restored.toJson(), settings.toJson());
    expect((await PrayerAlertStore('second-user').load()).enabled, isFalse);
    expect(
      () => PrayerAlertSettings(leadMinutes: 7),
      throwsFormatException,
    );
    expect(
      () => PrayerAlertSettings(
        quietEnabled: true,
        quietStartMinute: 120,
        quietEndMinute: 120,
      ),
      throwsFormatException,
    );
    await store.remove();
    expect((await store.load()).enabled, isFalse);
  });

  testWidgets('alerts remain switchable off if location settings are missing', (
    tester,
  ) async {
    PrayerAlertSettings? changed;
    bool? requestedPermission;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrayerAlertCard(
            settings: PrayerAlertSettings(enabled: true),
            locationReady: false,
            busy: false,
            permissionGranted: true,
            exact: true,
            scheduledCount: 0,
            onChanged: (next, requestPermission) {
              changed = next;
              requestedPermission = requestPermission;
            },
            onConfigureLocation: () {},
          ),
        ),
      ),
    );

    expect(find.text('আগে নামাজের সময় সেট করুন'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    expect(changed?.enabled, isFalse);
    expect(requestedPermission, isFalse);
  });
}
