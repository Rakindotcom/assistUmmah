// Local visual fixture. No Firebase or real account records.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/productivity/data/calendar_event_repository.dart';
import 'package:ummah_assist/src/productivity/data/daily_planning_repository.dart';
import 'package:ummah_assist/src/productivity/data/experience_repository.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_event.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/ui/daily_planning_page.dart';

void main() {
  testWidgets('render daily plan with bundled Bangla and English fonts',
      (tester) async {
    for (final font in [
      ('AnekBangla', 'assets/fonts/AnekBangla.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = CalendarDay(2026, 11, 9);
    for (final language in ['bn', 'en']) {
      final options = ExperienceOptions(
          language: language,
          timeZone: 'Asia/Dhaka',
          use24HourClock: true,
          completedOnboarding: true);
      final db = (await tester.runAsync(() async {
        final db = await ProductivityDatabase.open(
            uid: 'plan-$language',
            factory: databaseFactoryMemory,
            path: 'visual-plan-$language');
        await ExperienceRepository(db).completeOnboarding(options);
        final tasks = TaskRepository(db);
        await tasks.createTask(ProductivityTask(
            id: 'proposal',
            workspaceId: 'personal',
            title: language == 'bn'
                ? 'প্রকল্পের প্রস্তাবনা তৈরি'
                : 'Prepare the project proposal',
            priority: TaskPriority.high,
            estimatedMinutes: 45,
            scheduledDay: day,
            inbox: false));
        await tasks.createTask(ProductivityTask(
            id: 'reading',
            workspaceId: 'personal',
            title: language == 'bn' ? 'বই পড়া' : 'Read a chapter',
            estimatedMinutes: 30,
            scheduledDay: day,
            inbox: false));
        await CalendarEventRepository(db).create(CalendarEvent(
            id: 'meeting',
            workspaceId: 'personal',
            title: 'Meeting',
            start: DateTime.utc(2026, 11, 9, 3),
            end: DateTime.utc(2026, 11, 9, 4),
            timeZone: 'Asia/Dhaka'));
        return db;
      }))!;
      await tester.pumpWidget(RepaintBoundary(
          key: const Key('daily-plan-preview'),
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              locale: Locale(language),
              localizationsDelegates: AppLocalization.delegates,
              supportedLocales: AppLocalization.supportedLocales,
              home: DailyPlanningPage(
                  repository: DailyPlanningRepository(db,
                      clock: () => DateTime.utc(2026, 11, 9)),
                  day: day,
                  options: options))));
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('daily-plan-preview')));
      await tester.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await Directory('.local/previews').create(recursive: true);
        await File('.local/previews/daily-plan-$language-phone.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(db.close);
    }
  });
}
