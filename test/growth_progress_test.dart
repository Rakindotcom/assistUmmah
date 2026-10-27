import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/dashboard_summary.dart';
import 'package:ummah_assist/src/growth_progress.dart';

void main() {
  test('five prayed or made-up prayers complete the linked item', () {
    final prayer = {
      'prayers': {
        'fajr': {'state': 'prayed'},
        'dhuhr': {'state': 'prayed'},
        'asr': {'state': 'madeUp'},
        'maghrib': {'state': 'prayed'},
        'isha': {'state': 'prayed'},
      },
    };
    expect(fivePrayersCompleted(prayer), isTrue);
    expect(fivePrayersCompleted(null), isFalse);
    final summary = DashboardSummary.fromDocuments(
      prayer: prayer,
      growth: {
        'userType': 'student',
        'prayerLinked': true,
        'growthData': {
          'iman': {'prayer': false},
          'life': <String, bool>{},
        },
      },
    );
    expect(summary.imanScore, 20);
  });

  test('linked missed prayer clears a stale saved check', () {
    final summary = DashboardSummary.fromDocuments(
      prayer: {
        'prayers': {
          'fajr': {'state': 'missed'},
          'dhuhr': {'state': 'prayed'},
          'asr': {'state': 'prayed'},
          'maghrib': {'state': 'prayed'},
          'isha': {'state': 'prayed'},
        },
      },
      growth: {
        'prayerLinked': true,
        'growthData': {
          'iman': {'prayer': true},
          'life': <String, bool>{},
        },
      },
    );
    expect(summary.imanScore, 0);
  });

  test('legacy manual prayer checks remain unchanged', () {
    final summary = DashboardSummary.fromDocuments(growth: {
      'growthData': {
        'iman': {'prayer': true},
        'life': <String, bool>{},
      },
    });
    expect(summary.imanScore, 20);
  });
}
