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

DateTime yesterday() => dateOnly().subtract(const Duration(days: 1));

Iterable<DateTime> datesBetween(DateTime start, DateTime end) sync* {
  var cursor = dateOnly(start);
  final last = dateOnly(end);
  while (!cursor.isAfter(last)) {
    yield cursor;
    cursor = cursor.add(const Duration(days: 1));
  }
}

String compactDateLabel(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}
