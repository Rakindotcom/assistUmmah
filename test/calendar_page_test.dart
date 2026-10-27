import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/calendar_page.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('a past prayer correction appears in the calendar summary', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPage(
            repository: repository,
            today: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('calendar_previous_day')));
    await tester.pumpAndSettle();
    expect(find.text('২৪/১০/২০২৬'), findsOneWidget);
    expect(find.text('এই দিনে কোনো নামাজের হিসাব লেখা হয়নি'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ListTile, 'নামাজের হিসাব'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'নামাজের হিসাব'));
    await tester.pumpAndSettle();
    expect(find.text('২৪/১০/২০২৬ দিনের হিসাব সংশোধন করুন'), findsOneWidget);

    await _markFajrPrayed(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(repository.savedPrayerDate, '2026-10-24');
    expect(repository.savedPrayerKey, 'fajr');
    expect(find.text('১ পড়া • ০ মিস • ০ কাযা • ৪ হিসাব নেই'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing past growth does not change the current profile type', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPage(
            repository: repository,
            today: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_previous_day')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(ListTile, 'গ্রোথ চেকলিস্ট'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'গ্রোথ চেকলিস্ট'));
    await tester.pumpAndSettle();
    expect(find.text('২৪/১০/২০২৬ দিনের হিসাব সংশোধন করুন'), findsOneWidget);

    await tester.ensureVisible(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(repository.savedGrowthDate, '2026-10-24');
    expect(repository.updatedPreferredType, isFalse);
    expect(find.text('ইমান ২০% • লাইফ ০%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar refreshes after a delayed write completes', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repository = _MemoryRepository()..prayerWriteGate = gate.future;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPage(
            repository: repository,
            today: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_previous_day')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'নামাজের হিসাব'));
    await tester.pumpAndSettle();
    await _markFajrPrayed(tester);
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('এই দিনে কোনো নামাজের হিসাব লেখা হয়নি'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('১ পড়া • ০ মিস • ০ কাযা • ৪ হিসাব নেই'), findsOneWidget);
  });

  testWidgets('calendar date selection works on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPage(
            repository: _MemoryRepository(),
            today: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CalendarDatePicker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();

    expect(find.text('২০/১০/২০২৬'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed past-day save is reported after leaving the editor', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repository = _MemoryRepository()
      ..prayerWriteGate = gate.future
      ..failPrayerWrite = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPage(
            repository: repository,
            today: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_previous_day')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'নামাজের হিসাব'));
    await tester.pumpAndSettle();
    await _markFajrPrayed(tester);
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('২৪/১০/২০২৬: নামাজের ডেটা সিঙ্ক করতে সমস্যা হয়েছে'),
      findsOneWidget,
    );
    expect(find.text('এই দিনে কোনো নামাজের হিসাব লেখা হয়নি'), findsOneWidget);
  });

  testWidgets('switching users clears the previous user’s calendar data', (
    tester,
  ) async {
    final first = _MemoryRepository(uid: 'first-user');
    first._prayers['2026-10-25'] = {
      'prayers': {
        'fajr': {'prayed': true},
      },
    };
    final second = _MemoryRepository(uid: 'second-user');

    Widget app(_MemoryRepository repository) => MaterialApp(
          home: Scaffold(
            body: CalendarPage(
              repository: repository,
              today: DateTime(2026, 10, 25),
            ),
          ),
        );

    await tester.pumpWidget(app(first));
    await tester.pumpAndSettle();
    expect(find.text('১ পড়া • ০ মিস • ০ কাযা • ৪ হিসাব নেই'), findsOneWidget);

    await tester.pumpWidget(app(second));
    await tester.pumpAndSettle();
    expect(find.text('১ পড়া • ০ মিস • ০ কাযা • ৪ হিসাব নেই'), findsNothing);
    expect(find.text('এই দিনে কোনো নামাজের হিসাব লেখা হয়নি'), findsOneWidget);
  });

  testWidgets('prayer selector saves explicit missed and made-up states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _MemoryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrayerPage(
            repository: repository,
            day: DateTime(2026, 10, 24),
            historical: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _selectFajrState(tester, 'মিস হয়েছে');
    expect(repository.savedPrayerStatus?.state, PrayerState.missed);

    await _selectFajrState(tester, 'কাযা আদায়');
    expect(repository.savedPrayerStatus?.state, PrayerState.madeUp);

    await _selectFajrState(tester, 'হিসাব নেই');
    expect(repository.savedPrayerStatus?.state, PrayerState.unlogged);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed prayer edit restores the last saved state', (
    tester,
  ) async {
    final repository = _MemoryRepository()..failPrayerWrite = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrayerPage(
            repository: repository,
            day: DateTime(2026, 10, 24),
            historical: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _selectFajrState(tester, 'মিস হয়েছে');
    final selector = tester.widget<DropdownButton<PrayerState>>(
      find.byKey(const ValueKey('prayer_state_fajr')),
    );
    expect(selector.value, PrayerState.unlogged);
    expect(find.text('নামাজের ডেটা সিঙ্ক করতে সমস্যা হয়েছে'), findsOneWidget);
  });
}

Future<void> _markFajrPrayed(WidgetTester tester) async {
  await _selectFajrState(tester, 'পড়া হয়েছে');
}

Future<void> _selectFajrState(WidgetTester tester, String label) async {
  final selector = find.byKey(const ValueKey('prayer_state_fajr'));
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class _MemoryRepository extends AppRepository {
  _MemoryRepository({super.uid = 'test-user'}) : super(firebaseReady: false);

  final Map<String, Map<String, dynamic>> _prayers = {};
  final Map<String, Map<String, dynamic>> _growth = {};
  String? savedPrayerDate;
  String? savedPrayerKey;
  PrayerStatus? savedPrayerStatus;
  String? savedGrowthDate;
  bool? updatedPreferredType;
  Future<void>? prayerWriteGate;
  bool failPrayerWrite = false;

  @override
  Future<Map<String, dynamic>?> loadPrayerDocument(String date) async =>
      _prayers[date];

  @override
  Future<Map<String, dynamic>?> loadGrowth(String date) async => _growth[date];

  @override
  Future<String?> loadUserType() async => 'student';

  @override
  Future<void> savePrayerStatus({
    required String date,
    required String prayerKey,
    required PrayerStatus status,
  }) async {
    final gate = prayerWriteGate;
    if (gate != null) await gate;
    if (failPrayerWrite) throw StateError('Simulated write failure');
    savedPrayerDate = date;
    savedPrayerKey = prayerKey;
    savedPrayerStatus = status;
    final document = _prayers.putIfAbsent(
      date,
      () => {'prayers': <String, dynamic>{}},
    );
    document['prayers'] = {
      ...asStringMap(document['prayers']),
      prayerKey: status.toMap(),
    };
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
    savedGrowthDate = date;
    updatedPreferredType = updatePreferredType;
    _growth[date] = {
      'userType': userType,
      'growthData': {'iman': iman, 'life': life},
      'prayerLinked': prayerLinked,
      if (checklistSnapshot != null)
        'checklistItems': checklistSnapshot.toMap(),
    };
  }
}
