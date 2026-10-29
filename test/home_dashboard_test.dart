import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/date_helpers.dart';
import 'package:ummah_assist/src/home_shell.dart';
import 'package:ummah_assist/src/pages/dua_library_page.dart';
import 'package:ummah_assist/src/prayer_times_service.dart';
import 'package:ummah_assist/src/widgets/home_prayer_card.dart';
import 'package:ummah_assist/src/home_prayer_snapshot.dart';
import 'support/native_ui_channels.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('AnekBangla')
          ..addFont(rootBundle.load('assets/fonts/AnekBangla.ttf')))
        .load();
  });

  setUp(() {
    configureNativeUiChannels();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Widget app(AppRepository repository, DateTime Function() clock) =>
      MaterialApp(
          theme: AppTheme.light,
          home: HomeShell(
              firebaseReady: false,
              repository: repository,
              user: null,
              clock: clock));

  testWidgets('home features remain usable while personal data is waiting',
      (tester) async {
    final repository = _HomeRepository()
      ..gate = Completer<Map<String, dynamic>?>();
    await tester.pumpWidget(app(repository, () => DateTime(2026, 10, 29)));
    await tester.pump();
    expect(find.text('আসসালামু আলাইকুম'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('home-dua')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('home-dua')));
    await tester.pumpAndSettle();
    expect(find.byType(DuaLibraryPage), findsOneWidget);
    await tester.tap(find.byTooltip('হোমে ফিরুন'));
    await tester.pump();
    expect(find.text('আসসালামু আলাইকুম'), findsOneWidget);
    repository.gate!.complete(null);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'quick location enables local times and fasting today or tomorrow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 10, 29, 12);
    final repository = _HomeRepository();
    await tester.pumpWidget(app(repository, () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('স্থান সেট করুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ঢাকা'));
    await tester.pumpAndSettle();
    expect((await PrayerTimeStore(repository.uid).load())?.placeName, 'ঢাকা');
    expect(find.byKey(const Key('home-prayer-countdown')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('home-fasting')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-fasting')));
    await tester.pumpAndSettle();
    expect(find.textContaining(compactDateLabel(now)), findsOneWidget);
    await tester.tap(find.text('আগামীকাল'));
    await tester.pumpAndSettle();
    expect(find.textContaining('৩০/১০/২০২৬'), findsOneWidget);
    expect(find.text('সাহরির শেষ সীমা · ফজর শুরু'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('live countdown advances without repeating account reads',
      (tester) async {
    final repository = _HomeRepository();
    final config = PrayerTimeConfig(
        latitude: 23.81,
        longitude: 90.41,
        placeName: 'ঢাকা',
        timeZoneId: 'Asia/Dhaka');
    await PrayerTimeStore(repository.uid).save(config);
    var now = PrayerTimeService.forDay(config, DateTime(2026, 10, 29))
        .entries[2]
        .time
        .subtract(const Duration(seconds: 2));
    await tester.pumpWidget(app(repository, () => now));
    await tester.pumpAndSettle();
    final reads = repository.reads;
    expect(find.text('০০:০০:০২'), findsOneWidget);
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    final snapshot = HomePrayerSnapshot(config, now);
    expect(
        tester
            .widget<Text>(find.byKey(const Key('home-prayer-countdown')))
            .data,
        prayerCountdown(snapshot.remaining));
    expect(repository.reads, reads);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('prayer countdown stops while its home is inactive',
      (tester) async {
    final config = PrayerTimeConfig(
        latitude: 23.81,
        longitude: 90.41,
        placeName: 'ঢাকা',
        timeZoneId: 'Asia/Dhaka');
    var now = DateTime(2026, 10, 29, 12);
    Widget card(bool active) => MaterialApp(
        home: Scaffold(
            body: HomePrayerCard(
                config: config,
                onOpen: () {},
                onConfigure: () {},
                clock: () => now,
                active: active)));
    await tester.pumpWidget(card(false));
    await tester.pump();
    final initial = tester
        .widget<Text>(find.byKey(const Key('home-prayer-countdown')))
        .data;
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(
        tester
            .widget<Text>(find.byKey(const Key('home-prayer-countdown')))
            .data,
        initial);
    await tester.pumpWidget(card(true));
    await tester.pump();
    expect(
        tester
            .widget<Text>(find.byKey(const Key('home-prayer-countdown')))
            .data,
        isNot(initial));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('configured home and fasting fit a small phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _HomeRepository();
    await PrayerTimeStore(repository.uid).save(PrayerTimeConfig(
        latitude: 23.81,
        longitude: 90.41,
        placeName: 'ঢাকা',
        timeZoneId: 'Asia/Dhaka'));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: HomeShell(
            firebaseReady: false,
            repository: repository,
            user: null,
            clock: () => DateTime(2026, 10, 29))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('home-fasting')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-fasting')));
    await tester.pumpAndSettle();
    expect(find.text('সাহরির শেষ সীমা · ফজর শুরু'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _HomeRepository extends AppRepository {
  _HomeRepository() : super(uid: 'home-test', firebaseReady: false);
  Completer<Map<String, dynamic>?>? gate;
  int reads = 0;
  @override
  Future<Map<String, dynamic>?> loadTasksForDate(String date) async {
    reads++;
    return gate?.future;
  }

  @override
  Future<Map<String, dynamic>?> loadPrayerDocument(String date) async {
    reads++;
    return null;
  }

  @override
  Future<Map<String, dynamic>?> loadGrowth(String date) async {
    reads++;
    return null;
  }
}
