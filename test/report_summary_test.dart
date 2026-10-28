import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/progress_trends.dart';

void main() {
  test('report uses one range load and preserves missing, zero and linked days',
      () async {
    final repository = _ReportRepository();
    final report = await repository.buildReport(
      start: DateTime(2026, 10, 30, 23),
      end: DateTime(2026, 11, 2, 1),
    );
    expect(repository.rangeLoads, 1);
    expect(repository.requestedDays, 4);
    expect(report.days, 4);
    expect(report.prayerLoggedDays, 2);
    expect(report.totalPrayed, 1);
    expect(report.totalJamaat, 1);
    expect(report.totalMissed, 1);
    expect(report.totalMadeUp, 4);
    expect(report.totalUnlogged, 4);
    expect(report.growthLoggedDays, 2);
    // The unlogged dates are excluded; the explicitly recorded zero stays.
    expect(report.averageIman, 50);
    expect(report.averageLife, 50);
    expect(report.averageOverall, 50);
  });

  test('rejects reversed or oversized ranges before querying', () async {
    final repository = _ReportRepository();
    await expectLater(
        repository.buildReport(
            start: DateTime(2026, 11, 2), end: DateTime(2026, 11, 1)),
        throwsArgumentError);
    await expectLater(
        repository.buildReport(
            start: DateTime(2025), end: DateTime(2026, 1, 2)),
        throwsArgumentError);
    expect(repository.rangeLoads, 0);
  });

  test('leap-year report includes all 366 calendar days', () async {
    final repository = _ReportRepository();
    final report = await repository.buildReport(
        start: DateTime(2024), end: DateTime(2024, 12, 31));
    expect(repository.requestedDays, 366);
    expect(report.days, 366);
    expect(report.growthLoggedDays, 0);
    expect(report.prayerLoggedDays, 0);
  });
}

class _ReportRepository extends AppRepository {
  _ReportRepository() : super(uid: 'test', firebaseReady: false);
  int rangeLoads = 0;
  int? requestedDays;

  @override
  bool get canSync => true;

  @override
  Future<ProgressTrends> loadProgressTrends(
      {required DateTime end, int dayCount = 30}) async {
    rangeLoads++;
    requestedDays = dayCount;
    return ProgressTrends.fromDocuments(
      end: end,
      dayCount: dayCount,
      prayers: {
        '2026-10-31': {
          'prayers': {
            'fajr': {'state': 'missed'}
          }
        },
        '2026-11-02': {
          'prayers': {
            'fajr': {'state': 'prayed', 'jamat': true},
            for (final key in ['dhuhr', 'asr', 'maghrib', 'isha'])
              key: {'state': 'madeUp'},
          }
        },
      },
      growth: {
        '2026-10-31': _growth(false),
        // A custom checklist keeps its snapshot. The prayer link overrides
        // the saved false answer when all five prayers are completed.
        '2026-11-02': {
          ..._growth(true),
          'prayerLinked': true,
          'growthData': {
            'iman': {'prayer': false},
            'life': {'custom': true}
          },
        },
      },
    );
  }

  Map<String, dynamic> _growth(bool done) => {
        'growthData': {
          'iman': {'prayer': done},
          'life': {'custom': done}
        },
        'checklistItems': {
          'iman': [
            {'key': 'prayer', 'label': 'Prayer'}
          ],
          'life': [
            {'key': 'custom', 'label': 'Custom'}
          ],
        },
      };
}
