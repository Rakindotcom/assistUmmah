import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/productivity_session.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/ui/sync_status_sheet.dart';
import 'package:ummah_assist/src/productivity/ui/task_editor_page.dart';

void main() {
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
