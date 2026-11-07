import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

import 'calendar_day.dart';

/// Converts wall-clock input without silently shifting a missing DST hour.
/// A fall-back overlap returns two instants so the UI can ask which was intended.
abstract final class PlanningTimeZone {
  static bool _initialized = false;
  static tz.Location location(String name) {
    if (!_initialized) {
      data.initializeTimeZones();
      _initialized = true;
    }
    return tz.getLocation(name);
  }

  static tz.TZDateTime inZone(DateTime instant, String zone) =>
      tz.TZDateTime.from(instant.toUtc(), location(zone));
  static List<String> get availableZones {
    location('UTC');
    return tz.timeZoneDatabase.locations.keys.toList()..sort();
  }

  static List<DateTime> candidates(
      CalendarDay day, int hour, int minute, String zone) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw const FormatException('Invalid local time.');
    }
    final place = location(zone);
    final nominal = DateTime.utc(day.year, day.month, day.day, hour, minute);
    final offsets = <int>{};
    for (var hours = -36; hours <= 36; hours += 6) {
      offsets.add(tz.TZDateTime.from(nominal.add(Duration(hours: hours)), place)
          .timeZoneOffset
          .inMilliseconds);
    }
    final result = <DateTime>[];
    for (final offset in offsets) {
      final instant = DateTime.fromMillisecondsSinceEpoch(
          nominal.millisecondsSinceEpoch - offset,
          isUtc: true);
      final local = tz.TZDateTime.from(instant, place);
      if (local.year == day.year &&
          local.month == day.month &&
          local.day == day.day &&
          local.hour == hour &&
          local.minute == minute) {
        result.add(instant);
      }
    }
    result.sort();
    return List.unmodifiable(result);
  }
}
