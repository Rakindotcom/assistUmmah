import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/dhikr_progress.dart';

void main() {
  test('changing a daily target preserves all counts and other goals', () {
    final day =
        DhikrDay.fromDocument('2026-10-26', null, fallback: DhikrGoals.standard)
            .change('subhanallah', 12)
            .change('alhamdulillah', 7);
    final updated = day.withTarget('subhanallah', 100);
    expect(updated.counts, day.counts);
    expect(updated.goals.items.first.target, 100);
    expect(updated.goals.items[1].target, 33);
    final reset = updated.reset('subhanallah');
    expect(reset.count('subhanallah'), 0);
    expect(reset.count('alhamdulillah'), 7);
    expect(reset.goals.items.first.target, 100);
    expect(() => day.withTarget('subhanallah', 0), throwsArgumentError);
    expect(() => day.reset('unknown'), throwsArgumentError);
  });

  test('renamed and custom goals do not inherit an unrelated Arabic phrase',
      () {
    expect(DhikrPhrase.forGoal(DhikrGoals.standard.items.first)?.arabic,
        'سُبْحَانَ اللَّهِ');
    expect(
        DhikrPhrase.forGoal(const DhikrGoal(
            id: 'subhanallah', name: 'My own phrase', target: 10)),
        isNull);
  });

  test('new custom phrases join today without changing counted goals', () {
    final day =
        DhikrDay.fromDocument('2026-10-26', null, fallback: DhikrGoals.standard)
            .change('subhanallah', 12);
    final template = DhikrGoals([
      const DhikrGoal(id: 'subhanallah', name: 'Changed', target: 100),
      const DhikrGoal(id: 'custom_one', name: 'My own dhikr', target: 50),
    ]);
    final updated = day.includeGoals(template);
    expect(updated.count('subhanallah'), 12);
    expect(updated.goals.items.first.target, 33);
    expect(updated.goals.items.first.name, 'সুবহানাল্লাহ');
    expect(updated.goals.items.last.id, 'custom_one');
    expect(updated.count('custom_one'), 0);
  });

  test('Bengali goal names use the same character limit as the editor', () {
    final name = List.filled(60, 'কি').join();
    final tooLong = List.filled(61, 'কি').join();
    expect(DhikrGoal(id: 'one', name: name, target: 10).valid, isTrue);
    expect(DhikrGoal(id: 'one', name: tooLong, target: 10).valid, isFalse);
  });

  test('invalid templates cannot silently drop or duplicate goals', () {
    final fallback = DhikrGoals.standard;
    expect(DhikrGoals([]).valid, isFalse);
    expect(DhikrGoals([fallback.items.first, fallback.items.first]).valid,
        isFalse);
    expect(
        DhikrGoals.fromList([
          {'id': 'bad.path', 'name': 'Name', 'target': 10},
        ]),
        same(fallback));
    expect(
        DhikrGoals.fromList([
          {'id': 'valid', 'name': 'Name', 'target': 0},
        ]),
        same(fallback));
  });

  test('daily goals keep their snapshot when the template changes', () {
    final old =
        DhikrGoals(const [DhikrGoal(id: 'one', name: 'Old', target: 3)]);
    final next =
        DhikrGoals(const [DhikrGoal(id: 'two', name: 'New', target: 10)]);
    final saved = DhikrDay.fromDocument('2026-10-25', null, fallback: old)
        .change('one', 3);
    final loaded =
        DhikrDay.fromDocument('2026-10-25', saved.toMap(), fallback: next);
    expect(loaded.goals.items.single.id, 'one');
    expect(loaded.goalsMet, 1);
    expect(loaded.count('one'), 3);
    expect(
        DhikrDay.fromDocument('2026-10-26', null, fallback: next)
            .goals
            .items
            .single
            .id,
        'two');
  });

  test('counter bounds and history distinguish zero from missing', () {
    final zero =
        DhikrDay.fromDocument('2026-10-25', null, fallback: DhikrGoals.standard)
            .change('subhanallah', -1);
    expect(zero.count('subhanallah'), 0);
    final maximum = zero.change('subhanallah', DhikrDay.maxCount);
    expect(() => maximum.change('subhanallah', 1), throwsArgumentError);
    expect(() => zero.change('unknown', 1), throwsArgumentError);
    final history = DhikrHistory(
        end: DateTime(2026, 10, 26),
        documents: {'2026-10-25': zero.toMap()},
        fallback: DhikrGoals.standard);
    expect(history.days.length, 7);
    expect(history.loggedDays, 1);
    expect(history.total, 0);
    expect(history.days.last.logged, isFalse);
    expect(history.days[5].logged, isTrue);
  });
}
