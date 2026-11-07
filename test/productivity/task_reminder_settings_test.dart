import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/notifications/task_reminder_controller.dart';
import 'package:ummah_assist/src/productivity/ui/experience_strings.dart';
import 'package:ummah_assist/src/productivity/ui/task_reminder_settings.dart';

import '../support/task_notification_platform.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_TASK_NOTIFICATION_PREVIEWS');
  for (final language in ['bn', 'en']) {
    testWidgets(
        '$language phone controls enable, explain limited device slots and cancel reminders',
        (tester) async {
      final platform = TaskNotificationPlatform()
        ..install(platform: TargetPlatform.iOS);
      if (capture) {
        for (final font in [
          ('AnekBangla', 'assets/fonts/AnekBangla.ttf'),
          ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
        ]) {
          await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
        }
      }
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final id in [
        1001,
        1002,
        1003,
        for (var id = 2000; id <= 2050; id++) id
      ]) {
        platform.pending[id] = {
          'id': id,
          'title': 'Existing reminder',
          'body': 'Saved',
          'payload': ''
        };
      }
      final db = (await tester.runAsync(() => ProductivityDatabase.open(
          uid: 'settings-$language',
          factory: databaseFactoryMemory,
          path: 'settings-notifications-$language')))!;
      await tester.runAsync(() => TaskRepository(db).createTask(
              ProductivityTask(
                  id: 'task',
                  workspaceId: 'personal',
                  title: 'Task reminder',
                  reminders: [
                for (var i = 0; i < 20; i++) DateTime.utc(2090, 1, 1, 0, i)
              ])));
      final controller = TaskReminderController(
          database: db,
          options: ExperienceOptions(language: language, timeZone: 'UTC'));
      await tester.runAsync(controller.start);
      await tester.pumpWidget(RepaintBoundary(
          key: const Key('task-reminder-preview'),
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              locale: Locale(language),
              localizationsDelegates: AppLocalization.delegates,
              supportedLocales: AppLocalization.supportedLocales,
              home: MediaQuery(
                  data:
                      const MediaQueryData(textScaler: TextScaler.linear(1.6)),
                  child: Scaffold(
                      body: SafeArea(
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: TaskReminderSettings(
                                  controller: controller,
                                  strings: ExperienceStrings(language)))))))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      for (var i = 0;
          i < 60 && (controller.delivery?.scheduledCount ?? 0) == 0;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
      }
      await tester.pumpAndSettle();
      // 54 existing requests leave ten slots: nine task reminders + renewal.
      expect(controller.delivery?.scheduledCount, 9,
          reason: 'ready=${controller.ready}, enabled=${controller.enabled}, '
              'working=${controller.working}, error=${controller.error}');
      expect(controller.delivery!.deferredCount, 11);
      expect(
          find.textContaining(
              language == 'bn' ? 'আরও ১১টি' : '11 reminders are not scheduled'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      final semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
      if (capture) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('task-reminder-preview')));
        await tester.runAsync(() async {
          final picture = await boundary.toImage(pixelRatio: 2);
          final bytes =
              await picture.toByteData(format: ui.ImageByteFormat.png);
          await Directory('.local/previews').create(recursive: true);
          await File('.local/previews/task-notifications-$language-phone.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      for (var i = 0;
          i < 60 &&
              (controller.working ||
                  controller.enabled ||
                  platform.pending.length != 54);
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
      }
      await tester.pumpAndSettle();
      expect(controller.enabled, isFalse);
      expect(platform.pending.length, 54);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(controller.close);
      controller.dispose();
      await tester.runAsync(db.close);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
  }
}
