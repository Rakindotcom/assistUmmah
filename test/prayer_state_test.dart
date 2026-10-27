import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/models.dart';

void main() {
  test('legacy false remains unlogged while legacy true remains prayed', () {
    expect(
      PrayerStatus.fromMap({'prayed': false}).state,
      PrayerState.unlogged,
    );
    final prayed = PrayerStatus.fromMap({'prayed': true, 'jamat': true});
    expect(prayed.state, PrayerState.prayed);
    expect(prayed.jamaat, isTrue);
    expect(
      PrayerStatus.fromMap(
        {'prayed': false},
        legacyQazaCompleted: true,
      ).state,
      PrayerState.madeUp,
    );
  });

  test('explicit states round trip and jamaat applies only to prayed', () {
    for (final state in PrayerState.values) {
      final status = PrayerStatus(state: state);
      expect(PrayerStatus.fromMap(status.toMap()).state, state);
    }
    final prayed = const PrayerStatus(
      state: PrayerState.prayed,
      jamaat: true,
    );
    final madeUp = prayed.copyWith(state: PrayerState.madeUp);
    expect(madeUp.jamaat, isFalse);
    expect(madeUp.toMap()['prayed'], isFalse);
  });

  test('summary counts explicit states without inferring missed prayers', () {
    final summary = PrayerSummary.fromDocument({
      'prayers': {
        'fajr': {'prayed': true, 'jamat': true},
        'dhuhr': {'prayed': false},
        'asr': {'state': 'missed'},
        'maghrib': {'state': 'madeUp'},
      },
    });

    expect(summary.prayed, 1);
    expect(summary.missed, 1);
    expect(summary.madeUp, 1);
    expect(summary.unlogged, 2);
    expect(summary.jamaat, 1);
    expect(summary.anyLogged, isTrue);
    expect(PrayerSummary.fromDocument(null).unlogged, 5);
    expect(PrayerSummary.fromDocument(null).anyLogged, isFalse);
  });

  test('legacy qaza completion is recovered without rewriting old records', () {
    final statuses = prayerStatusesFromDocument({
      'prayers': {
        'fajr': {'prayed': false},
        'dhuhr': {'state': 'missed', 'prayed': false},
      },
      'qazaCompletions': {'fajr': true, 'dhuhr': true},
    });

    expect(statuses['fajr']?.state, PrayerState.madeUp);
    expect(statuses['dhuhr']?.state, PrayerState.missed);
  });
}
