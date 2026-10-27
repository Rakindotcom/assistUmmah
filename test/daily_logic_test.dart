import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/daily_logic.dart';
import 'package:ummah_assist/src/date_helpers.dart';
import 'package:ummah_assist/src/home_shell.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';

void main() {
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

  test('daily recurrence creates one fresh task per opened day', () {
    final today = <String, List<TaskItem>>{'mustDo': [], 'goodToDo': []};
    final missed = <String, List<TaskItem>>{'mustDo': [], 'goodToDo': []};
    final recurring = [
      const RecurringTask(
        id: 'routine',
        text: 'Read',
        section: 'mustDo',
        repeat: TaskRepeat.daily,
        startDate: '2026-10-24',
      ),
    ];

    expect(materializeRecurringTasks(today, recurring, '2026-10-24'), isTrue);
    expect(materializeRecurringTasks(today, recurring, '2026-10-24'), isFalse);
    today['mustDo']![0] = today['mustDo']!.single.copyWith(completed: true);
    expect(rollOverTaskBuckets(today, missed, '2026-10-25'), isTrue);
    expect(materializeRecurringTasks(today, recurring, '2026-10-25'), isTrue);
    expect(today['mustDo']!.single.completed, isFalse);
    expect(today['mustDo']!.single.id, 'routine:2026-10-25');
    expect(missed['mustDo'], isEmpty);
  });

  test('weekly recurrence uses its start weekday and respects start date', () {
    final today = <String, List<TaskItem>>{'mustDo': [], 'goodToDo': []};
    final recurring = [
      const RecurringTask(
        id: 'friday',
        text: 'Weekly review',
        section: 'goodToDo',
        repeat: TaskRepeat.weekly,
        startDate: '2026-10-23',
      ),
    ];

    expect(materializeRecurringTasks(today, recurring, '2026-10-22'), isFalse);
    expect(materializeRecurringTasks(today, recurring, '2026-10-24'), isFalse);
    expect(materializeRecurringTasks(today, recurring, '2026-10-30'), isTrue);
    expect(today['goodToDo']!.single.recurrenceId, 'friday');
  });

  test('scheduled task becomes due once and preserves its original due date',
      () {
    final today = <String, List<TaskItem>>{'mustDo': [], 'goodToDo': []};
    final scheduled = [
      const TaskItem(
        id: 'planned',
        text: 'Call family',
        completed: false,
        createdAt: '',
        dateCreated: '2026-10-24',
        dueDate: '2026-10-28',
        section: 'goodToDo',
      ),
    ];
    expect(materializeScheduledTasks(today, scheduled, '2026-10-27'), isFalse);
    expect(materializeScheduledTasks(today, scheduled, '2026-10-29'), isTrue);
    expect(materializeScheduledTasks(today, scheduled, '2026-10-29'), isFalse);
    expect(scheduled, isEmpty);
    expect(today['goodToDo']!.single.dateCreated, '2026-10-29');
    expect(today['goodToDo']!.single.dueDate, '2026-10-28');
  });

  test('rescheduled recurring occurrence is not regenerated on its old day',
      () {
    final today = <String, List<TaskItem>>{'mustDo': [], 'goodToDo': []};
    final scheduled = [
      const TaskItem(
        id: 'routine:2026-10-25',
        text: 'Read',
        completed: false,
        createdAt: '',
        dateCreated: '2026-10-25',
        dueDate: '2026-10-28',
        section: 'mustDo',
        recurrenceId: 'routine',
      ),
    ];
    final recurring = [
      const RecurringTask(
        id: 'routine',
        text: 'Read',
        section: 'mustDo',
        repeat: TaskRepeat.daily,
        startDate: '2026-10-25',
      ),
    ];
    expect(
      materializeRecurringTasks(today, recurring, '2026-10-25',
          scheduled: scheduled),
      isFalse,
    );
    expect(today['mustDo'], isEmpty);
    expect(materializeRecurringTasks(today, recurring, '2026-10-26'), isTrue);
  });

  test('postponed recurrence and the regular occurrence can share a day', () {
    final today = <String, List<TaskItem>>{
      'mustDo': [
        const TaskItem(
          id: 'routine:2026-10-25',
          text: 'Read',
          completed: false,
          createdAt: '',
          dateCreated: '2026-10-28',
          recurrenceId: 'routine',
          dueDate: '2026-10-28',
          section: 'mustDo',
        ),
      ],
      'goodToDo': [],
    };
    final recurring = [
      const RecurringTask(
        id: 'routine',
        text: 'Read',
        section: 'mustDo',
        repeat: TaskRepeat.daily,
        startDate: '2026-10-25',
      ),
    ];
    expect(materializeRecurringTasks(today, recurring, '2026-10-28'), isTrue);
    expect(today['mustDo']!.map((task) => task.id),
        ['routine:2026-10-25', 'routine:2026-10-28']);
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
