import 'package:timezone/timezone.dart' as tz;

import 'display_formatters.dart';
import 'prayer_times_service.dart';

/// Clock-derived presentation data. Updating a countdown never reads Firestore.
class HomePrayerSnapshot {
  HomePrayerSnapshot(PrayerTimeConfig config, DateTime instant) {
    now = tz.TZDateTime.from(
        instant, PrayerTimeService.location(config.timeZoneId));
    schedule = PrayerTimeService.forDay(config, now);
    next = PrayerTimeService.nextPrayer(config, now);
    final previous = PrayerTimeService.forDay(
        config, DateTime(now.year, now.month, now.day - 1));
    final all = [...previous.entries, ...schedule.entries];
    latest = all.lastWhere((entry) => !entry.time.isAfter(now));
    final elapsed = now.difference(latest.time).inMilliseconds;
    final span = next.time.difference(latest.time).inMilliseconds;
    progress = span <= 0 ? 0 : (elapsed / span).clamp(0.0, 1.0);
  }

  late final tz.TZDateTime now;
  late final PrayerSchedule schedule;
  late final PrayerTimeEntry next;
  late final PrayerTimeEntry latest;
  late final double progress;

  Duration get remaining => next.time.difference(now);
  bool get nextIsTomorrow =>
      next.time.day != now.day || next.time.month != now.month;

  /// Sunrise is separate from the five daily prayer starts.
  bool get afterSunriseBeforeDhuhr =>
      latest.key == 'fajr' &&
      schedule.sunrise != null &&
      !now.isBefore(schedule.sunrise!);
}

String prayerCountdown(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 172800);
  final hours = seconds ~/ 3600;
  final minutes = seconds % 3600 ~/ 60;
  return banglaDigits('${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}');
}
