import 'package:characters/characters.dart';

import 'date_helpers.dart';
import 'models.dart';

class DhikrGoal {
  const DhikrGoal({required this.id, required this.name, required this.target});

  final String id;
  final String name;
  final int target;

  bool get valid =>
      RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id) &&
      name.trim().isNotEmpty &&
      name.trim().characters.length <= 60 &&
      target >= 1 &&
      target <= 100000;

  Map<String, Object> toMap() =>
      {'id': id, 'name': name.trim(), 'target': target};

  static DhikrGoal? fromMap(Object? raw) {
    final map = asStringMap(raw);
    final goal = DhikrGoal(
      id: map['id'] is String ? map['id'] as String : '',
      name: map['name'] is String ? (map['name'] as String).trim() : '',
      target: map['target'] is int ? map['target'] as int : 0,
    );
    return goal.valid ? goal : null;
  }
}

class DhikrGoals {
  DhikrGoals(Iterable<DhikrGoal> goals) : items = List.unmodifiable(goals);

  final List<DhikrGoal> items;

  static final standard = DhikrGoals(const [
    DhikrGoal(id: 'subhanallah', name: 'সুবহানাল্লাহ', target: 33),
    DhikrGoal(id: 'alhamdulillah', name: 'আলহামদুলিল্লাহ', target: 33),
    DhikrGoal(id: 'allahu_akbar', name: 'আল্লাহু আকবার', target: 34),
  ]);

  bool get valid =>
      items.isNotEmpty &&
      items.length <= 20 &&
      items.every((goal) => goal.valid) &&
      items.map((goal) => goal.id).toSet().length == items.length;

  List<Map<String, Object>> toList() =>
      items.map((goal) => goal.toMap()).toList();

  static DhikrGoals fromList(Object? raw, {DhikrGoals? fallback}) {
    if (raw is! List) return fallback ?? standard;
    final parsed = raw.map(DhikrGoal.fromMap).toList();
    if (parsed.any((goal) => goal == null)) return fallback ?? standard;
    final result = DhikrGoals(parsed.cast<DhikrGoal>());
    return result.valid ? result : fallback ?? standard;
  }
}

class DhikrDay {
  DhikrDay({
    required this.date,
    required this.logged,
    required this.goals,
    required Map<String, int> counts,
  }) : counts = Map.unmodifiable(counts);

  final String date;
  final bool logged;
  final DhikrGoals goals;
  final Map<String, int> counts;
  static const maxCount = 1000000;

  int count(String id) => counts[id] ?? 0;
  int get total => counts.values.fold(0, (sum, value) => sum + value);
  int get goalsMet =>
      goals.items.where((goal) => count(goal.id) >= goal.target).length;

  factory DhikrDay.fromDocument(String date, Map<String, dynamic>? data,
      {required DhikrGoals fallback}) {
    final goals = DhikrGoals.fromList(data?['goals'], fallback: fallback);
    final rawCounts = asStringMap(data?['counts']);
    return DhikrDay(
      date: date,
      logged: data?['counts'] is Map,
      goals: goals,
      counts: {
        for (final goal in goals.items)
          goal.id: rawCounts[goal.id] is int
              ? (rawCounts[goal.id] as int).clamp(0, maxCount)
              : 0,
      },
    );
  }

  DhikrDay change(String id, int delta) {
    if (!goals.items.any((goal) => goal.id == id)) {
      throw ArgumentError.value(id, 'id');
    }
    final next = count(id) + delta;
    if (next > maxCount) throw ArgumentError.value(next, 'count');
    return DhikrDay(
      date: date,
      logged: true,
      goals: goals,
      counts: {...counts, id: next.clamp(0, maxCount)},
    );
  }

  Map<String, Object> toMap() => {
        'date': date,
        'goals': goals.toList(),
        'counts': counts,
      };
}

class DhikrHistory {
  DhikrHistory(
      {required DateTime end,
      required Map<String, Map<String, dynamic>> documents,
      required DhikrGoals fallback,
      int dayCount = 7})
      : days = List.unmodifiable([
          for (final date in datesBetween(
              DateTime(end.year, end.month, end.day - dayCount + 1), end))
            DhikrDay.fromDocument(dateKey(date), documents[dateKey(date)],
                fallback: fallback),
        ]);

  final List<DhikrDay> days;
  int get total => days.fold(0, (sum, day) => sum + day.total);
  int get loggedDays => days.where((day) => day.logged).length;
}
