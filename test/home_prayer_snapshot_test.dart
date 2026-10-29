import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:ummah_assist/src/home_prayer_snapshot.dart';
import 'package:ummah_assist/src/prayer_times_service.dart';

void main() {
  final config = PrayerTimeConfig(
      latitude: 23.81,
      longitude: 90.41,
      placeName: 'ঢাকা',
      timeZoneId: 'Asia/Dhaka');

  test('next prayer changes exactly at a prayer start', () {
    final schedule = PrayerTimeService.forDay(config, DateTime(2026, 10, 29));
    final asr = schedule.entries[2];
    final before = HomePrayerSnapshot(
        config, asr.time.subtract(const Duration(seconds: 1)));
    expect(before.next.key, 'asr');
    expect(before.remaining, const Duration(seconds: 1));
    final at = HomePrayerSnapshot(config, asr.time);
    expect(at.latest.key, 'asr');
    expect(at.next.key, 'maghrib');
    expect(at.progress, 0);
  });

  test('sunrise gap is distinct from a continuing Fajr prayer period', () {
    final schedule = PrayerTimeService.forDay(config, DateTime(2026, 10, 29));
    final after = HomePrayerSnapshot(
        config, schedule.sunrise!.add(const Duration(seconds: 1)));
    expect(after.afterSunriseBeforeDhuhr, isTrue);
    expect(after.next.key, 'dhuhr');
    expect(
        HomePrayerSnapshot(config, schedule.entries.first.time)
            .afterSunriseBeforeDhuhr,
        isFalse);
  });

  test('late night and midnight use the configured location date', () {
    final zone = PrayerTimeService.location(config.timeZoneId);
    final late =
        HomePrayerSnapshot(config, tz.TZDateTime(zone, 2026, 10, 29, 23));
    expect(late.next.key, 'fajr');
    expect(late.nextIsTomorrow, isTrue);
    final midnight = HomePrayerSnapshot(config, DateTime.utc(2026, 10, 29, 19));
    expect(midnight.now.day, 30);
    expect(midnight.next.time.day, 30);
    expect(midnight.latest.key, 'isha');
    expect(midnight.remaining.isNegative, isFalse);
  });

  test(
      'countdown displays Bengali hours minutes seconds and clamps expired times',
      () {
    expect(prayerCountdown(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '০১:০২:০৩');
    expect(prayerCountdown(const Duration(seconds: -1)), '০০:০০:০০');
  });
}
