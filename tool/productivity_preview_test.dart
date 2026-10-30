// Development fixture only. No Firebase connection or real account data.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  testWidgets('render the connected workspace on a phone in both languages',
      (tester) async {
    final shadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = shadows);
    for (final font in [
      ('AnekBangla', 'assets/fonts/AnekBangla.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf')
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final language in ['bn', 'en']) {
      final uid = 'preview-$language';
      final db = (await tester.runAsync(() async {
        final db = await ProductivityDatabase.open(
            uid: uid, factory: databaseFactoryMemory, path: uid);
        await ExperienceRepository(db).completeOnboarding(ExperienceOptions(
            language: language,
            timeZone: 'Asia/Dhaka',
            modules: [WorkspaceModule.personal, WorkspaceModule.work],
            completedOnboarding: true));
        final tasks = TaskRepository(db);
        await tasks.createTask(ProductivityTask(
            id: 'proposal',
            workspaceId: 'personal',
            title: language == 'bn'
                ? 'প্রকল্পের প্রস্তাবনা তৈরি'
                : 'Prepare the project proposal',
            priority: TaskPriority.high,
            estimatedMinutes: 45,
            tags: [language == 'bn' ? 'লেখা' : 'writing']));
        await tasks.createTask(ProductivityTask(
            id: 'learn',
            workspaceId: 'personal',
            title: language == 'bn'
                ? 'পড়ার জন্য বইয়ের তালিকা'
                : 'Books I want to read',
            priority: TaskPriority.normal,
            estimatedMinutes: 15));
        return db;
      }))!;
      await tester.pumpWidget(RepaintBoundary(
          key: const Key('workspace-preview'),
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: ProductivityRoot(
                  uid: uid,
                  openDatabase: () async => db,
                  detectTimeZone: () async => 'Asia/Dhaka',
                  initialLanguage: language,
                  faithBuilder: (_) => const SizedBox.shrink(),
                  accountBuilder: (_) => const SizedBox.shrink()))));
      await tester.pumpAndSettle();
      await tester.runAsync(() => precacheImage(
          const ResizeImage(AssetImage('assets/brand/app_icon.png'), width: 34),
          tester.element(find.byType(ProductivityRoot))));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('workspace-preview')));
      await tester.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await Directory('.local/previews').create(recursive: true);
        await File('.local/previews/productivity-$language-phone.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => ProductivitySession.closeAccount(uid));
    }
    debugDisableShadows = shadows;
  });
}
