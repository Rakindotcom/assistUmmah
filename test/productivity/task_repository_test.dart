import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/project.dart';
import 'package:ummah_assist/src/productivity/domain/recurrence.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';

void main() {
  var sequence = 0;
  late ProductivityDatabase db;
  late TaskRepository repository;
  final now = DateTime.utc(2026, 10, 30, 12);
  setUp(() async {
    db = await ProductivityDatabase.open(
        uid: 'alice',
        factory: databaseFactoryMemory,
        path: 'task-repository-${sequence++}');
    repository = TaskRepository(db, clock: () => now);
  });
  tearDown(() => db.close());
  ProductivityTask task(String id,
          {String workspace = 'personal',
          String? parent,
          String? project,
          List<String> dependencies = const [],
          RecurrenceRule? recurrence}) =>
      ProductivityTask(
          id: id,
          workspaceId: workspace,
          title: 'Task $id',
          parentId: parent,
          projectId: project,
          dependencies: dependencies,
          recurrence: recurrence);
  Matcher failure(String code) =>
      isA<TaskEditFailure>().having((e) => e.code, 'code', code);

  test('Bangla title limits count user-visible characters rather than code units', () async {
    final title = List.filled(250, 'কাজ').join();
    expect(title.length, greaterThan(500));
    await repository.createTask(ProductivityTask(id: 'bangla', workspaceId: 'personal', title: title));
    expect((await db.get(RecordKind.task, 'bangla'))!.fields['title'], title);
    final project = ProductivityProject(id: 'bangla-project', workspaceId: 'personal', name: List.filled(100, 'কাজ').join());
    await repository.createProject(project);
    final count = (await db.pending()).length;
    await repository.createProject(project);
    expect(await db.pending(), hasLength(count));
  });

  test('references must exist in the same workspace; failures leave no writes',
      () async {
    await repository.createProject(
        ProductivityProject(id: 'work', workspaceId: 'work', name: 'Work'));
    final count = (await db.pending()).length;
    await expectLater(
        repository.createTask(task('missing', project: 'unknown')),
        throwsA(failure('not-found')));
    await expectLater(repository.createTask(task('wrong', project: 'work')),
        throwsA(failure('different-workspace')));
    expect(await db.list(kind: RecordKind.task), isEmpty);
    expect(await db.pending(), hasLength(count));
  });

  test('field patches retain unrelated later edits and unchanged clocks',
      () async {
    await repository.createTask(task('a'));
    await repository.editTask('a', {'description': 'New notes'});
    final before = (await db.get(RecordKind.task, 'a'))!;
    await repository.editTask('a', {'title': 'Renamed'});
    final after = (await db.get(RecordKind.task, 'a'))!;
    expect(after.fields['description'], 'New notes');
    expect(after.clocks['description'], before.clocks['description']);
    final count = (await db.pending()).length;
    await repository.editTask('a', {'title': 'Renamed'});
    expect(await db.pending(), hasLength(count));
    await expectLater(repository.editTask('a', {'_deleted': true}),
        throwsA(failure('invalid-field')));
  });

  test('racing parent changes serialize and cannot create a hierarchy cycle',
      () async {
    await repository.createTask(task('a'));
    await repository.createTask(task('b'));
    final outcomes = await Future.wait([
      repository
          .editTask('a', {'parentId': 'b'})
          .then<Object>((_) => true)
          .catchError((Object e) => e),
      repository
          .editTask('b', {'parentId': 'a'})
          .then<Object>((_) => true)
          .catchError((Object e) => e),
    ]);
    expect(outcomes.whereType<bool>(), hasLength(1));
    expect(outcomes.whereType<TaskEditFailure>().single.code,
        'circular-reference');
    expect(await db.pending(), hasLength(3));
  });

  test('mixed hierarchy and dependency cycles are rejected', () async {
    await repository.createTask(task('parent'));
    await expectLater(
        repository.createTask(
            task('child', parent: 'parent', dependencies: ['parent'])),
        throwsA(failure('circular-reference')));
    await repository.createTask(task('child', parent: 'parent'));
    await repository.createTask(task('third', dependencies: ['parent']));
    await expectLater(
        repository.editTask('child', {
          'dependencies': ['third']
        }),
        throwsA(failure('circular-reference')));
    expect((await db.get(RecordKind.task, 'child'))!.fields['dependencies'],
        isEmpty);
  });

  test(
      'completion enforces dependencies and subtasks; reopening clears timestamp',
      () async {
    await repository.createTask(task('dependency'));
    await repository.createTask(task('parent', dependencies: ['dependency']));
    await repository.createTask(task('child', parent: 'parent'));
    await expectLater(repository.setStatus('parent', TaskStatus.completed),
        throwsA(failure('dependencies-open')));
    await repository.setStatus('dependency', TaskStatus.completed);
    await expectLater(repository.setStatus('parent', TaskStatus.completed),
        throwsA(failure('subtasks-open')));
    await repository.setStatus('child', TaskStatus.completed);
    await repository.setStatus('parent', TaskStatus.completed);
    expect((await db.get(RecordKind.task, 'parent'))!.fields['completedAt'],
        now.toIso8601String());
    await repository.setStatus('parent', TaskStatus.inProgress);
    expect((await db.get(RecordKind.task, 'parent'))!.fields['completedAt'],
        isNull);
  });

  test('trash cascades atomically; restoration cannot create dangling children',
      () async {
    await repository.createTask(task('parent'));
    await repository.createTask(task('child', parent: 'parent'));
    await repository.createTask(task('grandchild', parent: 'child'));
    await repository.createTask(task('outside', dependencies: ['parent']));
    await repository.trash('parent');
    expect(
        (await db.list(kind: RecordKind.task)).map((r) => r.id), ['outside']);
    await expectLater(
        repository.restore('grandchild'), throwsA(failure('in-trash')));
    await expectLater(repository.setStatus('outside', TaskStatus.completed),
        throwsA(failure('in-trash')));
    await repository.restore('parent');
    await repository.restore('child');
    await repository.restore('grandchild');
    expect(await db.list(kind: RecordKind.task), hasLength(4));
  });

  test(
      'undoing trash restores its full subtree without reverting a later deletion',
      () async {
    await repository.createTask(task('parent'));
    await repository.createTask(task('child', parent: 'parent'));
    await repository.createTask(task('grandchild', parent: 'child'));
    final receipt = await repository.trashWithReceipt('parent');
    await repository.undoTrash(receipt);
    expect(await db.list(kind: RecordKind.task), hasLength(3));
    await repository.trash('child');
    await repository.undoTrash(receipt);
    expect((await db.list(kind: RecordKind.task)).map((r) => r.id), ['parent']);
  });

  test(
      'postponement retains an overdue hard deadline and tracks repeated moves',
      () async {
    await repository.createTask(ProductivityTask(
        id: 'a',
        workspaceId: 'personal',
        title: 'Late proposal',
        deadline: now.subtract(const Duration(days: 1))));
    await repository.postpone('a', now);
    await repository.postpone('a', now.add(const Duration(days: 1)));
    final updated =
        ProductivityTask.fromRecord((await db.get(RecordKind.task, 'a'))!);
    expect(updated.postponements, 2);
    expect(updated.deadline, now.subtract(const Duration(days: 1)));
    expect(updated.scheduledPastDeadline, isTrue);
    expect(updated.inbox, isFalse);
  });

  test(
      'reading recurring occurrences is write-free; completion belongs to one day',
      () async {
    final day = CalendarDay(2026, 10, 30);
    await repository.createTask(task('repeat',
        recurrence:
            RecurrenceRule(start: day, frequency: RecurrenceFrequency.daily)));
    final pending = (await db.pending()).length;
    final occurrences =
        await repository.occurrences('personal', day, day.addDays(2));
    expect(occurrences, hasLength(3));
    expect(await db.pending(), hasLength(pending));
    await repository.setOccurrenceStatus('repeat', day, TaskStatus.completed);
    await expectLater(repository.setStatus('repeat', TaskStatus.completed),
        throwsA(failure('choose-occurrence')));
    final after = await repository.occurrences('personal', day, day.addDays(1));
    expect(after.first.status, TaskStatus.completed);
    expect(after.last.status, TaskStatus.notStarted);
    expect((await db.get(RecordKind.task, 'repeat'))!.fields['status'],
        'notStarted');
    final count = (await db.pending()).length;
    await repository.setOccurrenceStatus('repeat', day, TaskStatus.completed);
    expect(await db.pending(), hasLength(count));
  });

  test(
      'paused series preserve completed history and reject new unscheduled days',
      () async {
    final day = CalendarDay(2026, 10, 30);
    final rule =
        RecurrenceRule(start: day, frequency: RecurrenceFrequency.daily);
    await repository.createTask(task('repeat', recurrence: rule));
    await repository.setOccurrenceStatus('repeat', day, TaskStatus.completed);
    await repository.editTask('repeat', {
      'recurrence': {...rule.toJson(), 'paused': true}
    });
    final history =
        await repository.occurrences('personal', day, day.addDays(3));
    expect(history, hasLength(1));
    expect(history.single.status, TaskStatus.completed);
    await expectLater(
        repository.setOccurrenceStatus(
            'repeat', day.addDays(1), TaskStatus.completed),
        throwsA(failure('not-scheduled')));
    await repository.setOccurrenceStatus('repeat', day, TaskStatus.notStarted);
    expect((await repository.occurrences('personal', day, day)).single.status,
        TaskStatus.notStarted);
  });

  test(
      'recurring prerequisites use the same day rather than closing the series',
      () async {
    final day = CalendarDay(2026, 10, 30);
    final rule =
        RecurrenceRule(start: day, frequency: RecurrenceFrequency.daily);
    await repository.createTask(task('prepare', recurrence: rule));
    await repository.createTask(
        task('execute', dependencies: ['prepare'], recurrence: rule));
    await expectLater(
        repository.setOccurrenceStatus('execute', day, TaskStatus.completed),
        throwsA(failure('dependencies-open')));
    await repository.setOccurrenceStatus('prepare', day, TaskStatus.completed);
    await repository.setOccurrenceStatus('execute', day, TaskStatus.completed);
    await expectLater(
        repository.setOccurrenceStatus(
            'execute', day.addDays(1), TaskStatus.completed),
        throwsA(failure('dependencies-open')));
  });
}
