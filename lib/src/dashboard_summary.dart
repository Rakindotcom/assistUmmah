import 'growth_progress.dart';
import 'models.dart';

/// A read-only view of today's data. An absent document is an empty log; a
/// failed read is represented separately by the caller.
class DashboardSummary {
  const DashboardSummary({
    required this.totalTasks,
    required this.completedTasks,
    required this.mustDoRemaining,
    required this.goodToDoRemaining,
    required this.nextMustDo,
    required this.prayersLogged,
    required this.prayersCompleted,
    required this.prayersMissed,
    required this.prayersMadeUp,
    required this.prayersUnlogged,
    required this.jamaatCount,
    required this.growthLogged,
    required this.growthLinked,
    required this.imanScore,
    required this.lifeScore,
  });

  final int totalTasks;
  final int completedTasks;
  final int mustDoRemaining;
  final int goodToDoRemaining;
  final String? nextMustDo;
  final bool prayersLogged;
  final int prayersCompleted;
  final int prayersMissed;
  final int prayersMadeUp;
  final int prayersUnlogged;
  final int jamaatCount;
  final bool growthLogged;
  final bool growthLinked;
  final int imanScore;
  final int lifeScore;

  int get overallScore => ((imanScore + lifeScore) / 2).round();

  factory DashboardSummary.fromDocuments({
    Map<String, dynamic>? tasks,
    Map<String, dynamic>? prayer,
    Map<String, dynamic>? growth,
  }) {
    final taskBuckets = asStringMap(tasks?['todayTasks']);
    List<TaskItem> parseTasks(String section) {
      final raw = taskBuckets[section];
      if (raw is! Iterable) return const [];
      return raw
          .map(TaskItem.fromMap)
          .where((task) => task.text.isNotEmpty)
          .toList();
    }

    final mustDo = parseTasks('mustDo');
    final goodToDo = parseTasks('goodToDo');
    final allTasks = [...mustDo, ...goodToDo];
    final prayerSummary = PrayerSummary.fromDocument(prayer);
    final growthData = asStringMap(growth?['growthData']);
    final growthItems = GrowthChecklistSnapshot.fromDocument(growth);

    return DashboardSummary(
      totalTasks: allTasks.length,
      completedTasks: allTasks.where((task) => task.completed).length,
      mustDoRemaining: mustDo.where((task) => !task.completed).length,
      goodToDoRemaining: goodToDo.where((task) => !task.completed).length,
      nextMustDo: mustDo.where((task) => !task.completed).firstOrNull?.text,
      prayersLogged: prayerSummary.anyLogged,
      prayersCompleted: prayerSummary.prayed,
      prayersMissed: prayerSummary.missed,
      prayersMadeUp: prayerSummary.madeUp,
      prayersUnlogged: prayerSummary.unlogged,
      jamaatCount: prayerSummary.jamaat,
      growthLogged: growthData.isNotEmpty,
      growthLinked: growth?['prayerLinked'] == true,
      imanScore: checklistScore(
        imanValuesForDocuments(growth, prayer),
        growthItems.iman,
      ),
      lifeScore: checklistScore(
        parseBoolMap(growthData['life']),
        growthItems.life,
      ),
    );
  }
}
