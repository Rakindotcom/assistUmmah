import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/domain/project.dart';
import 'package:ummah_assist/src/productivity/ui/task_editor_page.dart';
import 'package:ummah_assist/src/productivity/ui/task_workspace_page.dart';

void main() {
  var sequence = 0;
  late ProductivityDatabase db;
  late TaskRepository repository;
  setUp(() async {
    db = await ProductivityDatabase.open(
        uid: 'alice',
        factory: databaseFactoryMemory,
        path: 'workspace-ui-${sequence++}');
    repository = TaskRepository(db);
  });
  tearDown(() => db.close());
  ExperienceOptions options(String language) => ExperienceOptions(
      language: language, timeZone: 'Asia/Dhaka', completedOnboarding: true);
  Widget app(Widget child, {String language = 'en', double scale = 1}) =>
      MaterialApp(
          theme: AppTheme.light,
          locale: Locale(language),
          supportedLocales: AppLocalization.supportedLocales,
          localizationsDelegates: AppLocalization.delegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(body: child));
  Future<void> scrollTo(WidgetTester tester, Finder target,
      {double delta = 250}) async {
    await tester.scrollUntilVisible(target, delta,
        scrollable: find.byType(Scrollable).first);
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  testWidgets('capture and complete a task through the real offline repository',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(TaskWorkspacePage(
        repository: repository,
        options: options('en'),
        workspaceId: 'personal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Task name'), 'Prepare proposal');
    tester.testTextInput.hide();
    await scrollTo(tester, find.text('Save task'));
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductivityTaskEditorPage), findsNothing);
    final tasks =
        (await tester.runAsync(() => db.list(kind: RecordKind.task)))!;
    expect(tasks, hasLength(1));
    expect(tasks.single.fields['title'], 'Prepare proposal');
    expect((await tester.runAsync(db.pending))!.single.kind, RecordKind.task);
    await scrollTo(tester, find.text('Prepare proposal'));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(
        (await tester.runAsync(() => db.get(RecordKind.task, tasks.single.id)))!
            .fields['status'],
        'completed');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a save failure keeps the draft and retries one stable task identity',
      (tester) async {
    final failing = _FailsOnce(db);
    await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ProductivityTaskEditorPage(
                    repository: failing,
                    workspaceId: 'personal',
                    options: options('en')))),
            child: const Text('Open editor')))));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Task name'), 'Keep my draft');
    tester.testTextInput.hide();
    await scrollTo(tester, find.text('Save task'));
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save. Your draft is kept; try again.'),
        findsOneWidget);
    await scrollTo(tester, find.text('Save task'));
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();
    expect(failing.identities.toSet(), hasLength(1));
    expect(
        (await tester.runAsync(() => db.list(kind: RecordKind.task)))!
            .single
            .fields['title'],
        'Keep my draft');
    expect(await tester.runAsync(db.pending), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Bangla editor accepts Bangla numeric input on a narrow large-text screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(
        Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => ProductivityTaskEditorPage(
                            repository: repository,
                            workspaceId: 'personal',
                            options: options('bn')))),
                child: const Text('Open editor'))),
        language: 'bn',
        scale: 1.6));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'কাজের নাম'), 'পড়াশোনা');
    tester.testTextInput.hide();
    await scrollTo(
        tester, find.widgetWithText(TextFormField, 'সময়ের অনুমান (মিনিট)'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'সময়ের অনুমান (মিনিট)'), '৪৫');
    tester.testTextInput.hide();
    await scrollTo(tester, find.text('কাজ সংরক্ষণ করুন'));
    await tester.tap(find.text('কাজ সংরক্ষণ করুন'));
    await tester.pumpAndSettle();
    final task = ProductivityTask.fromRecord(
        (await tester.runAsync(() => db.list(kind: RecordKind.task)))!.single);
    expect(task.title, 'পড়াশোনা');
    expect(task.estimatedMinutes, 45);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project save failures retain the draft and retry the same project identity', (tester) async {
    final failing = _ProjectFailsOnce(db);
    await tester.pumpWidget(app(TaskWorkspacePage(repository: failing,
        options: options('en'), workspaceId: 'personal')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Project'));
    await tester.tap(find.text('Project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'Retain my project');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save. Your draft is kept; try again.'), findsOneWidget);
    expect(find.text('Retain my project'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('New project'), findsNothing);
    expect(failing.identities.toSet(), hasLength(1));
    expect((await tester.runAsync(() => db.list(kind: RecordKind.project)))!.single.fields['name'], 'Retain my project');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FailsOnce extends TaskRepository {
  _FailsOnce(super.database);
  final identities = <String>[];
  @override
  Future<ProductivityTask> createTask(ProductivityTask task) async {
    identities.add(task.id);
    if (identities.length == 1) throw StateError('Synthetic write failure');
    return super.createTask(task);
  }
}

class _ProjectFailsOnce extends TaskRepository {
  _ProjectFailsOnce(super.database);
  final identities = <String>[];
  @override
  Future<ProductivityProject> createProject(ProductivityProject project) async {
    identities.add(project.id);
    if (identities.length == 1) throw StateError('Synthetic project storage error');
    return super.createProject(project);
  }
}
