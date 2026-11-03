import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/productivity/data/experience_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/ui/task_editor_page.dart';
import 'package:ummah_assist/src/productivity/ui/universal_inbox_page.dart';

void main() {
  var sequence = 0;

  Future<(ProductivityDatabase, TaskRepository, ExperienceOptions)> fixture(
      {String language = 'en'}) async {
    final db = await ProductivityDatabase.open(
        uid: 'inbox-owner-${sequence++}',
        factory: databaseFactoryMemory,
        path: 'universal-inbox-$sequence');
    final options = ExperienceOptions(
        language: language,
        timeZone: 'Asia/Dhaka',
        modules: [
          WorkspaceModule.personal,
          WorkspaceModule.work,
          WorkspaceModule.study
        ],
        completedOnboarding: true);
    await ExperienceRepository(db).completeOnboarding(options);
    return (db, TaskRepository(db), options);
  }

  testWidgets('shows open Inbox tasks across workspaces and filters them',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (db, tasks, options) = (await tester.runAsync(fixture))!;
    addTearDown(db.close);
    await tester.runAsync(() async {
      await tasks.createTask(ProductivityTask(
          id: 'personal', workspaceId: 'personal', title: 'Personal Alpha'));
      await tasks.createTask(ProductivityTask(
          id: 'work', workspaceId: 'work', title: 'Work Beta'));
      await tasks.createTask(ProductivityTask(
          id: 'done',
          workspaceId: 'work',
          title: 'Already done',
          status: TaskStatus.completed,
          completedAt: DateTime.utc(2026, 11, 1)));
      await tasks.createTask(ProductivityTask(
          id: 'planned',
          workspaceId: 'study',
          title: 'Already planned',
          inbox: false));
    });

    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: UniversalInboxPage(repository: tasks, options: options))));
    await tester.pumpAndSettle();
    expect(find.text('Personal Alpha'), findsOneWidget);
    expect(find.text('Work Beta'), findsOneWidget);
    expect(find.text('Already done'), findsNothing);
    expect(find.text('Already planned'), findsNothing);
    expect(find.text('2 items'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Work'));
    await tester.pumpAndSettle();
    expect(find.text('Personal Alpha'), findsNothing);
    expect(find.text('Work Beta'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'missing');
    await tester.pump();
    expect(find.text('No matching tasks.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'opens the correct workspace editor and captures into the active one',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (db, tasks, options) = (await tester.runAsync(fixture))!;
    addTearDown(db.close);
    await tester.runAsync(() => tasks.createTask(ProductivityTask(
        id: 'work-task', workspaceId: 'work', title: 'Review proposal')));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: Scaffold(
            body: UniversalInboxPage(repository: tasks, options: options))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review proposal'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ProductivityTaskEditorPage>(
                find.byType(ProductivityTaskEditorPage))
            .workspaceId,
        'work');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ProductivityTaskEditorPage>(
                find.byType(ProductivityTaskEditorPage))
            .workspaceId,
        'personal');
    await tester.pageBack();
    await tester.pumpAndSettle();
    final capture = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(capture);
    await tester.tap(capture);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ProductivityTaskEditorPage>(
                find.byType(ProductivityTaskEditorPage))
            .workspaceId,
        'work');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Task name'),
        'New work inbox item');
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductivityTaskEditorPage), findsNothing);
    final workTasks = (await tester.runAsync(
        () => tasks.watchTasks('work').first))!;
    expect(workTasks.any((task) => task.title == 'New work inbox item'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
