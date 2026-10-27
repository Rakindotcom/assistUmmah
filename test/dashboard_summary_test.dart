import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/dashboard_summary.dart';

void main() {
  test("summarizes today's tasks, prayers, and the selected growth checklist",
      () {
    final summary = DashboardSummary.fromDocuments(
      tasks: {
        'todayTasks': {
          'mustDo': [
            {'id': '1', 'text': 'Study', 'completed': false},
            {'id': '2', 'text': 'Call home', 'completed': true},
          ],
          'goodToDo': [
            {'id': '3', 'text': 'Walk', 'completed': false},
          ],
        },
      },
      prayer: {
        'prayers': {
          'fajr': {'prayed': true, 'jamat': true},
          'dhuhr': {'prayed': true, 'jamat': false},
        },
      },
      growth: {
        'userType': 'professional',
        'growthData': {
          'iman': {'istigfar': true},
          'life': {'deepWork': true, 'professionalDev': true},
        },
      },
    );

    expect(summary.totalTasks, 3);
    expect(summary.completedTasks, 1);
    expect(summary.mustDoRemaining, 1);
    expect(summary.goodToDoRemaining, 1);
    expect(summary.nextMustDo, 'Study');
    expect(summary.prayersLogged, isTrue);
    expect(summary.prayersCompleted, 2);
    expect(summary.prayersMissed, 0);
    expect(summary.prayersMadeUp, 0);
    expect(summary.prayersUnlogged, 3);
    expect(summary.jamaatCount, 1);
    expect(summary.growthLogged, isTrue);
    expect(summary.imanScore, 20);
    expect(summary.lifeScore, 40);
    expect(summary.overallScore, 30);
  });

  test('an absent prayer document remains unlogged', () {
    final summary = DashboardSummary.fromDocuments();

    expect(summary.prayersLogged, isFalse);
    expect(summary.prayersCompleted, 0);
    expect(summary.prayersUnlogged, 5);
    expect(summary.growthLogged, isFalse);
    expect(summary.totalTasks, 0);
  });
}
