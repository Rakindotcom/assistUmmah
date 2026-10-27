import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/quran_reading.dart';

void main() {
  test('goal parsing validates unit and target', () {
    expect(QuranGoal.fromMap({'unit': 'pages', 'target': 5}).unit,
        QuranGoalUnit.pages);
    expect(QuranGoal.fromMap({'unit': 'pages', 'target': 5}).target, 5);
    expect(QuranGoal.fromMap({'unit': 'pages', 'target': -3}).target, 10);
    expect(QuranGoal.fromMap({'unit': 'unknown', 'target': 50}).target, 10);
    expect(const QuranGoal(unit: QuranGoalUnit.minutes, target: 1441).valid,
        isFalse);
  });

  test('daily goal snapshot survives a later goal change', () {
    final document = {
      'minutes': 12,
      'pages': 2,
      'lastRead': 'Surah Baqarah 20',
      'goal': {'unit': 'minutes', 'target': 10},
    };
    final day = QuranReadingDay.fromDocument(
      '2026-10-24',
      document,
      fallbackGoal: const QuranGoal(unit: QuranGoalUnit.pages, target: 5),
    );
    expect(day.goal.unit, QuranGoalUnit.minutes);
    expect(day.goalMet, isTrue);
    expect(day.lastRead, 'Surah Baqarah 20');
    expect(day.fraction, 1);
  });

  test('history separates missing days from a logged zero', () {
    final history = QuranHistory.fromDocuments(
      end: DateTime(2026, 11, 1),
      dayCount: 3,
      fallbackGoal: QuranGoal.standard,
      documents: {
        '2026-10-31': {
          'minutes': 0,
          'pages': 0,
          'goal': {'unit': 'minutes', 'target': 10},
        },
        '2026-11-01': {
          'minutes': 15,
          'pages': 3,
          'goal': {'unit': 'minutes', 'target': 10},
        },
      },
    );
    expect(history.days.first.date, '2026-10-30');
    expect(history.days.first.logged, isFalse);
    expect(history.days[1].logged, isTrue);
    expect(history.days[1].goalMet, isFalse);
    expect(history.loggedDays, 2);
    expect(history.goalsMet, 1);
    expect(history.totalMinutes, 15);
    expect(history.totalPages, 3);
  });
}
