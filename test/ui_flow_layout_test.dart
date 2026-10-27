import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/auth/auth_screen.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/contacts_page.dart';
import 'package:ummah_assist/src/pages/dhikr_page.dart';
import 'package:ummah_assist/src/pages/growth_checklist_editor.dart';
import 'package:ummah_assist/src/pages/prayer_alert_card.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';
import 'package:ummah_assist/src/pages/quran_page.dart';
import 'package:ummah_assist/src/pages/settings_page.dart';
import 'package:ummah_assist/src/pages/tasks_page.dart';
import 'package:ummah_assist/src/pages/trends_page.dart';
import 'package:ummah_assist/src/prayer_alerts.dart';
import 'package:ummah_assist/src/reminder_service.dart';

import '../tool/ui_preview_repository.dart';
import 'support/native_ui_channels.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('AnekBangla')
      ..addFont(rootBundle.load('assets/fonts/AnekBangla.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    configureNativeUiChannels();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  final day = DateTime(2026, 10, 26);
  final platform =
      const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS});

  for (final page in [
    (
      'tasks',
      'কাজ লোড করা যায়নি',
      'আজকের কাজ',
      (_FailingLoads repo) => TasksPage(repository: repo, day: day)
    ),
    (
      'prayers',
      'নামাজের হিসাব লোড করা যায়নি',
      'নামাজ ট্র্যাকিং',
      (_FailingLoads repo) => PrayerPage(repository: repo, day: day)
    ),
    (
      'contacts',
      'যোগাযোগ লোড করা যায়নি',
      'জরুরি যোগাযোগ',
      (_FailingLoads repo) => ContactsPage(repository: repo)
    ),
    (
      'settings',
      'সেটিংস লোড করা যায়নি',
      'সেটিংস',
      (_FailingLoads repo) =>
          SettingsPage(repository: repo, user: null, firebaseReady: true)
    ),
  ]) {
    _mobileFlow(
        '${page.$1} shows a recoverable load error instead of empty content',
        (tester) async {
      final repository = _FailingLoads(today: day);
      await _mount(tester, page.$4(repository));
      expect(find.text(page.$2), findsOneWidget);
      await _capture(tester, 'load-error-${page.$1}');
      repository.fail = false;
      await _tap(tester, find.text('রিট্রাই'));
      expect(find.text(page.$2), findsNothing);
      expect(find.text(page.$3), findsWidgets);
      expect(tester.takeException(), isNull);
    }, variant: platform);
  }

  _mobileFlow('signup validation fits enlarged text and the keyboard',
      (tester) async {
    await _mount(tester, const AuthScreen());
    await _tap(tester, find.text('কোন অ্যাকাউন্ট নেই? সাইন আপ করুন'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    await _tap(
        tester, find.widgetWithText(FilledButton, 'অ্যাকাউন্ট তৈরি করুন'));
    expect(find.text('দয়া করে আপনার নাম লিখুন'), findsOneWidget);
    await _capture(tester, 'signup-keyboard-large');
    expect(tester.takeException(), isNull);
  }, variant: platform);

  _mobileFlow('password reset feedback fits enlarged text', (tester) async {
    await _mount(tester, const AuthScreen());
    await _tap(tester, find.text('পাসওয়ার্ড ভুলে গেছেন?'));
    expect(find.text('পাসওয়ার্ড রিসেট করতে প্রথমে ইমেইল দিন'), findsOneWidget);
    await _capture(tester, 'password-reset-feedback-large');
    expect(tester.takeException(), isNull);
  }, variant: platform);

  _mobileFlow('native Bengali date picker fits enlarged text', (tester) async {
    await _mount(tester,
        TasksPage(repository: UiPreviewRepository(today: day), day: day));
    await _tap(tester, find.text('কাজ যোগ'));
    await _tap(tester, find.textContaining('তারিখ:'));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.textContaining('অক্টো'), findsWidgets);
    await _capture(tester, 'date-picker-large');
    expect(tester.takeException(), isNull);
  }, variant: platform);

  _mobileFlow('task dialog fits enlarged text and the keyboard',
      (tester) async {
    await _mount(tester,
        TasksPage(repository: UiPreviewRepository(today: day), day: day));
    await _tap(tester, find.text('কাজ যোগ'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    await tester.enterText(
        find.byType(TextField), 'প্রতিদিন মনোযোগ দিয়ে পড়ার জন্য সময় রাখা');
    await _capture(tester, 'task-dialog-keyboard-large');
    await _tap(tester, find.text('যোগ করুন'));
    expect(find.text('প্রতিদিন মনোযোগ দিয়ে পড়ার জন্য সময় রাখা'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: platform);

  _mobileFlow('prayer location form fits enlarged text and the keyboard',
      (tester) async {
    await _mount(tester,
        PrayerPage(repository: UiPreviewRepository(today: day), day: day));
    await _tap(tester, find.text('সেট করুন'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, 'ঢাকা');
    await _capture(tester, 'prayer-location-keyboard-large');
    expect(tester.takeException(), isNull);
  }, variant: platform);

  _mobileFlow('prayer alert controls fit enlarged text', (tester) async {
    await _mount(
        tester,
        SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: PrayerAlertCard(
                settings:
                    PrayerAlertSettings(enabled: true, quietEnabled: true),
                locationReady: true,
                busy: false,
                permissionGranted: true,
                exact: true,
                scheduledCount: 30,
                onChanged: (_, __) {},
                onConfigureLocation: () {})));
    await _capture(tester, 'prayer-alerts-large');
    expect(tester.takeException(), isNull);
  }, variant: platform);

  _mobileFlow('checklist item editor fits enlarged text and the keyboard',
      (tester) async {
    await _mount(
        tester,
        const GrowthChecklistEditor(
            title: 'ইমান চেকলিস্ট',
            initialItems: imanChecklist,
            defaultItems: imanChecklist));
    await _tap(tester, find.text('আইটেম যোগ'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    await tester.enterText(
        find.byType(TextFormField), 'প্রতিদিন একটি ভালো অভ্যাস');
    await _capture(tester, 'checklist-item-keyboard-large');
    await _tap(tester, find.text('ঠিক আছে'));
    tester.view.resetViewInsets();
    await tester.pump();
    await tester.scrollUntilVisible(find.text('প্রতিদিন একটি ভালো অভ্যাস'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('প্রতিদিন একটি ভালো অভ্যাস'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: platform);

  _mobileFlow('Quran goal and reading editors fit enlarged text',
      (tester) async {
    await _mount(tester,
        QuranPage(repository: UiPreviewRepository(today: day), today: day));
    await _tap(tester, find.text('পরিবর্তন'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    await _capture(tester, 'quran-goal-keyboard-large');
    expect(tester.takeException(), isNull);
    await _tap(tester, find.text('বাতিল'));
    tester.view.resetViewInsets();
    await tester.pump();
    await _tap(tester, find.text('হিসাব সংশোধন করুন'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    await tester.scrollUntilVisible(find.text('হিসাব সংরক্ষণ'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, variant: platform);

  _mobileFlow('Dhikr count and goal editors fit enlarged text', (tester) async {
    await _mount(tester,
        DhikrPage(repository: UiPreviewRepository(today: day), today: day));
    await _tap(tester, find.text('সংখ্যা যোগ করুন').first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await _tap(tester, find.text('বাতিল'));
    tester.view.resetViewInsets();
    await tester.pump();
    await _tap(tester, find.text('লক্ষ্য সম্পাদনা'));
    await _capture(tester, 'dhikr-goals-large');
    expect(find.text('যিকিরের লক্ষ্য সম্পাদনা'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: platform);

  _mobileFlow('contact dialog can save a name with enlarged text',
      (tester) async {
    await _mount(
        tester, ContactsPage(repository: UiPreviewRepository(today: day)));
    await _tap(tester, find.text('যোগাযোগ'));
    await tester.enterText(
        find.byType(TextField), 'পরিবারের সঙ্গে নিয়মিত যোগাযোগ');
    await _tap(tester, find.text('যোগ করুন'));
    expect(find.text('পরিবারের সঙ্গে নিয়মিত যোগাযোগ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: platform);

  _mobileFlow('profile and report dialogs fit enlarged text', (tester) async {
    await _mount(
        tester,
        SettingsPage(
            repository: UiPreviewRepository(today: day),
            user: null,
            firebaseReady: true));
    await _tap(tester, find.text('প্রোফাইল'));
    await tester.enterText(find.byType(TextField), 'পর্যালোচনার নমুনা নাম');
    await _tap(tester, find.text('সেভ'));
    expect(tester.takeException(), isNull);
    await _tap(tester, find.text('দৈনিক রিপোর্ট'));
    await _capture(tester, 'report-large');
    expect(tester.takeException(), isNull);
  }, variant: platform);

  _mobileFlow('trend day sheet fits enlarged text', (tester) async {
    await _mount(tester,
        TrendsPage(repository: UiPreviewRepository(today: day), today: day));
    await _tap(tester, find.text('২৬/১০'));
    expect(find.text('দিনপঞ্জিতে খুলুন'), findsOneWidget);
    await _capture(tester, 'trend-day-large');
    expect(tester.takeException(), isNull);
  }, variant: platform);
}

Future<void> _mount(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(RepaintBoundary(
      key: const Key('ui-review-capture'),
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: AppLocalization.locale,
          supportedLocales: AppLocalization.supportedLocales,
          localizationsDelegates: AppLocalization.delegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!),
          home: Scaffold(body: page))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('ui-review-capture')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('docs/ui-screenshots');
    await directory.create(recursive: true);
    await File('${directory.path}/$name-${defaultTargetPlatform.name}.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _FailingLoads extends UiPreviewRepository {
  _FailingLoads({required super.today});
  bool fail = true;
  void _check() {
    if (fail) throw StateError('Simulated read failure');
  }

  @override
  Future<Map<String, dynamic>?> loadTasksForDate(String date) async {
    _check();
    return super.loadTasksForDate(date);
  }

  @override
  Future<Map<String, dynamic>?> loadPrayerDocument(String date) async {
    _check();
    return super.loadPrayerDocument(date);
  }

  @override
  Future<Map<String, dynamic>?> loadContacts() async {
    _check();
    return super.loadContacts();
  }

  @override
  Future<Map<String, dynamic>?> loadSettings() async {
    _check();
    return super.loadSettings();
  }
}

void _mobileFlow(String description, WidgetTesterCallback body,
    {required TargetPlatformVariant variant}) {
  testWidgets(description, (tester) async {
    configureNativeUiChannels();
    try {
      await body(tester);
    } finally {
      // Finish platform work in this test's fake-async zone before the next
      // variant reuses the reminder service's serialized queue.
      var nativeWorkFinished = false;
      Object? nativeError;
      ReminderService.instance
          .syncPrayerAlerts(config: null, settings: PrayerAlertSettings())
          .then<void>((_) {
        nativeWorkFinished = true;
      }, onError: (Object error) {
        nativeError = error;
        nativeWorkFinished = true;
      });
      for (var i = 0; i < 100 && !nativeWorkFinished; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(nativeWorkFinished, isTrue);
      expect(nativeError, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      // iOS form validation schedules a delayed accessibility announcement.
      await tester.pump(const Duration(seconds: 2));
    }
  }, variant: variant);
}
