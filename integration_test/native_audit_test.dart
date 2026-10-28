// Runs on a disposable emulator. Only the dedicated synthetic reviewer identity
// is accessed. Screenshot records are fabricated fixtures in its Firestore data.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ummah_assist/main.dart' as app;
import 'package:ummah_assist/src/account/privacy_page.dart';
import 'package:ummah_assist/src/account/account_service.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/auth/auth_screen.dart';
import 'package:ummah_assist/src/home_shell.dart';
import 'package:ummah_assist/src/pages/dhikr_page.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';
import 'package:ummah_assist/src/pages/quran_page.dart';
import 'package:ummah_assist/src/pages/tasks_page.dart';
import 'package:ummah_assist/src/reminder_service.dart';
import 'package:ummah_assist/src/prayer_alerts.dart';
import 'package:ummah_assist/src/prayer_times_service.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'native startup, bundled privacy, plugin initialization and screens',
      (tester) async {
    app.main();
    await waitFor(tester, find.byType(AuthScreen));
    expect(FirebaseAuth.instance.currentUser, isNull,
        reason: 'Use a fresh emulator without a signed-in account.');
    expect(
        FirebaseCrashlytics.instance.isCrashlyticsCollectionEnabled, isFalse);
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('01-sign-in');

    await tester.ensureVisible(find.text('গোপনীয়তা নীতি'));
    await tester.tap(find.text('গোপনীয়তা নীতি'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPage), findsOneWidget);
    // Confirms that the bundled Bengali policy parses on Android too.
    expect(find.text('গোপনীয়তা নীতি'), findsWidgets);
    await waitFor(tester, find.text('আমাদের পরিচয় ও যোগাযোগ'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Real native method channels: notification initialization, timezone lookup
    // and cancellation. This does not claim delivery, permission or Doze tests.
    await ReminderService.instance.cancelAll();
    final pageSize = await Process.run('/system/bin/getconf', ['PAGESIZE']);
    expect(pageSize.exitCode, 0);
    expect(pageSize.stdout.toString().trim(), '16384',
        reason: 'This audit must run on the dedicated 16 KB system image.');
    final configuration = PrayerTimeConfig(
        latitude: 23.81,
        longitude: 90.41,
        placeName: 'ঢাকা',
        timeZoneId: 'Asia/Dhaka');
    final localStore = PrayerTimeStore('native-audit-fixture');
    await localStore.save(configuration);
    expect((await localStore.load())?.toJson(), configuration.toJson());
    await localStore.remove();
    expect(await localStore.load(), isNull);
    final denied = await ReminderService.instance.syncPrayerAlerts(
        config: configuration,
        settings: PrayerAlertSettings(enabled: true),
        requestPermission: false);
    expect(denied.permissionGranted, isFalse,
        reason: 'Use a fresh emulator with notification permission ungranted.');
    expect(denied.scheduledCount, 0);

    const reviewEmail = String.fromEnvironment('email');
    const reviewPassword = String.fromEnvironment('password');
    const reviewUid = String.fromEnvironment('uid');
    expect(
        reviewEmail.isNotEmpty &&
            reviewPassword.isNotEmpty &&
            reviewUid.isNotEmpty,
        isTrue,
        reason: 'Pass the private dedicated reviewer credential file.');
    // The headless integration binding doesn't register simulated text input
    // automatically. Exercise the form without relying on a system IME window.
    tester.testTextInput.register();
    final signInWatch = Stopwatch();
    try {
      await tester.enterText(find.byType(TextFormField).at(0), reviewEmail);
      await tester.enterText(find.byType(TextFormField).at(1), reviewPassword);
      expect(
          tester
                  .widget<TextFormField>(find.byType(TextFormField).at(0))
                  .controller!
                  .text ==
              reviewEmail,
          isTrue);
      expect(
          tester
                  .widget<TextFormField>(find.byType(TextFormField).at(1))
                  .controller!
                  .text ==
              reviewPassword,
          isTrue);
      await tester.ensureVisible(find.text('লগইন'));
      signInWatch.start();
      await tester.tap(find.text('লগইন'));
      await waitFor(tester, find.byType(HomeShell));
      await waitForLoadedPage(tester);
    } finally {
      tester.testTextInput.unregister();
    }
    signInWatch.stop();
    expect(FirebaseAuth.instance.currentUser?.uid, reviewUid);
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(reviewUid)
        .get(const GetOptions(source: Source.server));
    expect(profile.exists, isTrue);
    expect(find.text('প্রিভিউ'), findsNothing);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('02-dashboard');

    final firstTabLoadMs = <String, int>{};
    for (final destination in [
      ('কাজ', '03-tasks', TasksPage),
      ('নামাজ', '04-prayers', PrayerPage),
    ]) {
      final watch = Stopwatch()..start();
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text(destination.$1)));
      await tester.pumpAndSettle();
      await waitForLoadedPage(tester);
      watch.stop();
      firstTabLoadMs[destination.$1] = watch.elapsedMilliseconds;
      expect(find.byType(destination.$3), findsOneWidget);
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot(destination.$2);
    }
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('আরও')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('কুরআন রিডিং'));
    await tester.pumpAndSettle();
    expect(find.byType(QuranPage), findsOneWidget);
    await waitForLoadedPage(tester);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('05-quran');

    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('আরও')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('যিকিরের লক্ষ্য'));
    await tester.pumpAndSettle();
    expect(find.byType(DhikrPage), findsOneWidget);
    await waitForLoadedPage(tester);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('06-dhikr');

    // A real account-scoped range read exercises the report query, including
    // its normal Firestore network path. It does not mutate reviewer records.
    final reportWatch = Stopwatch()..start();
    final report =
        await const AppRepository(uid: reviewUid, firebaseReady: true).buildReport(
      start: DateTime.now().subtract(const Duration(days: 6)),
      end: DateTime.now(),
    );
    reportWatch.stop();
    expect(report.days, 7);
    expect(report.prayerLoggedDays, greaterThanOrEqualTo(5));
    expect(report.growthLoggedDays, greaterThanOrEqualTo(5));

    // FrameTiming is gathered by the official profile-mode integration
    // binding. Screenshot captures above are outside this measurement window.
    await binding.watchPerformance(() async {
      for (final name in ['আজ', 'কাজ', 'নামাজ', 'গ্রোথ', 'আরও']) {
        await tester.tap(find.descendant(
            of: find.byType(NavigationBar), matching: find.text(name)));
        await tester.pumpAndSettle();
      }
    }, reportKey: 'tabNavigationFrameTimings');
    await AccountService.signOut();
    expect(FirebaseAuth.instance.currentUser, isNull);
    await waitFor(tester, find.byType(AuthScreen));
    binding.reportData = {
      ...?binding.reportData,
      'nativeStartup': true,
      'bundledPrivacy': true,
      'crashCollectionInitiallyDisabled': true,
      'notificationPluginInitializationAndCancellation': true,
      'notificationPermissionUngrantedSchedulesZero': true,
      'nativePreferenceRoundTripAndRemoval': true,
      'nativePasswordSignIn': true,
      'nativeSignInFormSubmitted': true,
      'formTextInputSimulated': true,
      'nativeFirestoreOwnerRead': true,
      'nativeSignOut': true,
      'profileRuntimePageSize': 16384,
      'screenCount': 6,
      'signInToDashboardReadyMs': signInWatch.elapsedMilliseconds,
      'firstTabLoadMs': firstTabLoadMs,
      'sevenDayReportLoadMs': reportWatch.elapsedMilliseconds,
      'performanceSampleScope':
          'single profile-mode API 36 x86_64 emulator run with live Firestore; not a physical-device benchmark',
      'dataSource':
          'dedicated synthetic Firebase reviewer records; production widgets and repository',
      'googleSignInTested': false,
      'notificationDeliveryTested': false,
      'playInstalledBuild': false,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> waitForLoadedPage(WidgetTester tester) async {
  final watch = Stopwatch()..start();
  await tester.pump();
  while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
      watch.elapsed < const Duration(seconds: 60)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(find.byType(CircularProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(finder, findsOneWidget);
  await tester.pumpAndSettle();
}
