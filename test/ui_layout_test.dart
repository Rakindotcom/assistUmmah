import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/auth/auth_screen.dart';
import 'package:ummah_assist/src/home_shell.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/calendar_page.dart';
import 'package:ummah_assist/src/pages/contacts_page.dart';
import 'package:ummah_assist/src/pages/dhikr_page.dart';
import 'package:ummah_assist/src/pages/growth_checklist_editor.dart';
import 'package:ummah_assist/src/pages/growth_page.dart';
import 'package:ummah_assist/src/pages/more_page.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';
import 'package:ummah_assist/src/pages/qaza_page.dart';
import 'package:ummah_assist/src/pages/quran_page.dart';
import 'package:ummah_assist/src/pages/settings_page.dart';
import 'package:ummah_assist/src/pages/tasks_page.dart';
import 'package:ummah_assist/src/pages/trends_page.dart';
import 'package:ummah_assist/src/progress_trends.dart';

import '../tool/ui_preview_repository.dart';
import 'support/native_ui_channels.dart';

void _noop() {}

void main() {
  setUpAll(() async {
    final loader = FontLoader('AnekBangla')
      ..addFont(rootBundle.load('assets/fonts/AnekBangla.ttf'));
    await loader.load();
  });
  setUp(() {
    configureNativeUiChannels();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  final day = DateTime(2026, 10, 26);
  for (final populated in [false, true]) {
    final repository = populated
        ? UiPreviewRepository(today: day)
        : const AppRepository(uid: 'demo', firebaseReady: false);
    final screens = <String, Widget Function()>{
      'shell': () =>
          HomeShell(firebaseReady: false, repository: repository, user: null),
      'sign in': () => const AuthScreen(),
      'tasks': () => TasksPage(repository: repository, day: day),
      'prayers': () => PrayerPage(repository: repository, day: day),
      'growth': () => GrowthPage(repository: repository, day: day),
      'checklist editor': () => const GrowthChecklistEditor(
          title: 'ইমান চেকলিস্ট',
          initialItems: imanChecklist,
          defaultItems: imanChecklist),
      'more': () => const MorePage(
          onOpenCalendar: _noop,
          onOpenQuran: _noop,
          onOpenDhikr: _noop,
          onOpenContacts: _noop,
          onOpenSettings: _noop),
      'calendar': () => CalendarPage(repository: repository, today: day),
      'contacts': () => ContactsPage(repository: repository),
      'settings': () => SettingsPage(
          repository: repository, user: null, firebaseReady: false),
      'qaza': () => QazaPage(repository: repository, today: day),
      'quran': () => QuranPage(repository: repository, today: day),
      'dhikr': () => DhikrPage(repository: repository, today: day),
      'trends': () => TrendsPage(
          repository: populated ? repository : const _TrendsRepository(),
          today: day),
    };
    for (final layout in [
      (320.0, 720.0, 1.6),
      (390.0, 844.0, 1.0),
      (1280.0, 900.0, 1.0)
    ]) {
      for (final entry in screens.entries) {
        if (populated &&
            ['sign in', 'checklist editor', 'more'].contains(entry.key)) {
          continue;
        }
        testWidgets(
            '${entry.key} (${populated ? 'sample' : 'empty'}) fits ${layout.$1.toInt()}px at ${layout.$3}x text',
            (tester) async {
          configureNativeUiChannels();
          tester.view.physicalSize = Size(layout.$1, layout.$2);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          if (layout.$1 < 820) {
            tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
            tester.view.viewPadding =
                const FakeViewPadding(top: 44, bottom: 34);
            addTearDown(tester.view.resetPadding);
            addTearDown(tester.view.resetViewPadding);
          }
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            locale: AppLocalization.locale,
            supportedLocales: AppLocalization.supportedLocales,
            localizationsDelegates: AppLocalization.delegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(layout.$3)),
                child: child!),
            home: Scaffold(body: entry.value()),
          ));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
            variant: layout.$1 < 820
                ? const TargetPlatformVariant(
                    {TargetPlatform.android, TargetPlatform.iOS})
                : TargetPlatformVariant.only(TargetPlatform.linux));
      }
    }
  }
}

class _TrendsRepository extends AppRepository {
  const _TrendsRepository()
      : super(uid: 'review-fixture', firebaseReady: false);
  @override
  bool get canSync => true;
  @override
  Future<ProgressTrends> loadProgressTrends(
          {required DateTime end, int dayCount = 30}) async =>
      ProgressTrends.fromDocuments(
          end: end, dayCount: dayCount, prayers: const {}, growth: const {});
}
