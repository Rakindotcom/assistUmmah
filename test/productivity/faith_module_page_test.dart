import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/calendar_page.dart';
import 'package:ummah_assist/src/pages/dhikr_page.dart';
import 'package:ummah_assist/src/pages/dua_library_page.dart';
import 'package:ummah_assist/src/pages/growth_page.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';
import 'package:ummah_assist/src/pages/prayer_alert_card.dart';
import 'package:ummah_assist/src/prayer_alerts.dart';
import 'package:ummah_assist/src/prayer_times_service.dart';
import 'package:ummah_assist/src/pages/quran_page.dart';
import 'package:ummah_assist/src/pages/tasks_page.dart';
import 'package:ummah_assist/src/pages/report_dialog.dart';
import 'package:ummah_assist/src/pages/trends_page.dart';
import 'package:ummah_assist/src/productivity/ui/faith_module_page.dart';

import '../../tool/ui_preview_repository.dart';
import '../support/native_ui_channels.dart';

void main() {
  setUp(() {
    configureNativeUiChannels();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets(
      'Faith history and reports preserve the account repository and notification opt-out on phone width',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today = DateTime(2026, 11, 5);
    final repository = _FaithHistoryRepository(today: today);
    final notificationCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      notificationCalls.add(call);
      return null;
    });
    await tester.runAsync(() async {
      await PrayerTimeStore(repository.uid).save(PrayerTimeConfig(
          latitude: 23.81,
          longitude: 90.41,
          placeName: 'Dhaka',
          timeZoneId: 'Asia/Dhaka'));
      await PrayerAlertStore(repository.uid)
          .save(PrayerAlertSettings(enabled: true));
    });
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalization.supportedLocales,
        localizationsDelegates: AppLocalization.delegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: Scaffold(
            body: FaithModulePage(
                repository: repository,
                clock: () => today,
                language: 'en',
                enableNotifications: false))));
    await tester.pumpAndSettle();
    expect(find.text('Prayer'), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    var calendar = tester.widget<CalendarPage>(find.byType(CalendarPage));
    expect(calendar.repository, same(repository));
    expect(calendar.today, today);
    expect(calendar.enableNotifications, isFalse);
    await tester.ensureVisible(find.text('নামাজের হিসাব'));
    await tester.tap(find.text('নামাজের হিসাব'));
    await tester.pumpAndSettle();
    var prayer = tester.widget<PrayerPage>(find.byType(PrayerPage));
    expect(prayer.repository, same(repository));
    expect(prayer.day, today);
    expect(prayer.historical, isFalse);
    expect(prayer.enableNotifications, isFalse);
    expect(find.byType(PrayerAlertCard, skipOffstage: false), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('calendar_previous_day')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_previous_day')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('গ্রোথ চেকলিস্ট'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('গ্রোথ চেকলিস্ট'));
    await tester.pumpAndSettle();
    final growth = tester.widget<GrowthPage>(find.byType(GrowthPage));
    expect(growth.repository, same(repository));
    expect(growth.day, DateTime(2026, 11, 4));
    expect(growth.historical, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    final ranges = [
      ('Daily report', today),
      ('Weekly report', DateTime(2026, 10, 30)),
      ('Monthly report', DateTime(2026, 11)),
    ];
    for (final (title, start) in ranges) {
      await tester.ensureVisible(find.text(title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      final report = tester.widget<ReportDialog>(find.byType(ReportDialog));
      expect(report.repository, same(repository));
      expect(report.start, start);
      expect(report.end, today);
      expect(find.text('নামাজ লগড দিন'), findsOneWidget);
      await tester.tap(find.text('বন্ধ'));
      await tester.pumpAndSettle();
    }
    expect(repository.reportRanges,
        ranges.map((value) => (value.$2, today)).toList());
    await tester.ensureVisible(find.text('Progress trends'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Progress trends'));
    await tester.pumpAndSettle();
    final trends = tester.widget<TrendsPage>(find.byType(TrendsPage));
    expect(trends.repository, same(repository));
    expect(trends.today, today);
    expect(trends.enableNotifications, isFalse);
    expect(find.text('শেষ ৩০ দিনের সারাংশ'), findsOneWidget);
    await tester.ensureVisible(find.text('৫/১১'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('৫/১১'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('দিনপঞ্জিতে খুলুন'));
    await tester.pumpAndSettle();
    calendar = tester.widget<CalendarPage>(find.byType(CalendarPage));
    expect(calendar.repository, same(repository));
    expect(calendar.initialDay, today);
    expect(calendar.enableNotifications, isFalse);
    await tester.ensureVisible(find.text('নামাজের হিসাব'));
    await tester.tap(find.text('নামাজের হিসাব'));
    await tester.pumpAndSettle();
    prayer = tester.widget<PrayerPage>(find.byType(PrayerPage));
    expect(prayer.enableNotifications, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(TasksPage, skipOffstage: false), findsNothing);
    expect(repository.taskReads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(notificationCalls, isEmpty);
  });

  testWidgets(
      'notification opt-out survives prayer time edits and resume without native calls',
      (tester) async {
    final repository = UiPreviewRepository(today: DateTime(2026, 11, 5));
    await tester.runAsync(() async {
      await PrayerTimeStore(repository.uid).save(PrayerTimeConfig(
          latitude: 23.81,
          longitude: 90.41,
          placeName: 'Dhaka',
          timeZoneId: 'Asia/Dhaka'));
      await PrayerAlertStore(repository.uid)
          .save(PrayerAlertSettings(enabled: true));
    });
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      calls.add(call);
      return null;
    });
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalization.supportedLocales,
        localizationsDelegates: AppLocalization.delegates,
        home: Scaffold(
            body: FaithModulePage(
                repository: repository, enableNotifications: false))));
    await tester.pumpAndSettle();
    expect(find.byType(PrayerAlertCard, skipOffstage: false), findsNothing);
    await tester.tap(find.text('পরিবর্তন'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('সময় সংরক্ষণ করুন'), 250,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('সময় সংরক্ষণ করুন'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(calls, isEmpty);
    expect(
        (await tester.runAsync(() => PrayerAlertStore(repository.uid).load()))!
            .enabled,
        isTrue);
    expect(tester.takeException(), isNull);
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
    expect(find.text('দিনপঞ্জি'), findsOneWidget);
    expect(find.text('রিপোর্ট'), findsOneWidget);
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

class _FaithHistoryRepository extends UiPreviewRepository {
  _FaithHistoryRepository({required super.today});
  final reportRanges = <(DateTime, DateTime)>[];
  int taskReads = 0;

  @override
  bool get canSync => true;

  @override
  Future<Map<String, dynamic>?> loadTasksForDate(String date) async {
    taskReads++;
    throw StateError('Faith routes must not read or roll over legacy tasks.');
  }

  @override
  Future<ReportSummary> buildReport(
      {required DateTime start, required DateTime end}) {
    reportRanges.add((start, end));
    return super.buildReport(start: start, end: end);
  }
}
