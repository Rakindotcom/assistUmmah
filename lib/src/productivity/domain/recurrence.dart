import 'calendar_day.dart';

enum RecurrenceFrequency { daily, weekly, monthly, yearly }

enum MissingMonthDay { skip, lastDay }

class RecurrenceRule {
  RecurrenceRule(
      {required this.start,
      required this.frequency,
      this.interval = 1,
      Iterable<int> weekdays = const [],
      Iterable<int> monthDays = const [],
      this.end,
      this.count,
      this.paused = false,
      this.pauseUntil,
      Iterable<CalendarDay> excludedDates = const [],
      this.missingMonthDay = MissingMonthDay.skip})
      : weekdays = Set.unmodifiable(weekdays),
        monthDays = Set.unmodifiable(monthDays),
        excludedDates = Set.unmodifiable(excludedDates) {
    if (interval < 1 ||
        interval > 365 ||
        (end != null && end!.isBefore(start)) ||
        (count != null && (count! < 1 || count! > 100000)) ||
        this.weekdays.any((day) => day < 1 || day > 7) ||
        this.monthDays.any((day) => day == 0 || day < -31 || day > 31)) {
      throw const FormatException('Invalid recurrence schedule.');
    }
  }
  final CalendarDay start;
  final RecurrenceFrequency frequency;
  final int interval;
  final Set<int> weekdays, monthDays;
  final CalendarDay? end, pauseUntil;
  final int? count;
  final bool paused;
  final Set<CalendarDay> excludedDates;
  final MissingMonthDay missingMonthDay;

  bool _monthDayMatches(CalendarDay date) {
    final selected = monthDays.isEmpty ? {start.day} : monthDays;
    return selected.any((day) {
      final target = day > 0 ? day : date.daysInMonth + day + 1;
      return date.day == target ||
          (missingMonthDay == MissingMonthDay.lastDay &&
              target > date.daysInMonth &&
              date.day == date.daysInMonth);
    });
  }

  bool _scheduled(CalendarDay date) {
    if (date.isBefore(start) || (end != null && date.isAfter(end!))) {
      return false;
    }
    final delta = date.difference(start);
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return delta % interval == 0 &&
            (weekdays.isEmpty || weekdays.contains(date.weekday));
      case RecurrenceFrequency.weekly:
        final startOfWeek = start.addDays(1 - start.weekday);
        return (date.difference(startOfWeek) ~/ 7) % interval == 0 &&
            (weekdays.isEmpty
                ? date.weekday == start.weekday
                : weekdays.contains(date.weekday));
      case RecurrenceFrequency.monthly:
        final months = (date.year - start.year) * 12 + date.month - start.month;
        return months % interval == 0 &&
            _monthDayMatches(date) &&
            (weekdays.isEmpty || weekdays.contains(date.weekday));
      case RecurrenceFrequency.yearly:
        return (date.year - start.year) % interval == 0 &&
            date.month == start.month &&
            _monthDayMatches(date) &&
            (weekdays.isEmpty || weekdays.contains(date.weekday));
    }
  }

  /// Count applies to scheduled occurrences before exceptions, matching common
  /// calendar recurrence semantics. Skipped/rest days are not failed check-ins.
  List<CalendarDay> between(CalendarDay from, CalendarDay to,
      {int limit = 1000}) {
    if (to.isBefore(from) ||
        limit < 1 ||
        limit > 20000 ||
        to.difference(from) > 3660) {
      throw ArgumentError('Choose a bounded recurrence range.');
    }
    if (paused || to.isBefore(start)) return const [];
    final first = from.isBefore(start) ? start : from;
    if (first.difference(start) > 36600 && count != null) {
      throw ArgumentError(
          'Count-limited recurrence spans more than 100 years.');
    }
    var ordinal = 0;
    if (count != null) {
      for (var date = start; date.isBefore(first); date = date.addDays(1)) {
        if (_scheduled(date)) ordinal++;
        if (ordinal >= count!) return const [];
      }
    }
    final result = <CalendarDay>[];
    for (var offset = 0; offset <= to.difference(first); offset++) {
      final date = first.addDays(offset);
      if (!_scheduled(date)) continue;
      ordinal++;
      if (count != null && ordinal > count!) break;
      if (excludedDates.contains(date) ||
          (pauseUntil != null && !date.isAfter(pauseUntil!))) {
        continue;
      }
      result.add(date);
      if (result.length >= limit) break;
    }
    return List.unmodifiable(result);
  }

  Map<String, Object?> toJson() => {
        'start': start.toString(),
        'frequency': frequency.name,
        'interval': interval,
        'weekdays': weekdays.toList()..sort(),
        'monthDays': monthDays.toList()..sort(),
        'end': end?.toString(),
        'count': count,
        'paused': paused,
        'pauseUntil': pauseUntil?.toString(),
        'excludedDates': excludedDates.map((day) => day.toString()).toList()
          ..sort(),
        'missingMonthDay': missingMonthDay.name,
      };
  factory RecurrenceRule.fromJson(Map<String, dynamic> json) => RecurrenceRule(
      start: CalendarDay.parse(json['start'] as String),
      frequency: RecurrenceFrequency.values.byName(json['frequency'] as String),
      interval: json['interval'] as int? ?? 1,
      weekdays: List<int>.from(json['weekdays'] as List? ?? []),
      monthDays: List<int>.from(json['monthDays'] as List? ?? []),
      end:
          json['end'] == null ? null : CalendarDay.parse(json['end'] as String),
      count: json['count'] as int?,
      paused: json['paused'] == true,
      pauseUntil: json['pauseUntil'] == null
          ? null
          : CalendarDay.parse(json['pauseUntil'] as String),
      excludedDates: (json['excludedDates'] as List? ?? [])
          .map((day) => CalendarDay.parse(day as String)),
      missingMonthDay: MissingMonthDay.values
          .byName(json['missingMonthDay'] as String? ?? 'skip'));
}
