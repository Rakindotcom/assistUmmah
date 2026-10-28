import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/daily_logic.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/tasks_page.dart';
import 'package:ummah_assist/src/pages/task_entry_dialog.dart';

void main() {
  testWidgets(
      'failed save keeps task draft, recurrence and retry in the dialog',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _TransientTaskRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: TasksPage(repository: repository, day: DateTime(2026, 10, 25))),
    ));
    await tester.pump();
    await tester.tap(find.text('কাজ যোগ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Read Quran');
    await tester.tap(find.text('একবার'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('প্রতিদিন').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('যোগ করুন'));
    await tester.pump();
    expect(repository.calls, 1);
    expect(find.byType(TaskEntryDialog), findsOneWidget);
    expect(find.text('সংরক্ষণ হচ্ছে…'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'সংরক্ষণ হচ্ছে…'))
            .onPressed,
        isNull);
    repository.firstAttempt.completeError(StateError('network'));
    await tester.pumpAndSettle();
    expect(
        find.text('কাজ সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Read Quran');
    expect(find.text('প্রতিদিন'), findsOneWidget);
    expect(repository.today['mustDo'], isEmpty);

    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(repository.today['mustDo'], hasLength(1));
    expect(repository.recurring, hasLength(1));
    expect(find.byType(TaskEntryDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry does not duplicate a task after an ambiguous commit',
      (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CommittedThenFailedRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: TasksPage(repository: repository, day: DateTime(2026, 10, 25))),
    ));
    await tester.pump();
    await tester.tap(find.text('কাজ যোগ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Read Quran');
    await tester.tap(find.text('একবার'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('প্রতিদিন').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();
    expect(
        find.text('কাজ সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'), findsOneWidget);
    expect(repository.today['mustDo'], hasLength(1));
    expect(repository.recurring, hasLength(1));

    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(repository.today['mustDo'], hasLength(1));
    expect(repository.recurring, hasLength(1));
    expect(find.byType(TaskEntryDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily task is created and removing it cancels the series', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _TaskRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TasksPage(repository: repository, day: DateTime(2026, 10, 25)),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('কাজ যোগ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Read Quran');
    await tester.tap(find.text('একবার'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('প্রতিদিন').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();

    expect(find.text('Read Quran'), findsOneWidget);
    expect(find.text('প্রতিদিন'), findsOneWidget);
    expect(repository.recurring, hasLength(1));
    expect(repository.today['mustDo']!.single.recurrenceId,
        repository.recurring.single.id);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('পুনরাবৃত্ত কাজ মুছবেন?'), findsOneWidget);
    await tester.tap(find.text('মুছুন'));
    await tester.pumpAndSettle();
    expect(repository.recurring, isEmpty);
    expect(repository.today['mustDo'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('future one-off task appears in scheduled tab and can move', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _TaskRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TasksPage(repository: repository, day: DateTime(2026, 10, 25)),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('কাজ যোগ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Call family');
    await tester.tap(find.text('তারিখ: ২৫/১০/২০২৬'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('28').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();

    expect(repository.today['mustDo'], isEmpty);
    expect(repository.scheduled.single.dueDate, '2026-10-28');
    await tester.tap(find.text('নির্ধারিত কাজ'));
    await tester.pumpAndSettle();
    expect(find.text('Call family'), findsOneWidget);
    expect(find.text('তারিখ: ২৮/১০/২০২৬'), findsOneWidget);

    await tester.tap(find.byTooltip('তারিখ পরিবর্তন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('29').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(repository.scheduled.single.dueDate, '2026-10-29');
    expect(find.text('তারিখ: ২৯/১০/২০২৬'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scheduled tasks remain usable on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _TaskRepository();
    repository.scheduled.add(const TaskItem(
      id: 'future',
      text: 'Call family and discuss the weekly schedule',
      completed: false,
      createdAt: '',
      dateCreated: '2026-10-25',
      dueDate: '2026-10-28',
      section: 'mustDo',
    ));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TasksPage(repository: repository, day: DateTime(2026, 10, 25)),
      ),
    ));
    await tester.pump();
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(find.text('নির্ধারিত কাজ').hitTestable(), findsOneWidget);
    await tester.tap(find.text('নির্ধারিত কাজ'));
    await tester.pump();
    expect(find.text('Call family and discuss the weekly schedule'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TaskRepository extends AppRepository {
  _TaskRepository() : super(uid: 'test-user', firebaseReady: false);

  final Map<String, List<TaskItem>> today = {'mustDo': [], 'goodToDo': []};
  final Map<String, List<TaskItem>> missed = {'mustDo': [], 'goodToDo': []};
  final List<RecurringTask> recurring = [];
  final List<TaskItem> scheduled = [];

  @override
  bool get canSync => true;

  @override
  Future<Map<String, dynamic>?> loadTasksForDate(String date) async =>
      _snapshot();

  @override
  Future<Map<String, dynamic>?> changeTasks({
    required String date,
    required void Function(
      Map<String, List<TaskItem>> today,
      Map<String, List<TaskItem>> missed,
      List<RecurringTask> recurring,
      List<TaskItem> scheduled,
    ) apply,
  }) async {
    apply(today, missed, recurring, scheduled);
    materializeScheduledTasks(today, scheduled, date);
    materializeRecurringTasks(today, recurring, date, scheduled: scheduled);
    return _snapshot();
  }

  Map<String, dynamic> _snapshot() => {
        'todayTasks': {
          for (final section in ['mustDo', 'goodToDo'])
            section: today[section]!.map((task) => task.toMap()).toList(),
        },
        'missedTasks': {
          for (final section in ['mustDo', 'goodToDo'])
            section: missed[section]!.map((task) => task.toMap()).toList(),
        },
        'recurringTasks': recurring.map((task) => task.toMap()).toList(),
        'scheduledTasks': scheduled.map((task) => task.toMap()).toList(),
      };
}

class _TransientTaskRepository extends _TaskRepository {
  final firstAttempt = Completer<void>();
  int calls = 0;

  @override
  Future<Map<String, dynamic>?> changeTasks({
    required String date,
    required void Function(
      Map<String, List<TaskItem>> today,
      Map<String, List<TaskItem>> missed,
      List<RecurringTask> recurring,
      List<TaskItem> scheduled,
    ) apply,
  }) async {
    calls++;
    if (calls == 1) {
      await firstAttempt.future;
    }
    return super.changeTasks(date: date, apply: apply);
  }
}

class _CommittedThenFailedRepository extends _TaskRepository {
  int calls = 0;

  @override
  Future<Map<String, dynamic>?> changeTasks({
    required String date,
    required void Function(
      Map<String, List<TaskItem>> today,
      Map<String, List<TaskItem>> missed,
      List<RecurringTask> recurring,
      List<TaskItem> scheduled,
    ) apply,
  }) async {
    calls++;
    final result = await super.changeTasks(date: date, apply: apply);
    if (calls == 1) throw StateError('response lost after commit');
    return result;
  }
}
