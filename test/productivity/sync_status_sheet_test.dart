import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/calendar_event_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/productivity_session.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_event.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/ui/sync_status_sheet.dart';
import 'package:ummah_assist/src/productivity/ui/calendar_page.dart';
import 'package:ummah_assist/src/productivity/ui/task_editor_page.dart';

void main() {
  testWidgets('failed event can be corrected and resubmitted on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const uid = 'event-sheet-test';
    final db = (await tester.runAsync(() async {
      final result = await ProductivityDatabase.open(
          uid: uid, factory: databaseFactoryMemory, path: 'event-sheet-test');
      await CalendarEventRepository(result).create(CalendarEvent(
          id: 'meeting',
          workspaceId: 'personal',
          title: 'Meeting',
          start: DateTime.utc(2026, 11, 5, 9),
          end: DateTime.utc(2026, 11, 5, 10),
          timeZone: 'Asia/Dhaka'));
      final operation = (await result.pending()).single;
      await result.recordFailure(operation, 'invalid-calendar-event',
          permanent: true);
      return result;
    }))!;
    final session = (await tester.runAsync(() =>
        ProductivitySession.open(uid: uid, openDatabase: () async => db)))!;
    addTearDown(() => ProductivitySession.closeAccount(uid));
    final options = ExperienceOptions(language: 'en', timeZone: 'Asia/Dhaka');
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => ProductivitySyncStatusSheet(
                            session: session,
                            repository: TaskRepository(db),
                            options: options)),
                    child: const Text('Open sync status'))))));
    await tester.tap(find.text('Open sync status'));
    await tester.pumpAndSettle();
    expect(find.text('Calendar event needs review'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review event'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarEventEditorPage), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'), 'Updated meeting');
    tester.testTextInput.hide();
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    expect(find.text('Send reviewed event?'), findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    final pending = await tester.runAsync(db.pending);
    expect(pending, hasLength(1));
    expect(pending!.single.patch['title'], 'Updated meeting');
    expect((await tester.runAsync(db.attention))!, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => ProductivitySession.closeAccount(uid));
  });

  testWidgets('same-field conflict shows both values and retries reviewed edit',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const uid = 'field-sheet-test';
    final db = (await tester.runAsync(() async {
      final result = await ProductivityDatabase.open(
          uid: uid, factory: databaseFactoryMemory, path: 'field-sheet-test');
      final tasks = TaskRepository(result);
      final created = await tasks.createTask(ProductivityTask(
          id: 'proposal', workspaceId: 'personal', title: 'Original'));
      final create = (await result.pending()).single;
      final canonical = WorkspaceRecord(
          ownerId: uid,
          kind: RecordKind.task,
          id: created.id,
          fields: created.toFields()..addAll({'_deleted': false}),
          clocks: (await result.get(RecordKind.task, created.id))!.clocks,
          revision: 1,
          modifiedAtMillis: 1);
      await result.acknowledge(create, canonical);
      await tasks.editTask('proposal', {'title': 'My proposal'});
      final edit = (await result.pending()).single;
      final cloud = WorkspaceRecord(
          ownerId: uid,
          kind: RecordKind.task,
          id: created.id,
          fields: {...canonical.fields, 'title': 'Cloud proposal'},
          clocks: {
            ...canonical.clocks,
            'title': VersionStamp(25, 'cloud_device')
          },
          revision: 2,
          modifiedAtMillis: 2);
      await result.acknowledge(edit, cloud, rejectedFields: ['title']);
      return result;
    }))!;
    final session = (await tester.runAsync(() =>
        ProductivitySession.open(uid: uid, openDatabase: () async => db)))!;
    addTearDown(() => ProductivitySession.closeAccount(uid));
    final options = ExperienceOptions(
        language: 'bn', timeZone: 'Asia/Dhaka', completedOnboarding: true);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('bn'),
        supportedLocales: AppLocalization.supportedLocales,
        localizationsDelegates: AppLocalization.delegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => ProductivitySyncStatusSheet(
                            session: session,
                            repository: TaskRepository(db),
                            options: options)),
                    child: const Text('Open sync status'))))));
    await tester.tap(find.text('Open sync status'));
    await tester.pumpAndSettle();
    expect(find.text('ডিভাইসগুলোর তথ্য ভিন্ন'), findsOneWidget);
    expect(find.text('০টি পরিবর্তন অপেক্ষায় · ১টি পর্যালোচনা দরকার'),
        findsOneWidget);
    await tester.ensureVisible(find.text('তথ্য পর্যালোচনা করুন'));
    await tester.tap(find.text('তথ্য পর্যালোচনা করুন'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('My proposal')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Cloud proposal')),
        findsOneWidget);
    await tester.tap(find.text('আমারটি রাখুন'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(db.fieldConflicts), isEmpty);
    final pending = await tester.runAsync(db.pending);
    expect(pending!.single.patch['title'], 'My proposal');
    expect(find.text('১টি পরিবর্তন অপেক্ষায় · ০টি পর্যালোচনা দরকার'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => ProductivitySession.closeAccount(uid));
  });

  testWidgets(
      'a sync conflict is visible and opens the task for review on phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(() async {
      final result = await ProductivityDatabase.open(
          uid: 'sync-sheet-test',
          factory: databaseFactoryMemory,
          path: 'sync-sheet-test');
      final tasks = TaskRepository(result);
      await tasks.createTask(ProductivityTask(
          id: 'proposal', workspaceId: 'personal', title: 'My proposal'));
      final operation = (await result.pending()).single;
      await result.recordFailure(operation, 'circular-reference',
          permanent: true);
      return result;
    }))!;
    final session = (await tester.runAsync(() => ProductivitySession.open(
        uid: 'sync-sheet-test', openDatabase: () async => db)))!;
    addTearDown(() => ProductivitySession.closeAccount('sync-sheet-test'));
    final options = ExperienceOptions(
        language: 'bn', timeZone: 'Asia/Dhaka', completedOnboarding: true);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('bn'),
        supportedLocales: AppLocalization.supportedLocales,
        localizationsDelegates: AppLocalization.delegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => ProductivitySyncStatusSheet(
                            session: session,
                            repository: TaskRepository(db),
                            options: options)),
                    child: const Text('Open sync status'))))));
    await tester.tap(find.text('Open sync status'));
    await tester.pumpAndSettle();
    expect(find.text('সিঙ্কের অবস্থা'), findsOneWidget);
    expect(find.text('কাজটি পর্যালোচনা দরকার'), findsOneWidget);
    expect(find.text('১টি পরিবর্তন অপেক্ষায় · ১টি পর্যালোচনা দরকার'),
        findsOneWidget);
    await tester.ensureVisible(find.text('কাজ পর্যালোচনা করুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('কাজ পর্যালোচনা করুন'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductivityTaskEditorPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester
        .runAsync(() => ProductivitySession.closeAccount('sync-sheet-test'));
  });
}
