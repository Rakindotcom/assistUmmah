import 'display_formatters.dart';

String dateKey([DateTime? value]) {
  final date = value ?? DateTime.now();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

DateTime dateOnly([DateTime? value]) {
  final date = value ?? DateTime.now();
  return DateTime(date.year, date.month, date.day);
}

DateTime yesterday() {
  final today = dateOnly();
  return DateTime(today.year, today.month, today.day - 1);
}

Iterable<DateTime> datesBetween(DateTime start, DateTime end) sync* {
  var cursor = dateOnly(start);
  final last = dateOnly(end);
  while (!cursor.isAfter(last)) {
    yield cursor;
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
}

String compactDateLabel(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return banglaDigits('$day/$month/${date.year}');
}
