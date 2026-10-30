import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/productivity/data/experience_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/productivity_session.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/ui/productivity_root.dart';

void main() {
  var sequence = 0;
  Future<ProductivityDatabase> database(String uid, {String? task}) async {
    final db = await ProductivityDatabase.open(
        uid: uid, factory: databaseFactoryMemory, path: 'root-${sequence++}');
    await ExperienceRepository(db).completeOnboarding(ExperienceOptions(
        language: 'en', timeZone: 'Asia/Dhaka', completedOnboarding: true));
    if (task != null) {
      await TaskRepository(db).createTask(
          ProductivityTask(id: 'task', workspaceId: 'personal', title: task));
    }
    return db;
  }

  Widget root(String uid, Future<ProductivityDatabase> Function() open) =>
      MaterialApp(
          home: ProductivityRoot(
              uid: uid,
              initialLanguage: 'en',
              openDatabase: open,
              detectTimeZone: () async => 'Asia/Dhaka',
              faithBuilder: (_) => const Text('Faith feature content'),
              accountBuilder: (_) =>
                  const Scaffold(body: Text('Account controls'))));

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
