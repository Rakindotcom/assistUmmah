import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/growth_page.dart';

void main() {
  testWidgets('editing a checklist saves its template and daily snapshot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _GrowthRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GrowthPage(repository: repository, day: DateTime(2026, 10, 26)),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('ইমান চেকলিস্ট সম্পাদনা'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('আইটেম যোগ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Daily reflection');
    await tester.tap(find.text('ঠিক আছে'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();

    expect(find.text('Daily reflection'), findsOneWidget);
    expect(repository.config.iman.last.label, 'Daily reflection');
    final saved = repository.documents['2026-10-26']!;
    expect(GrowthChecklistSnapshot.fromDocument(saved).iman.last.label,
        'Daily reflection');
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed checklist save leaves the previous items visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _GrowthRepository()..failSave = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GrowthPage(repository: repository, day: DateTime(2026, 10, 26)),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('ইমান চেকলিস্ট সম্পাদনা'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('আইটেম যোগ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Should not persist');
    await tester.tap(find.text('ঠিক আছে'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();

    expect(find.text('Should not persist'), findsNothing);
    expect(repository.config.iman.length, imanChecklist.length);
    expect(find.text('চেকলিস্ট সংরক্ষণ করা যায়নি'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renaming and removing built-in items updates the saved list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _GrowthRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GrowthPage(repository: repository, day: DateTime(2026, 10, 26)),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('ইমান চেকলিস্ট সম্পাদনা'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('নাম পরিবর্তন').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Personal dhikr');
    await tester.tap(find.text('ঠিক আছে'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('আইটেম মুছুন').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();

    expect(repository.config.iman.length, imanChecklist.length - 1);
    expect(repository.config.iman.first.key, 'istigfar');
    expect(repository.config.iman.first.label, 'Personal dhikr');
    expect(repository.config.iman.any((item) => item.key == 'prayer'), isFalse);
    final saved = repository.documents['2026-10-26']!;
    expect(GrowthChecklistSnapshot.fromDocument(saved).iman.length,
        imanChecklist.length - 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default items can be restored after customization', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _GrowthRepository();
    repository.config = repository.config.withItems('iman', 'student', [
      const ChecklistItem('customOnly', 'Custom only'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GrowthPage(repository: repository, day: DateTime(2026, 10, 26)),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('ইমান চেকলিস্ট সম্পাদনা'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ডিফল্ট ফিরিয়ে আনুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ফিরিয়ে আনুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();

    expect(repository.config.iman.map((item) => item.key),
        imanChecklist.map((item) => item.key));
    expect(tester.takeException(), isNull);
  });

  testWidgets('historical growth uses its saved items without edit controls', (
    tester,
  ) async {
    final repository = _GrowthRepository();
    repository.documents['2026-10-24'] = {
      'userType': 'student',
      'growthData': {
        'iman': {'customDhikr': true},
        'life': {'customStudy': false},
      },
      'checklistItems': const GrowthChecklistSnapshot(
        iman: [ChecklistItem('customDhikr', 'Past dhikr')],
        life: [ChecklistItem('customStudy', 'Past study')],
      ).toMap(),
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GrowthPage(
          repository: repository,
          day: DateTime(2026, 10, 24),
          historical: true,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Past dhikr'), findsOneWidget);
    expect(find.text('Past study'), findsOneWidget);
    expect(find.byTooltip('ইমান চেকলিস্ট সম্পাদনা'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('linking prayer progress follows the recorded prayer states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _GrowthRepository();
    repository.documents['2026-10-26'] = {
      'userType': 'student',
      'growthData': {
        'iman': {'prayer': true},
        'life': <String, bool>{},
      },
    };
    Widget page(int token) => MaterialApp(
          home: Scaffold(
            body: GrowthPage(
              repository: repository,
              day: DateTime(2026, 10, 26),
              refreshToken: token,
            ),
          ),
        );
    await tester.pumpWidget(page(0));
    await tester.pump();
    final prayerCheckbox =
        find.widgetWithText(CheckboxListTile, '৫ ওয়াক্ত নামাজ পড়েছি');
    expect(tester.widget<CheckboxListTile>(prayerCheckbox).value, isTrue);

    await tester.tap(find.text('নামাজের হিসাবের সাথে যুক্ত'));
    await tester.pump();
    expect(repository.documents['2026-10-26']!['prayerLinked'], isTrue);
    expect(tester.widget<CheckboxListTile>(prayerCheckbox).value, isFalse);
    expect(tester.widget<CheckboxListTile>(prayerCheckbox).onChanged, isNull);

    repository.prayers['2026-10-26'] = {
      'prayers': {
        for (final key in prayerKeys) key: {'state': 'prayed'},
      },
    };
    await tester.pumpWidget(page(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<CheckboxListTile>(prayerCheckbox).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('growth shows a retry when linked prayer data cannot load', (
    tester,
  ) async {
    final repository = _GrowthRepository()..failPrayerRead = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GrowthPage(repository: repository, day: DateTime(2026, 10, 26)),
      ),
    ));
    await tester.pump();
    expect(find.text('গ্রোথের তথ্য লোড করা যায়নি'), findsOneWidget);
    expect(find.text('রিট্রাই'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed growth write keeps the draft across tab refresh and retries',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _GrowthRepository()..failSave = true;
    Widget page(int token) => MaterialApp(
          home: Scaffold(
            body: GrowthPage(
              repository: repository,
              day: DateTime(2026, 10, 26),
              refreshToken: token,
            ),
          ),
        );
    await tester.pumpWidget(page(0));
    await tester.pump();
    final checkbox = find.widgetWithText(
        CheckboxListTile, 'ইস্তিগফার ও মাইন্ডফুল জিকির করেছি');
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
    expect(find.text('পরিবর্তন সংরক্ষিত হয়নি'), findsOneWidget);
    expect(repository.documents, isEmpty);

    await tester.pumpWidget(page(1));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
    expect(find.text('পরিবর্তন সংরক্ষিত হয়নি'), findsOneWidget);

    repository.failSave = false;
    await tester.ensureVisible(find.text('আবার সংরক্ষণ করুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('আবার সংরক্ষণ করুন'));
    await tester.pumpAndSettle();
    expect(
        repository.documents['2026-10-26']!['growthData']['iman']['istigfar'],
        isTrue);
    expect(find.text('পরিবর্তন সংরক্ষিত হয়নি'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in-flight growth write survives tab refresh', (tester) async {
    final repository = _GrowthRepository()..saveGate = Completer<void>();
    Widget page(int token) => MaterialApp(
          home: Scaffold(
            body: GrowthPage(
              repository: repository,
              day: DateTime(2026, 10, 26),
              refreshToken: token,
            ),
          ),
        );
    await tester.pumpWidget(page(0));
    await tester.pump();
    final checkbox = find.widgetWithText(
        CheckboxListTile, 'ইস্তিগফার ও মাইন্ডফুল জিকির করেছি');
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pump();
    expect(find.text('পরিবর্তন সংরক্ষণ হচ্ছে…'), findsOneWidget);

    await tester.pumpWidget(page(1));
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
    expect(find.text('পরিবর্তন সংরক্ষণ হচ্ছে…'), findsOneWidget);

    repository.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(
        repository.documents['2026-10-26']!['growthData']['iman']['istigfar'],
        isTrue);
    expect(find.text('পরিবর্তন সংরক্ষণ হচ্ছে…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checklist save confirms an earlier failed checkbox edit',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _GrowthRepository()..failSave = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GrowthPage(repository: repository, day: DateTime(2026, 10, 26)),
      ),
    ));
    await tester.pump();
    await tester.tap(find.widgetWithText(
        CheckboxListTile, 'ইস্তিগফার ও মাইন্ডফুল জিকির করেছি'));
    await tester.pumpAndSettle();
    expect(find.text('পরিবর্তন সংরক্ষিত হয়নি'), findsOneWidget);

    repository.failSave = false;
    await tester.tap(find.byTooltip('ইমান চেকলিস্ট সম্পাদনা'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('আইটেম যোগ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Daily reflection');
    await tester.tap(find.text('ঠিক আছে'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();
    expect(
        repository.documents['2026-10-26']!['growthData']['iman']['istigfar'],
        isTrue);
    expect(find.text('পরিবর্তন সংরক্ষিত হয়নি'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _GrowthRepository extends AppRepository {
  _GrowthRepository() : super(uid: 'test-user', firebaseReady: false);

  GrowthChecklistConfig config = GrowthChecklistConfig.defaults();
  final Map<String, Map<String, dynamic>> documents = {};
  final Map<String, Map<String, dynamic>> prayers = {};
  bool failSave = false;
  bool failPrayerRead = false;
  Completer<void>? saveGate;

  @override
  Future<GrowthChecklistConfig> loadGrowthChecklistConfig() async => config;

  @override
  Future<String?> loadUserType() async => 'student';

  @override
  Future<Map<String, dynamic>?> loadGrowth(String date) async =>
      documents[date];

  @override
  Future<Map<String, dynamic>?> loadPrayerDocument(String date) async {
    if (failPrayerRead) throw StateError('Simulated prayer read failure');
    return prayers[date];
  }

  @override
  Future<void> saveGrowth({
    required String date,
    required String userType,
    required Map<String, bool> iman,
    required Map<String, bool> life,
    bool updatePreferredType = true,
    GrowthChecklistSnapshot? checklistSnapshot,
    GrowthChecklistConfig? checklistConfig,
    bool prayerLinked = false,
  }) async {
    if (saveGate case final gate?) await gate.future;
    if (failSave) throw StateError('Simulated write failure');
    if (checklistConfig != null) config = checklistConfig;
    documents[date] = {
      'userType': userType,
      'growthData': {'iman': iman, 'life': life},
      'prayerLinked': prayerLinked,
      if (checklistSnapshot != null)
        'checklistItems': checklistSnapshot.toMap(),
    };
  }
}
