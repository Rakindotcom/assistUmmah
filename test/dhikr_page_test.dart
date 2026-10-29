import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/date_helpers.dart';
import 'package:ummah_assist/src/dhikr_progress.dart';
import 'package:ummah_assist/src/pages/dhikr_page.dart';

void main() {
  testWidgets('new custom dhikr can be counted on an already logged day',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _DhikrRepository();
    repository.documents['2026-10-26'] =
        DhikrDay.fromDocument('2026-10-26', null, fallback: repository.goals)
            .change('one', 7)
            .toMap();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('লক্ষ্য সম্পাদনা'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('নতুন লক্ষ্য'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(2), 'আমার যিকির');
    await tester.enterText(find.byType(TextFormField).at(3), '50');
    await tester.ensureVisible(find.text('লক্ষ্য সংরক্ষণ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('লক্ষ্য সংরক্ষণ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('যিকিরসমূহ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('আমার যিকির'));
    await tester.pumpAndSettle();
    final id = repository.goals.items.last.id;
    await tester.tap(find.byKey(ValueKey('dhikr-plus-$id')));
    await tester.pumpAndSettle();
    final counts = repository.documents['2026-10-26']!['counts'] as Map;
    expect(counts['one'], 7);
    expect(counts[id], 1);
  });
  testWidgets('phrase picker changes the active counter without moving counts',
      (tester) async {
    final repository = _DhikrRepository()..goals = DhikrGoals.standard;
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('dhikr-plus-subhanallah')));
    await tester.tap(find.byKey(const ValueKey('dhikr-plus-subhanallah')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('যিকিরসমূহ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('যিকিরসমূহ'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('আল্লাহু আকবার'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('আল্লাহু আকবার'));
    await tester.pumpAndSettle();
    expect(find.text('اللَّهُ أَكْبَرُ'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('dhikr-plus-allahu_akbar')));
    await tester.tap(find.byKey(const ValueKey('dhikr-plus-allahu_akbar')));
    await tester.pumpAndSettle();
    final counts = repository.documents['2026-10-26']!['counts'] as Map;
    expect(counts['subhanallah'], 1);
    expect(counts['allahu_akbar'], 1);
  });

  testWidgets('daily target retries a failed save and preserves existing count',
      (tester) async {
    final repository = _DhikrRepository()..failTargetSave = true;
    repository.documents['2026-10-26'] =
        DhikrDay.fromDocument('2026-10-26', null, fallback: repository.goals)
            .change('one', 7)
            .toMap();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dhikr-target')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '20');
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();
    expect(find.text('লক্ষ্য সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'),
        findsOneWidget);
    repository.failTargetSave = false;
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();
    expect(find.text('৭ / ২০'), findsOneWidget);
    expect((repository.documents['2026-10-26']!['counts'] as Map)['one'], 7);
  });

  testWidgets('reset requires confirmation and failure keeps the saved count',
      (tester) async {
    final repository = _DhikrRepository()..failReset = true;
    repository.documents['2026-10-26'] =
        DhikrDay.fromDocument('2026-10-26', null, fallback: repository.goals)
            .change('one', 7)
            .toMap();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('গণনা রিসেট করুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('বাতিল'));
    await tester.pumpAndSettle();
    expect(find.text('৭ / ১০'), findsOneWidget);
    await tester.tap(find.byTooltip('গণনা রিসেট করুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('রিসেট করুন'));
    await tester.pumpAndSettle();
    expect(
        find.text('গণনা রিসেট করা যায়নি। আবার চেষ্টা করুন।'), findsOneWidget);
    expect(find.text('৭ / ১০'), findsOneWidget);
    repository.failReset = false;
    await tester.tap(find.byTooltip('গণনা রিসেট করুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('রিসেট করুন'));
    await tester.pumpAndSettle();
    expect(find.text('০ / ১০'), findsOneWidget);
  });

  testWidgets(
      'rapid taps preserve remote increments and save to the original day',
      (tester) async {
    final repository = _DhikrRepository()..gate = Completer<void>();
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    final plus = find.byKey(const ValueKey('dhikr-plus-one'));
    await tester.tap(plus);
    await tester.tap(plus);
    await tester.tap(plus);
    await tester.pump();
    expect(find.text('৩ / ১০'), findsOneWidget);
    expect(find.text('গণনা সংরক্ষণ হচ্ছে…'), findsOneWidget);
    expect(
        tester
            .widgetList<IconButton>(find.byType(IconButton))
            .singleWhere((button) => button.tooltip == 'আগের দিন')
            .onPressed,
        isNull);

    // A second device has saved seven counts before our first commit.
    repository.documents['2026-10-26'] =
        DhikrDay.fromDocument('2026-10-26', null, fallback: repository.goals)
            .change('one', 7)
            .toMap();
    repository.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('১০ / ১০'), findsOneWidget);
    expect(repository.savedDates, ['2026-10-26', '2026-10-26', '2026-10-26']);
    expect(find.text('গণনা সংরক্ষণ হচ্ছে…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('midnight waits for queued counts before opening the new day',
      (tester) async {
    final repository = _DhikrRepository()..gate = Completer<void>();
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    final plus = find.byKey(const ValueKey('dhikr-plus-one'));
    await tester.tap(plus);
    await tester.tap(plus);
    await tester.pumpWidget(_app(repository, today: DateTime(2026, 10, 27)));
    expect(find.text('২ / ১০'), findsOneWidget);
    repository.gate!.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repository.savedDates, ['2026-10-26', '2026-10-26']);
    expect(find.text('২৭/১০/২০২৬ • আজ'), findsOneWidget);
    expect(find.text('০ / ১০'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late saves from another account cannot change the new account view',
      (tester) async {
    final old = _DhikrRepository()..gate = Completer<void>();
    await tester.pumpWidget(_app(old));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dhikr-plus-one')));
    final next = _DhikrRepository(uid: 'other-user');
    await tester.pumpWidget(_app(next));
    await tester.pump();
    old.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('০ / ১০'), findsOneWidget);
    expect(next.documents, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed count reverts and can be retried without duplicating a successful count',
      (tester) async {
    final repository = _DhikrRepository()..failNextChange = true;
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    final plus = find.byKey(const ValueKey('dhikr-plus-one'));
    await tester.tap(plus);
    await tester.tap(plus);
    await tester.pump();
    await tester.pump();
    expect(find.text('১ / ১০'), findsOneWidget);
    expect(find.textContaining('১টি পরিবর্তন সংরক্ষণ হয়নি'), findsOneWidget);
    await tester.tap(find.text('আবার সংরক্ষণ'));
    await tester.pump();
    await tester.pump();
    expect(find.text('২ / ১০'), findsOneWidget);
    expect(find.textContaining('পরিবর্তন সংরক্ষণ হয়নি'), findsNothing);
    expect(repository.savedDates.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed goal save retains the draft and existing day keeps its goal',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _DhikrRepository()..failGoalSave = true;
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dhikr-plus-one')));
    await tester.pump();
    await tester.tap(find.byTooltip('লক্ষ্য সম্পাদনা'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '20');
    await tester.tap(find.text('লক্ষ্য সংরক্ষণ'));
    await tester.pump();
    expect(find.text('লক্ষ্য সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'),
        findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    repository.failGoalSave = false;
    await tester.tap(find.text('লক্ষ্য সংরক্ষণ'));
    await tester.pumpAndSettle();
    expect(repository.goals.items.single.target, 20);
    expect(find.text('১ / ১০'), findsOneWidget);
    await tester.tap(find.byTooltip('আগের দিন'));
    await tester.pump();
    await tester.pump();
    expect(find.text('০ / ২০'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('counter and bulk add work on a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _DhikrRepository();
    await tester.pumpWidget(_app(repository, largeText: true));
    await tester.pump();
    await tester.ensureVisible(find.text('সংখ্যা যোগ করুন'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('সংখ্যা যোগ করুন'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '12');
    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();
    expect(find.text('১২ / ১০'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(_DhikrRepository repository,
        {bool largeText = false, DateTime? today}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(largeText ? 1.5 : 1)),
          child: child!),
      home: Scaffold(
          body: DhikrPage(
              repository: repository, today: today ?? DateTime(2026, 10, 26))),
    );

class _DhikrRepository extends AppRepository {
  _DhikrRepository({super.uid = 'test-user'}) : super(firebaseReady: false);
  DhikrGoals goals =
      DhikrGoals(const [DhikrGoal(id: 'one', name: 'My dhikr', target: 10)]);
  final documents = <String, Map<String, dynamic>>{};
  final savedDates = <String>[];
  Completer<void>? gate;
  bool failNextChange = false;
  bool failGoalSave = false;
  bool failTargetSave = false;
  bool failReset = false;

  @override
  bool get canSync => true;
  @override
  Future<DhikrGoals> loadDhikrGoals() async => goals;
  @override
  Future<void> saveDhikrGoals(DhikrGoals value) async {
    if (failGoalSave) throw StateError('Simulated failure');
    goals = value;
  }

  @override
  Future<DhikrDay> saveDhikrGoalsForDay(
      {required String date,
      required DhikrGoals goals,
      required DhikrGoals fallback}) async {
    await saveDhikrGoals(goals);
    final day = DhikrDay.fromDocument(date, documents[date], fallback: fallback)
        .includeGoals(goals);
    if (day.logged) documents[date] = day.toMap();
    return day;
  }

  @override
  Future<Map<String, dynamic>?> loadDhikrDocument(String date) async =>
      documents[date];
  @override
  Future<DhikrDay> setDhikrTarget(
      {required String date,
      required String goalId,
      required int target,
      required DhikrGoals fallback}) async {
    if (failTargetSave) throw StateError('Simulated target write failure');
    final day = DhikrDay.fromDocument(date, documents[date], fallback: fallback)
        .withTarget(goalId, target);
    documents[date] = day.toMap();
    return day;
  }

  @override
  Future<DhikrDay> resetDhikrCount(
      {required String date,
      required String goalId,
      required DhikrGoals fallback}) async {
    if (failReset) throw StateError('Simulated reset failure');
    final day = DhikrDay.fromDocument(date, documents[date], fallback: fallback)
        .reset(goalId);
    documents[date] = day.toMap();
    return day;
  }

  @override
  Future<DhikrDay> changeDhikrCount(
      {required String date,
      required String goalId,
      required int delta,
      required DhikrGoals fallback}) async {
    await gate?.future;
    if (failNextChange) {
      failNextChange = false;
      throw StateError('Simulated failure');
    }
    final day = DhikrDay.fromDocument(date, documents[date], fallback: fallback)
        .change(goalId, delta);
    documents[date] = day.toMap();
    savedDates.add(date);
    return day;
  }

  @override
  Future<DhikrHistory> loadDhikrHistory(
          {required DateTime end,
          required DhikrGoals fallback,
          int dayCount = 7}) async =>
      DhikrHistory(
          end: dateOnly(end),
          documents: documents,
          fallback: fallback,
          dayCount: dayCount);
}
