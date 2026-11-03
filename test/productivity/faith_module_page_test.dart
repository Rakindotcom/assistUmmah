import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/pages/dhikr_page.dart';
import 'package:ummah_assist/src/pages/dua_library_page.dart';
import 'package:ummah_assist/src/pages/growth_page.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';
import 'package:ummah_assist/src/pages/quran_page.dart';
import 'package:ummah_assist/src/pages/tasks_page.dart';
import 'package:ummah_assist/src/productivity/ui/faith_module_page.dart';

import '../../tool/ui_preview_repository.dart';
import '../support/native_ui_channels.dart';

void main() {
  setUp(() {
    configureNativeUiChannels();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('Faith tabs keep legacy task routes out and open content lazily',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today = DateTime(2026, 11, 3);
    final repository = UiPreviewRepository(today: today);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalization.supportedLocales,
        localizationsDelegates: AppLocalization.delegates,
        home: Scaffold(
            body:
                FaithModulePage(repository: repository, clock: () => today))));
    await _pumpUi(tester);

    expect(find.byType(PrayerPage), findsOneWidget);
    expect(find.byType(TasksPage, skipOffstage: false), findsNothing);
    expect(find.byType(QuranPage, skipOffstage: false), findsNothing);
    expect(find.byType(DhikrPage, skipOffstage: false), findsNothing);
    expect(find.byType(GrowthPage, skipOffstage: false), findsNothing);
    expect(find.byType(DuaLibraryPage, skipOffstage: false), findsNothing);

    await tester.tap(find.text('গ্রোথ').first);
    await _pumpUi(tester);
    expect(find.byType(GrowthPage), findsOneWidget);
    final growth = tester.widget<GrowthPage>(find.byType(GrowthPage));
    growth.onOpenQuran!();
    await _pumpUi(tester);
    expect(find.byType(QuranPage), findsOneWidget);
    expect(find.text('কুরআন রিডিং'), findsOneWidget);

    await tester.tap(find.text('জিকির').first);
    await _pumpUi(tester);
    expect(find.byType(DhikrPage), findsOneWidget);
    await tester.ensureVisible(find.text('দোয়া').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('দোয়া').first);
    await _pumpUi(tester);
    expect(find.byType(DuaLibraryPage), findsOneWidget);
    expect(find.byType(TasksPage, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Faith page reopens today on resume at midnight', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var now = DateTime(2026, 11, 3, 23, 55);
    final repository = UiPreviewRepository(today: now);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalization.supportedLocales,
        localizationsDelegates: AppLocalization.delegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: Scaffold(
            body: FaithModulePage(repository: repository, clock: () => now))));
    await _pumpUi(tester);
    expect(tester.widget<PrayerPage>(find.byType(PrayerPage)).day.day, 3);
    now = DateTime(2026, 11, 4, 8);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpUi(tester);
    expect(tester.widget<PrayerPage>(find.byType(PrayerPage)).day.day, 4);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
}
