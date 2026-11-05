import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/calendar_event_repository.dart';
import 'package:ummah_assist/src/productivity/data/daily_planning_repository.dart';
import 'package:ummah_assist/src/productivity/data/experience_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_event.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/recurrence.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';

void main() {
  var sequence = 0;
  late ProductivityDatabase db;
  late DailyPlanningRepository planner;
  late TaskRepository tasks;
  late DateTime now;
  final day = CalendarDay(2026, 11, 9);
  Matcher failure(String code) =>
      isA<DailyPlanningFailure>().having((e) => e.code, 'code', code);

  setUp(() async {
    now = DateTime.utc(2026, 11, 9, 8);
    db = await ProductivityDatabase.open(
        uid: 'planner-owner',
        factory: databaseFactoryMemory,
        path: 'planner-${sequence++}');
    planner = DailyPlanningRepository(db, clock: () => now);
    tasks = TaskRepository(db);
    await ExperienceRepository(db).completeOnboarding(ExperienceOptions(
        language: 'en', timeZone: 'UTC', completedOnboarding: true));
    await tasks.createTask(ProductivityTask(
        id: 'urgent',
        workspaceId: 'personal',
        title: 'Urgent report',
        scheduledDay: day,
        inbox: false,
        priority: TaskPriority.urgent,
        estimatedMinutes: 90,
        deadline: DateTime.utc(2026, 11, 9, 12)));
    await tasks.createTask(ProductivityTask(
        id: 'normal',
        workspaceId: 'personal',
        title: 'Read chapter',
        scheduledDay: day,
        inbox: false,
        estimatedMinutes: 60));
  });
  tearDown(() => db.close());

  test('review does not write; applying schedules all tasks through the outbox',
      () async {
    await CalendarEventRepository(db).create(CalendarEvent(
        id: 'meeting',
        workspaceId: 'personal',
        title: 'Meeting',
        start: DateTime.utc(2026, 11, 9, 9),
        end: DateTime.utc(2026, 11, 9, 10),
        timeZone: 'UTC'));
    final before = (await db.queued()).length;
    final review = await planner.preview(day);
    expect(await db.queued(), hasLength(before));
    expect(review.plan.placements.map((p) => p.taskId), ['urgent', 'normal']);
    expect(review.plan.placements.first.start, DateTime.utc(2026, 11, 9, 10));
    await planner.apply(review);
    expect(await db.queued(), hasLength(before + 2));
    final saved = (await db.get(RecordKind.task, 'urgent'))!;
    expect(saved.fields['scheduledAt'], '2026-11-09T10:00:00.000Z');
    expect(saved.fields['scheduledDay'], isNull);
    expect(saved.fields['deadline'], '2026-11-09T12:00:00.000Z');
    expect(saved.fields['inbox'], isFalse);
  });

  for (final change in ['task', 'event', 'preferences']) {
    test('$change changes require a fresh review and write no stale placements',
        () async {
      final review = await planner.preview(day);
      switch (change) {
        case 'task':
          await tasks.editTask('normal', {'description': 'Changed elsewhere'});
        case 'event':
          await CalendarEventRepository(db).create(CalendarEvent(
              id: 'new-event',
              workspaceId: 'personal',
              title: 'New meeting',
              start: DateTime.utc(2026, 11, 9, 9),
              end: DateTime.utc(2026, 11, 9, 10),
              timeZone: 'UTC'));
        case 'preferences':
          await ExperienceRepository(db)
              .updateOptions({'dailyCapacityMinutes': 90});
      }
      final before = (await db.queued()).length;
      await expectLater(planner.apply(review), throwsA(failure('stale-plan')));
      expect(await db.queued(), hasLength(before));
      expect((await db.get(RecordKind.task, 'urgent'))!.fields['scheduledAt'],
          isNull);
    });
  }

  test('expired review and already-passed slot require rebuilding', () async {
    final review = await planner.preview(day);
    now = now.add(const Duration(minutes: 16));
    await expectLater(planner.apply(review), throwsA(failure('expired-plan')));
    now = DateTime.utc(2026, 11, 9, 9);
    final fresh = await planner.preview(day);
    expect(fresh.plan.placements.first.start, DateTime.utc(2026, 11, 9, 9, 5));
    now = now.add(const Duration(minutes: 6));
    await expectLater(planner.apply(fresh), throwsA(failure('expired-plan')));
  });

  test('two simultaneous applies cannot schedule the same review twice',
      () async {
    final first = await planner.preview(day);
    final second = await planner.preview(day);
    final before = (await db.queued()).length;
    final results = await Future.wait([
      for (final review in [first, second])
        planner
            .apply(review)
            .then<Object>((_) => true)
            .catchError((Object error) => error),
    ]);
    expect(results.whereType<bool>(), hasLength(1));
    expect(results.whereType<DailyPlanningFailure>().single.code, 'stale-plan');
    expect(await db.queued(), hasLength(before + 2));
  });

  test('a validation failure cannot save a partial plan', () async {
    final invalid = ProductivityTask(
        id: 'invalid',
        workspaceId: 'personal',
        title: 'Broken project link',
        projectId: 'missing',
        estimatedMinutes: 15,
        scheduledDay: day,
        inbox: false,
        priority: TaskPriority.low);
    await db.mutate(
        kind: RecordKind.task,
        id: invalid.id,
        workspaceId: invalid.workspaceId,
        patch: invalid.toFields());
    final review = await planner.preview(day);
    expect(review.plan.placements, hasLength(3));
    final before = (await db.queued()).length;
    await expectLater(planner.apply(review), throwsA(isA<TaskEditFailure>()));
    expect(await db.queued(), hasLength(before));
    for (final id in ['urgent', 'normal', 'invalid']) {
      expect(
          (await db.get(RecordKind.task, id))!.fields['scheduledAt'], isNull);
    }
  });

  test('review cannot cross account or deletion boundary', () async {
    final review = await planner.preview(day);
    final other = await ProductivityDatabase.open(
        uid: 'different-owner',
        factory: databaseFactoryMemory,
        path: 'planner-other-${sequence++}');
    addTearDown(other.close);
    await expectLater(DailyPlanningRepository(other).apply(review),
        throwsA(failure('different-account')));
    await db.freeze();
    final before = (await db.queued()).length;
    await expectLater(planner.apply(review), throwsStateError);
    expect(await db.queued(), hasLength(before));
  });

  test(
      'a completed recurring occurrence releases time without ending its series',
      () async {
    await tasks.createTask(ProductivityTask(
        id: 'routine',
        workspaceId: 'personal',
        title: 'Morning routine',
        inbox: false,
        recurrence:
            RecurrenceRule(start: day, frequency: RecurrenceFrequency.daily)));
    expect((await planner.preview(day)).plan.placements, isEmpty);
    await tasks.setOccurrenceStatus('routine', day, TaskStatus.completed);
    final reviewed = await planner.preview(day);
    expect(reviewed.plan.placements, hasLength(2));
    expect(reviewed.plan.fixedTaskIds, isNot(contains('routine')));
    expect((await db.get(RecordKind.task, 'routine'))!.fields['status'],
        TaskStatus.notStarted.name);
  });
}
