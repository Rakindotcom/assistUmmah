import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/date_helpers.dart';
import 'package:ummah_assist/src/progress_trends.dart';
import 'package:ummah_assist/src/pages/trends_page.dart';

void main() {
  test('trends distinguish missing days from recorded zero progress', () {
    final trends = ProgressTrends.fromDocuments(
      end: DateTime(2026, 11, 2),
      dayCount: 5,
      prayers: {
        '2026-10-31': {
          'prayers': {
            'fajr': {'state': 'missed'},
          },
        },
        '2026-11-02': {
          'prayers': {
            for (final key in ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'])
              key: {'state': 'prayed'},
          },
        },
      },
      growth: {
        '2026-11-02': {
          'userType': 'student',
          'prayerLinked': true,
          'growthData': {
            'iman': {'prayer': false},
            'life': {'customLife': true},
          },
          'checklistItems': {
            'iman': [
              {'key': 'prayer', 'label': 'Prayer'},
            ],
            'life': [
              {'key': 'customLife', 'label': 'Life'},
            ],
          },
        },
      },
    );

    expect(trends.days.map((day) => dateKey(day.date)), [
      '2026-10-29',
      '2026-10-30',
      '2026-10-31',
      '2026-11-01',
      '2026-11-02',
    ]);
    expect(trends.days.first.prayerLogged, isFalse);
    expect(trends.days.first.overallScore, isNull);
    expect(trends.days[2].prayerLogged, isTrue);
    expect(trends.days[2].completedPrayers, 0);
    expect(trends.days.last.completedPrayers, 5);
    expect(trends.days.last.overallScore, 100);

    final window = trends.window(0, 5);
    expect(window.prayerLoggedDays, 2);
    expect(window.completedPrayers, 5);
    expect(window.missedPrayers, 1);
    expect(window.growthLoggedDays, 1);
    expect(window.averageGrowth, 100);
  });

  test('window with no growth log has no average', () {
    final trends = ProgressTrends.fromDocuments(
      end: DateTime(2026, 10, 26),
      dayCount: 2,
      prayers: const {},
      growth: const {},
    );
    expect(trends.window(0, 2).averageGrowth, isNull);
  });

  test('completed-week comparison excludes the partial current day', () {
    Map<String, dynamic> growth(bool done) => {
          'growthData': {
            'iman': {'one': done},
            'life': {'two': done},
          },
          'checklistItems': {
            'iman': [
              {'key': 'one', 'label': 'One'},
            ],
            'life': [
              {'key': 'two', 'label': 'Two'},
            ],
          },
        };
    final trends = ProgressTrends.fromDocuments(
      end: DateTime(2026, 10, 26),
      dayCount: 30,
      prayers: const {},
      growth: {
        for (final day in [12, 13, 14]) '2026-10-$day': growth(false),
        for (final day in [19, 20, 21]) '2026-10-$day': growth(true),
        '2026-10-26': growth(false),
      },
    );
    final previous = trends.window(15, 7);
    final recent = trends.window(22, 7);
    expect(previous.growthLoggedDays, 3);
    expect(previous.averageGrowth, 0);
    expect(recent.growthLoggedDays, 3);
    expect(recent.averageGrowth, 100);
    expect(trends.days.last.overallScore, 0);
  });

  testWidgets('trend grid and day detail work on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _TrendRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TrendsPage(
          repository: repository,
          today: DateTime(2026, 10, 26),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('গ্রোথের গড়: হিসাব নেই'), findsOneWidget);
    await tester.tap(find.text('৭ দিন'));
    await tester.pump();
    expect(find.text('শেষ ৭ দিনের সারাংশ'), findsOneWidget);
    await tester.ensureVisible(find.text('২৬/১০'));
    await tester.pump();
    await tester.tap(find.text('২৬/১০'));
    await tester.pumpAndSettle();
    expect(find.text('২৬/১০/২০২৬'), findsOneWidget);
    expect(find.text('নামাজের হিসাব নেই'), findsOneWidget);
    await tester.ensureVisible(find.text('দিনপঞ্জিতে খুলুন'));
    await tester.tap(find.text('দিনপঞ্জিতে খুলুন'));
    await tester.pumpAndSettle();
    expect(find.text('২৬/১০/২০২৬ • আজ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TrendRepository extends AppRepository {
  _TrendRepository() : super(uid: 'test-user', firebaseReady: false);

  @override
  bool get canSync => true;

  @override
  Future<ProgressTrends> loadProgressTrends({
    required DateTime end,
    int dayCount = 30,
  }) async =>
      ProgressTrends.fromDocuments(
        end: end,
        dayCount: dayCount,
        prayers: const {},
        growth: const {},
      );

  @override
  Future<Map<String, dynamic>?> loadPrayerDocument(String date) async => null;

  @override
  Future<Map<String, dynamic>?> loadGrowth(String date) async => null;
}
