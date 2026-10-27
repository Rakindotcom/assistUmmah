import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/prayer_times_service.dart';

void main() {
  final dhaka = PrayerTimeConfig(
    latitude: 23.81,
    longitude: 90.41,
    placeName: 'Dhaka',
    timeZoneId: 'Asia/Dhaka',
  );

  test('calculates five ordered times in the chosen time zone', () {
    final schedule = PrayerTimeService.forDay(dhaka, DateTime(2026, 10, 25));

    expect(
      schedule.entries.map((entry) => entry.key),
      ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'],
    );
    for (var i = 0; i < schedule.entries.length; i++) {
      final time = schedule.entries[i].time;
      expect(time.year, 2026);
      expect(time.month, 10);
      expect(time.day, 25);
      expect(time.timeZoneOffset, const Duration(hours: 6));
      if (i > 0) {
        expect(time.isAfter(schedule.entries[i - 1].time), isTrue);
      }
    }
  });

  test('Hanafi Asr is later than Shafi Asr and offsets apply', () {
    final day = DateTime(2026, 10, 25);
    final hanafi = PrayerTimeService.forDay(dhaka, day);
    final shafi = PrayerTimeService.forDay(
      dhaka.copyWith(madhab: 'shafi'),
      day,
    );
    final adjusted = PrayerTimeService.forDay(
      dhaka.copyWith(adjustments: {'fajr': 5}),
      day,
    );

    expect(hanafi.entries[2].time.isAfter(shafi.entries[2].time), isTrue);
    expect(
      adjusted.entries.first.time.difference(hanafi.entries.first.time),
      const Duration(minutes: 5),
    );
  });

  test('after Isha, next prayer is tomorrow Fajr', () {
    final today = PrayerTimeService.forDay(dhaka, DateTime(2026, 10, 25));
    final next = PrayerTimeService.nextPrayer(
      dhaka,
      today.entries.last.time.add(const Duration(minutes: 1)),
    );

    expect(next.key, 'fajr');
    expect(next.time.day, 26);
  });

  test('settings round trip and invalid coordinates are rejected', () {
    final restored = PrayerTimeConfig.fromJson(dhaka.toJson());
    expect(restored.latitude, dhaka.latitude);
    expect(restored.timeZoneId, dhaka.timeZoneId);
    expect(restored.method, 'karachi');

    expect(
      () => PrayerTimeConfig(
        latitude: 91,
        longitude: 90,
        placeName: 'Invalid',
        timeZoneId: 'Asia/Dhaka',
      ),
      throwsFormatException,
    );
  });

  test('local prayer settings persist for the same user', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = PrayerTimeStore('test-user');
    await store.save(dhaka);
    final restored = await store.load();
    expect(restored?.placeName, 'Dhaka');
    expect(restored?.latitude, 23.81);
    expect(await PrayerTimeStore('another-user').load(), isNull);
  });
}
