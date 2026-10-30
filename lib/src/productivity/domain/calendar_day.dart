/// A civil calendar date, independent of the duration of a local DST day.
class CalendarDay implements Comparable<CalendarDay> {
  CalendarDay(this.year, this.month, this.day) {
    final normalized = DateTime.utc(year, month, day);
    if (year < 1900 ||
        year > 9999 ||
        normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw const FormatException('Invalid calendar date.');
    }
  }
  factory CalendarDay.fromDate(DateTime value) =>
      CalendarDay(value.year, value.month, value.day);
  factory CalendarDay.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) throw const FormatException('Use YYYY-MM-DD dates.');
    return CalendarDay(
        int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
  }
  final int year, month, day;
  DateTime get utc => DateTime.utc(year, month, day);
  int get weekday => utc.weekday;
  int get daysInMonth => DateTime.utc(year, month + 1, 0).day;
  CalendarDay addDays(int days) =>
      CalendarDay.fromDate(utc.add(Duration(days: days)));
  int difference(CalendarDay other) => utc.difference(other.utc).inDays;
  bool isBefore(CalendarDay other) => compareTo(other) < 0;
  bool isAfter(CalendarDay other) => compareTo(other) > 0;
  @override
  int compareTo(CalendarDay other) => utc.compareTo(other.utc);
  @override
  bool operator ==(Object other) =>
      other is CalendarDay &&
      year == other.year &&
      month == other.month &&
      day == other.day;
  @override
  int get hashCode => Object.hash(year, month, day);
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
