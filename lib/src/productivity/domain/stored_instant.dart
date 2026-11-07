import 'calendar_day.dart';

/// Our persisted instants are explicit UTC. DateTime.parse alone accepts missing
/// offsets and normalizes invalid dates, which would diverge between devices.
DateTime parseStoredInstant(String value) {
  final match = RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?Z$')
      .firstMatch(value);
  if (match == null) {
    throw const FormatException('Use an explicit UTC instant.');
  }
  CalendarDay(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
  if (int.parse(match[4]!) > 23 ||
      int.parse(match[5]!) > 59 ||
      int.parse(match[6]!) > 59) {
    throw const FormatException('Invalid instant clock time.');
  }
  return DateTime.parse(value).toUtc();
}
