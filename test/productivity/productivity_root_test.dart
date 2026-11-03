import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/pages/contacts_page.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';
import 'package:ummah_assist/src/productivity/data/experience_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/productivity_session.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/ui/productivity_root.dart';
import 'package:ummah_assist/src/productivity/ui/faith_module_page.dart';
import 'package:ummah_assist/src/productivity/ui/task_editor_page.dart';

import '../support/native_ui_channels.dart';

void main() {
  var sequence = 0;
  Future<ProductivityDatabase> database(String uid,
      {String? task,
      Iterable<WorkspaceModule> modules = const [
        WorkspaceModule.personal
      ]}) async {
    final db = await ProductivityDatabase.open(
        uid: uid, factory: databaseFactoryMemory, path: 'root-${sequence++}');
    await ExperienceRepository(db).completeOnboarding(ExperienceOptions(
        language: 'en',
        timeZone: 'Asia/Dhaka',
        modules: modules,
        completedOnboarding: true));
    if (task != null) {
      await TaskRepository(db).createTask(
          ProductivityTask(id: 'task', workspaceId: 'personal', title: task));
    }
    return db;
  }

  Widget root(String uid, Future<ProductivityDatabase> Function() open,
          {bool defaultFaith = false, AppRepository? legacyRepository}) =>
      MaterialApp(
          home: ProductivityRoot(
              uid: uid,
              initialLanguage: 'en',
              openDatabase: open,
              detectTimeZone: () async => 'Asia/Dhaka',
              legacyRepository: legacyRepository ??
                  AppRepository(uid: uid, firebaseReady: false),
              faithBuilder: defaultFaith
                  ? null
                  : (_) => const Text('Faith feature content'),
              accountBuilder: (_) =>
                  const Scaffold(body: Text('Account controls'))));

  testWidgets('enabled Faith opens the default adapter in the universal root',
      (tester) async {
    configureNativeUiChannels();
    final db = (await tester.runAsync(() => database('root-faith',
        modules: [WorkspaceModule.personal, WorkspaceModule.faith])))!;
    addTearDown(() => ProductivitySession.closeAccount('root-faith'));
    await tester
        .pumpWidget(root('root-faith', () async => db, defaultFaith: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Faith'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FaithModulePage), findsOneWidget);
    expect(find.byType(PrayerPage), findsOneWidget);
    await tester.tap(find.byTooltip('Quick add task'));
    for (var i = 0;
        i < 30 && find.byType(ProductivityTaskEditorPage).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ProductivityTaskEditorPage), findsOneWidget);
    expect(
        tester
            .widget<ProductivityTaskEditorPage>(
                find.byType(ProductivityTaskEditorPage))
            .workspaceId,
        'personal');
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quick add task'));
    for (var i = 0;
        i < 30 && find.byType(ProductivityTaskEditorPage).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ProductivityTaskEditorPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => ProductivitySession.closeAccount('root-faith'));
  });

  testWidgets(
      'turning off Faith cancels legacy alerts and never schedules task alerts',
      (tester) async {
    configureNativeUiChannels();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      calls.add(call);
      return switch (call.method) {
        'initialize' ||
        'areNotificationsEnabled' ||
        'canScheduleExactNotifications' =>
          true,
        'cancel' || 'zonedSchedule' => null,
        _ => throw StateError('Unexpected notification method ${call.method}'),
      };
    });
    final uid = 'root-reminders';
    final db = (await tester.runAsync(() => database(uid,
        modules: [WorkspaceModule.personal, WorkspaceModule.faith])))!;
    addTearDown(() => ProductivitySession.closeAccount(uid));
    await tester.pumpWidget(root(uid, () async => db,
        legacyRepository: _EnabledRemindersRepository(uid)));
    await tester.pumpAndSettle();
    for (var i = 0;
        i < 30 && !calls.any((call) => call.method == 'zonedSchedule');
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final scheduledIds = calls
        .where((call) => call.method == 'zonedSchedule')
        .map((call) => (call.arguments as Map)['id'])
        .toSet();
    expect(scheduledIds, containsAll([1002, 1003]));
    expect(scheduledIds, isNot(contains(1001)));

    final beforeDisable = calls.length;
    await tester.runAsync(() => ExperienceRepository(db).updateOptions({
          'modules': ['personal']
        }));
    final saved = await tester
        .runAsync(() => ExperienceRepository(db).watchOptions().first);
    expect(saved!.faithEnabled, isFalse);
    for (var i = 0; i < 30 && find.text('Faith').evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Faith'), findsNothing);
    Set<Object?> cancelledSinceDisable() => calls
        .skip(beforeDisable)
        .where((call) => call.method == 'cancel')
        .map((call) => (call.arguments as Map)['id'])
        .toSet();
    for (var i = 0;
        i < 30 && !cancelledSinceDisable().containsAll([1001, 1002, 1003]);
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(cancelledSinceDisable(), containsAll([1001, 1002, 1003]));
    expect(
        calls
            .skip(beforeDisable)
            .where((call) => call.method == 'zonedSchedule'),
        isEmpty);
    expect(find.text('Faith'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => ProductivitySession.closeAccount(uid));
  });

  testWidgets(
      'universal root opens the saved workspace and settings without Faith enabled',
      (tester) async {
    final db = (await tester
        .runAsync(() => database('root-alice', task: 'Alice proposal')))!;
    addTearDown(() => ProductivitySession.closeAccount('root-alice'));
    await tester.pumpWidget(root('root-alice', () async => db));
    await tester.pumpAndSettle();
    expect(find.text('Add task'), findsOneWidget);
    expect(find.text('Faith'), findsNothing);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => ProductivitySession.closeAccount('root-alice'));
  });

  testWidgets('settings keeps legacy emergency contacts reachable',
      (tester) async {
    final uid = 'root-contacts';
    final db = (await tester.runAsync(() => database(uid)))!;
    addTearDown(() => ProductivitySession.closeAccount(uid));
    await tester.pumpWidget(root(uid, () async => db));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Emergency contacts'), 250,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Emergency contacts'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ContactsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => ProductivitySession.closeAccount(uid));
  });

  testWidgets(
      'changing accounts discards old UI while the replacement database opens',
      (tester) async {
    final a = (await tester.runAsync(
        () => database('root-switch-a', task: 'Private Alice task')))!;
    final b = (await tester
        .runAsync(() => database('root-switch-b', task: 'Private Bob task')))!;
    addTearDown(() => ProductivitySession.closeAccount('root-switch-a'));
    addTearDown(() => ProductivitySession.closeAccount('root-switch-b'));
    await tester.pumpWidget(root('root-switch-a', () async => a));
    await tester.pumpAndSettle();
    final gate = Completer<ProductivityDatabase>();
    await tester.pumpWidget(root('root-switch-b', () => gate.future));
    await tester.pump();
    expect(find.text('Add task'), findsNothing);
    expect(find.text('Private Alice task'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.complete(b);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Private Bob task'), 250,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Private Alice task'), findsNothing);
    expect(find.text('Private Bob task'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester
        .runAsync(() => ProductivitySession.closeAccount('root-switch-b'));
  });

  testWidgets(
      'a late database opening from an intermediate account cannot replace the latest account',
      (tester) async {
    final a = (await tester.runAsync(() => database('root-fast-a')))!;
    final b = (await tester.runAsync(
        () => database('root-fast-b', task: 'Intermediate account task')))!;
    final c = (await tester.runAsync(
        () => database('root-fast-c', task: 'Current account task')))!;
    for (final uid in ['root-fast-a', 'root-fast-b', 'root-fast-c']) {
      addTearDown(() => ProductivitySession.closeAccount(uid));
    }
    await tester.pumpWidget(root('root-fast-a', () async => a));
    await tester.pumpAndSettle();
    final gate = Completer<ProductivityDatabase>();
    await tester.pumpWidget(root('root-fast-b', () => gate.future));
    await tester.pump();
    await tester.pumpWidget(root('root-fast-c', () async => c));
    await tester.pumpAndSettle();
    gate.complete(b);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Current account task'), 250,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Intermediate account task'), findsNothing);
    expect(find.text('Current account task'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester
        .runAsync(() => ProductivitySession.closeAccount('root-fast-c'));
  });
}

class _EnabledRemindersRepository extends AppRepository {
  const _EnabledRemindersRepository(String uid)
      : super(uid: uid, firebaseReady: true);

  @override
  Future<Map<String, dynamic>?> loadSettings() async => {
        'remindersConfigured': true,
        'notifications': {'prayer': true, 'tasks': true, 'growth': true},
      };
}
