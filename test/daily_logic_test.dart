import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/daily_logic.dart';
import 'package:ummah_assist/src/date_helpers.dart';
import 'package:ummah_assist/src/home_shell.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';

void main() {
  test('unlogged prayers are not classified as qaza', () {
    expect(isQazaPending({}, {}, 'fajr'), isFalse);
    expect(
      isQazaPending(
        {
          'fajr': {'prayed': false},
        },
        {},
        'fajr',
      ),
      isTrue,
    );
    expect(
      isQazaPending(
        {
          'fajr': {'prayed': false},
        },
        {'fajr': true},
        'fajr',
      ),
      isFalse,
    );
  });

  test('today’s remaining prayers are not reported as missed', () {
    final today = DateTime(2026, 10, 25);
    expect(missedPrayerCountForDay(today, today, 1), 0);
    expect(missedPrayerCountForDay(DateTime(2026, 10, 24), today, 1), 4);
  });

  test('rollover moves unfinished tasks and removes completed tasks', () {
    TaskItem task(String id, bool completed) => TaskItem(
          id: id,
          text: id,
          completed: completed,
          createdAt: '',
          dateCreated: '2026-10-24',
        );
    final today = <String, List<TaskItem>>{
      'mustDo': [task('unfinished', false), task('finished', true)],
      'goodToDo': [],
    };
    final missed = <String, List<TaskItem>>{'mustDo': [], 'goodToDo': []};

    expect(rollOverTaskBuckets(today, missed, '2026-10-25'), isTrue);
    expect(today['mustDo'], isEmpty);
    expect(missed['mustDo']!.map((task) => task.id), ['unfinished']);
  });

  test('rollover uses the stored document day for legacy tasks', () {
    final today = <String, List<TaskItem>>{
      'mustDo': [
        const TaskItem(
          id: 'legacy',
          text: 'Legacy task',
          completed: false,
          createdAt: '',
          dateCreated: '',
        ),
      ],
      'goodToDo': [],
    };
    final missed = <String, List<TaskItem>>{
      'mustDo': [],
      'goodToDo': [],
    };

    expect(
      rollOverTaskBuckets(
        today,
        missed,
        '2026-10-25',
        previousDate: '2026-10-24',
      ),
      isTrue,
    );
    expect(today['mustDo'], isEmpty);
    expect(missed['mustDo']!.single.id, 'legacy');
  });

  test('date range advances by calendar days', () {
    expect(
      datesBetween(
        DateTime(2026, 10, 24),
        DateTime(2026, 10, 26),
      ).map((date) => dateKey(date)),
      ['2026-10-24', '2026-10-25', '2026-10-26'],
    );
  });

  testWidgets('daily pages reload when the app resumes on a new day', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 25, 23, 59);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          firebaseReady: false,
          repository: const AppRepository(uid: 'demo', firebaseReady: false),
          user: null,
          clock: () => now,
        ),
      ),
    );
    final prayerPage = find.byType(PrayerPage, skipOffstage: false);
    expect(tester.widget<PrayerPage>(prayerPage).day.day, 25);

    now = DateTime(2026, 10, 26, 0, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.widget<PrayerPage>(prayerPage).day.day, 26);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
