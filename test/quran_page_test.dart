import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/pages/quran_page.dart';
import 'package:ummah_assist/src/quran_reading.dart';

void main() {
  testWidgets('goal and reading log update daily progress', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _QuranRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.tap(find.text('পরিবর্তন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('মিনিট').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('পৃষ্ঠা').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '5');
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();
    expect(repository.goal.unit, QuranGoalUnit.pages);
    expect(find.text('৫ পৃষ্ঠা'), findsOneWidget);

    await tester.tap(find.text('রিডিং হিসাব লিখুন'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '12');
    await tester.enterText(find.byType(TextFormField).at(1), '6');
    await tester.enterText(
        find.byType(TextFormField).at(2), 'Surah Baqarah 20');
    await tester.tap(find.text('হিসাব সংরক্ষণ'));
    await tester.pumpAndSettle();

    expect(repository.documents['2026-10-26']!['minutes'], 12);
    expect(repository.documents['2026-10-26']!['pages'], 6);
    expect(find.text('৬ / ৫ পৃষ্ঠা • লক্ষ্য পূরণ'), findsOneWidget);
    expect(find.text('শেষ পড়া: Surah Baqarah 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('past reading correction keeps the original goal',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _QuranRepository()
      ..goal = const QuranGoal(unit: QuranGoalUnit.pages, target: 5);
    repository.documents['2026-10-24'] = {
      'date': '2026-10-24',
      'minutes': 8,
      'pages': 2,
      'lastRead': 'Old place',
      'goal': const QuranGoal(unit: QuranGoalUnit.minutes, target: 10).toMap(),
    };
    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.ensureVisible(find.text('২৪/১০/২০২৬'));
    await tester.tap(find.text('২৪/১০/২০২৬'));
    await tester.pump();
    expect(find.text('১০ মিনিট'), findsOneWidget);
    await tester.tap(find.text('হিসাব সংশোধন করুন'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '12');
    await tester.tap(find.text('হিসাব সংরক্ষণ'));
    await tester.pumpAndSettle();

    final saved = QuranReadingDay.fromDocument(
        '2026-10-24', repository.documents['2026-10-24'],
        fallbackGoal: repository.goal);
    expect(saved.goal.unit, QuranGoalUnit.minutes);
    expect(saved.goalMet, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed reading save keeps the form open for retry',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _QuranRepository()..failDaySave = true;
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.tap(find.text('রিডিং হিসাব লিখুন'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '15');
    await tester.tap(find.text('হিসাব সংরক্ষণ'));
    await tester.pump();
    expect(find.text('রিডিং হিসাব সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'),
        findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    repository.failDaySave = false;
    await tester.tap(find.text('হিসাব সংরক্ষণ'));
    await tester.pumpAndSettle();
    expect(repository.documents['2026-10-26']!['minutes'], 15);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed goal save keeps the editor open for retry',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _QuranRepository()..failGoalSave = true;
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.tap(find.text('পরিবর্তন'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '20');
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pump();
    expect(find.text('লক্ষ্য সংরক্ষণ করা যায়নি'), findsOneWidget);
    expect(repository.goal.target, 10);
    repository.failGoalSave = false;
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();
    expect(repository.goal.target, 20);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(_QuranRepository repository) => MaterialApp(
      home: Scaffold(
        body: QuranPage(repository: repository, today: DateTime(2026, 10, 26)),
      ),
    );

class _QuranRepository extends AppRepository {
  _QuranRepository() : super(uid: 'test-user', firebaseReady: false);

  QuranGoal goal = QuranGoal.standard;
  final Map<String, Map<String, dynamic>> documents = {};
  bool failDaySave = false;
  bool failGoalSave = false;

  @override
  bool get canSync => true;

  @override
  Future<QuranGoal> loadQuranGoal() async => goal;

  @override
  Future<void> saveQuranGoal(QuranGoal next, {required DateTime today}) async {
    if (failGoalSave) throw StateError('Simulated goal save failure');
    goal = next;
    final date =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    if (documents[date] case final data?) {
      documents[date] = {...data, 'goal': goal.toMap()};
    }
  }

  @override
  Future<Map<String, dynamic>?> loadQuranDocument(String date) async =>
      documents[date];

  @override
  Future<void> saveQuranDay(QuranReadingDay day) async {
    if (failDaySave) throw StateError('Simulated save failure');
    documents[day.date] = day.toMap();
  }

  @override
  Future<QuranHistory> loadQuranHistory({
    required DateTime end,
    required QuranGoal fallbackGoal,
    int dayCount = 7,
  }) async =>
      QuranHistory.fromDocuments(
        end: end,
        dayCount: dayCount,
        documents: documents,
        fallbackGoal: fallbackGoal,
      );
}
