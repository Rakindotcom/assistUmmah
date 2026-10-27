import 'date_helpers.dart';
import 'models.dart';

enum QuranGoalUnit { minutes, pages }

class QuranGoal {
  const QuranGoal({required this.unit, required this.target});

  final QuranGoalUnit unit;
  final int target;

  static const standard = QuranGoal(unit: QuranGoalUnit.minutes, target: 10);

  int get maxTarget => unit == QuranGoalUnit.minutes ? 1440 : 1000;
  bool get valid => target >= 1 && target <= maxTarget;

  factory QuranGoal.fromMap(Object? raw, {QuranGoal fallback = standard}) {
    final map = asStringMap(raw);
    final QuranGoalUnit? unit = switch (map['unit']) {
      'pages' => QuranGoalUnit.pages,
      'minutes' => QuranGoalUnit.minutes,
      _ => null,
    };
    if (unit == null) return fallback;
    final target = map['target'];
    final parsed = target is int ? target : int.tryParse('$target');
    final goal = QuranGoal(unit: unit, target: parsed ?? 0);
    return goal.valid ? goal : fallback;
  }

  Map<String, Object> toMap() => {'unit': unit.name, 'target': target};
}

class QuranReadingDay {
  const QuranReadingDay({
    required this.date,
    required this.logged,
    required this.minutes,
    required this.pages,
    required this.lastRead,
    required this.goal,
  });

  final String date;
  final bool logged;
  final int minutes;
  final int pages;
  final String lastRead;
  final QuranGoal goal;

  int get completed => goal.unit == QuranGoalUnit.minutes ? minutes : pages;
  bool get goalMet => logged && completed >= goal.target;
  double get fraction => (completed / goal.target).clamp(0.0, 1.0);

  factory QuranReadingDay.fromDocument(
    String date,
    Map<String, dynamic>? data, {
    required QuranGoal fallbackGoal,
  }) {
    int nonNegative(Object? value) {
      final parsed = value is int ? value : int.tryParse('$value');
      return parsed == null || parsed < 0 ? 0 : parsed;
    }

    final goal = data?['goal'] == null
        ? fallbackGoal
        : QuranGoal.fromMap(data?['goal'], fallback: fallbackGoal);
    final label = data?['lastRead'];
    return QuranReadingDay(
      date: date,
      logged: data?.containsKey('minutes') == true ||
          data?.containsKey('pages') == true,
      minutes: nonNegative(data?['minutes']),
      pages: nonNegative(data?['pages']),
      lastRead: label is String ? label.trim() : '',
      goal: goal,
    );
  }

  Map<String, Object> toMap() => {
        'date': date,
        'minutes': minutes,
        'pages': pages,
        'lastRead': lastRead.trim(),
        'goal': goal.toMap(),
      };
}

class QuranHistory {
  QuranHistory._(List<QuranReadingDay> days)
      : days = List<QuranReadingDay>.unmodifiable(days);

  final List<QuranReadingDay> days;

  int get loggedDays => days.where((day) => day.logged).length;
  int get goalsMet => days.where((day) => day.goalMet).length;
  int get totalMinutes => days.fold(0, (sum, day) => sum + day.minutes);
  int get totalPages => days.fold(0, (sum, day) => sum + day.pages);

  static QuranHistory fromDocuments({
    required DateTime end,
    required int dayCount,
    required Map<String, Map<String, dynamic>> documents,
    required QuranGoal fallbackGoal,
  }) {
    if (dayCount < 1) throw ArgumentError.value(dayCount, 'dayCount');
    final last = dateOnly(end);
    final first = DateTime(last.year, last.month, last.day - dayCount + 1);
    return QuranHistory._([
      for (final date in datesBetween(first, last))
        QuranReadingDay.fromDocument(
          dateKey(date),
          documents[dateKey(date)],
          fallbackGoal: fallbackGoal,
        ),
    ]);
  }
}
