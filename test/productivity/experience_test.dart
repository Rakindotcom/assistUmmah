import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/experience_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/ui/onboarding_page.dart';

void main() {
  var sequence = 0;
  Future<ProductivityDatabase> memory() => ProductivityDatabase.open(
      uid: 'alice',
      factory: databaseFactoryMemory,
      path: 'experience-${sequence++}');
  ExperienceOptions options(
          {Iterable<WorkspaceModule> modules = const [WorkspaceModule.personal],
          String language = 'en'}) =>
      ExperienceOptions(
          language: language,
          timeZone: 'Asia/Dhaka',
          modules: modules,
          completedOnboarding: true);

  test(
      'workspace setup commits all choices atomically and repeated submits are harmless',
      () async {
    final db = await memory();
    addTearDown(db.close);
    final repository = ExperienceRepository(db);
    await repository.completeOnboarding(
        options(modules: [WorkspaceModule.personal, WorkspaceModule.work]));
    expect(await db.list(kind: RecordKind.workspace), hasLength(3));
    final original = await repository.watchOptions().first;
    expect(original!.faithEnabled, isFalse);
    expect(original.language, 'en');
    final count = (await db.pending()).length;
    await repository.completeOnboarding(options(language: 'bn'));
    expect((await repository.watchOptions().first)!.language, 'en');
    expect(await db.pending(), hasLength(count));
  });

  test('disabling Faith preserves its workspace and all existing records',
      () async {
    final db = await memory();
    addTearDown(db.close);
    final repository = ExperienceRepository(db);
    await repository.completeOnboarding(
        options(modules: [WorkspaceModule.personal, WorkspaceModule.faith]));
    await db.mutate(
        kind: RecordKind.note,
        id: 'faith-note',
        workspaceId: 'faith',
        patch: {'body': 'Kept'});
    await repository.updateOptions({
      'modules': ['personal']
    });
    expect((await repository.watchOptions().first)!.faithEnabled, isFalse);
    expect((await db.get(RecordKind.workspace, 'faith'))!.deleted, isFalse);
    expect(
        (await db.get(RecordKind.note, 'faith-note'))!.fields['body'], 'Kept');
  });

  test('invalid settings are rejected before workspace or preference writes',
      () async {
    final db = await memory();
    addTearDown(db.close);
    final repository = ExperienceRepository(db);
    await repository.completeOnboarding(options());
    final count = (await db.pending()).length;
    await expectLater(
        repository.updateOptions({
          'modules': ['work']
        }),
        throwsFormatException);
    await expectLater(
        repository.updateOptions({'weekStartsOn': 8}), throwsFormatException);
    await expectLater(repository.updateOptions({'completedOnboarding': false}),
        throwsArgumentError);
    expect(await db.pending(), hasLength(count));
    expect(await db.get(RecordKind.workspace, 'work'), isNull);
  });

  testWidgets(
      'English setup saves a non-religious workspace with Faith off by default',
      (tester) async {
    ExperienceOptions? saved;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalization.supportedLocales,
        localizationsDelegates: AppLocalization.delegates,
        home: ProductivityOnboardingPage(
            timeZone: 'America/New_York',
            initialLanguage: 'en',
            onComplete: (options) async => saved = options)));
    await tester.tap(find.text('Work'));
    await tester.scrollUntilVisible(find.text('Start my workspace'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Start my workspace'));
    await tester.pumpAndSettle();
    expect(saved!.language, 'en');
    expect(saved!.modules, {WorkspaceModule.personal, WorkspaceModule.work});
    expect(saved!.faithEnabled, isFalse);
    expect(saved!.timeZone, 'America/New_York');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Bangla setup keeps its draft after failure on a narrow large-text screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('bn'),
        supportedLocales: AppLocalization.supportedLocales,
        localizationsDelegates: AppLocalization.delegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!),
        home: ProductivityOnboardingPage(
            timeZone: 'Asia/Dhaka',
            onComplete: (_) async {
              attempts++;
              if (attempts == 1) throw StateError('Synthetic storage error');
            })));
    await tester.scrollUntilVisible(find.text('শুরু করুন'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('শুরু করুন'));
    await tester.pumpAndSettle();
    expect(find.text('সংরক্ষণ হয়নি। আপনার লেখা রাখা আছে; আবার চেষ্টা করুন।'),
        findsOneWidget);
    await tester.scrollUntilVisible(find.text('শুরু করুন'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('শুরু করুন'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
