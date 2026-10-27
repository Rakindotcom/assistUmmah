import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/qaza_backlog.dart';

void main() {
  test('collects explicit missed prayers across years in date order', () {
    final backlog = QazaBacklog.fromDocuments({
      '2024-01-02': {
        'prayers': {
          'fajr': {'state': 'missed'},
        },
      },
      '2026-10-25': {
        'prayers': {
          'isha': {'state': 'missed'},
          'dhuhr': {'state': 'missed'},
        },
      },
      '2026-10-24': {
        'prayers': {
          'asr': {'state': 'madeUp'},
          'maghrib': {'state': 'missed'},
        },
      },
    }, today: DateTime(2026, 10, 25));

    expect(
      backlog.entries.map((entry) => entry.id),
      [
        '2026-10-25:dhuhr',
        '2026-10-25:isha',
        '2026-10-24:maghrib',
        '2024-01-02:fajr',
      ],
    );
  });

  test('never infers backlog from unlogged or future records', () {
    final backlog = QazaBacklog.fromDocuments({
      '2026-10-24': {
        'prayers': {
          'fajr': {'prayed': false},
          'dhuhr': {'state': 'unlogged'},
          'asr': {'state': 'prayed'},
          'maghrib': {'state': 'madeUp'},
        },
      },
      '2026-10-26': {
        'prayers': {
          'isha': {'state': 'missed'},
        },
      },
      'not-a-date': {
        'prayers': {
          'fajr': {'state': 'missed'},
        },
      },
    }, today: DateTime(2026, 10, 25));

    expect(backlog.entries, isEmpty);
  });
}
