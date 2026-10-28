import 'date_helpers.dart';
import 'growth_progress.dart';
import 'models.dart';

class ProgressDay {
  const ProgressDay({
    required this.date,
    required this.prayer,
    required this.growthLogged,
    required this.imanScore,
    required this.lifeScore,
  });

  final DateTime date;
  final PrayerSummary prayer;
  final bool growthLogged;
  final int? imanScore;
  final int? lifeScore;

  bool get prayerLogged => prayer.anyLogged;
  int get completedPrayers => prayer.prayed + prayer.madeUp;
  int? get overallScore => imanScore == null || lifeScore == null
      ? null
      : ((imanScore! + lifeScore!) / 2).round();
}

class TrendWindow {
  const TrendWindow({
    required this.days,
    required this.prayerLoggedDays,
    required this.completedPrayers,
    required this.missedPrayers,
    required this.growthLoggedDays,
    required this.averageGrowth,
  });

  final int days;
  final int prayerLoggedDays;
  final int completedPrayers;
  final int missedPrayers;
  final int growthLoggedDays;
  final int? averageGrowth;
}

class ProgressTrends {
  ProgressTrends._(List<ProgressDay> days)
      : days = List<ProgressDay>.unmodifiable(days);

  final List<ProgressDay> days;

  static ProgressTrends fromDocuments({
    required DateTime end,
    required int dayCount,
    required Map<String, Map<String, dynamic>> prayers,
    required Map<String, Map<String, dynamic>> growth,
  }) {
    if (dayCount < 1) throw ArgumentError.value(dayCount, 'dayCount');
    final last = dateOnly(end);
    final first = DateTime(last.year, last.month, last.day - dayCount + 1);
    final days = <ProgressDay>[];
    for (final date in datesBetween(first, last)) {
      final key = dateKey(date);
      final prayerDoc = prayers[key];
      final growthDoc = growth[key];
      final growthData = asStringMap(growthDoc?['growthData']);
      final logged = growthData.isNotEmpty;
      final snapshot = GrowthChecklistSnapshot.fromDocument(growthDoc);
      days.add(ProgressDay(
        date: date,
        prayer: PrayerSummary.fromDocument(prayerDoc),
        growthLogged: logged,
        imanScore: logged
            ? checklistScore(
                imanValuesForDocuments(growthDoc, prayerDoc),
                snapshot.iman,
              )
            : null,
        lifeScore: logged
            ? checklistScore(
                parseBoolMap(growthData['life']),
                snapshot.life,
              )
            : null,
      ));
    }
    return ProgressTrends._(days);
  }

  ReportSummary toReportSummary() {
    final loggedPrayers = days.where((day) => day.prayerLogged);
    final loggedGrowth = days.where((day) => day.growthLogged);
    int average(Iterable<int> values) {
      final scores = values.toList();
      return scores.isEmpty
          ? 0
          : (scores.reduce((a, b) => a + b) / scores.length).round();
    }

    return ReportSummary(
      days: days.length,
      prayerLoggedDays: loggedPrayers.length,
      totalPrayed: loggedPrayers.fold(0, (sum, day) => sum + day.prayer.prayed),
      totalJamaat: loggedPrayers.fold(0, (sum, day) => sum + day.prayer.jamaat),
      totalMissed: loggedPrayers.fold(0, (sum, day) => sum + day.prayer.missed),
      totalMadeUp: loggedPrayers.fold(0, (sum, day) => sum + day.prayer.madeUp),
      totalUnlogged:
          loggedPrayers.fold(0, (sum, day) => sum + day.prayer.unlogged),
      growthLoggedDays: loggedGrowth.length,
      averageIman: average(loggedGrowth.map((day) => day.imanScore!)),
      averageLife: average(loggedGrowth.map((day) => day.lifeScore!)),
      averageOverall: average(loggedGrowth.map((day) => day.overallScore!)),
    );
  }

  TrendWindow window(int startIndex, int length) {
    if (startIndex < 0 || length < 0 || startIndex + length > days.length) {
      throw RangeError('Invalid trend window');
    }
    final selected = days.skip(startIndex).take(length).toList();
    final scores =
        selected.map((day) => day.overallScore).whereType<int>().toList();
    return TrendWindow(
      days: selected.length,
      prayerLoggedDays: selected.where((day) => day.prayerLogged).length,
      completedPrayers:
          selected.fold(0, (sum, day) => sum + day.completedPrayers),
      missedPrayers: selected.fold(0, (sum, day) => sum + day.prayer.missed),
      growthLoggedDays: scores.length,
      averageGrowth: scores.isEmpty
          ? null
          : (scores.reduce((a, b) => a + b) / scores.length).round(),
    );
  }
}
