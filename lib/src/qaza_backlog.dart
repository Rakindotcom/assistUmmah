import 'date_helpers.dart';
import 'models.dart';

class QazaEntry {
  const QazaEntry({required this.date, required this.prayerKey});

  final String date;
  final String prayerKey;

  String get id => '$date:$prayerKey';
}

class QazaBacklog {
  QazaBacklog._(List<QazaEntry> entries)
      : entries = List<QazaEntry>.unmodifiable(entries);

  final List<QazaEntry> entries;

  static QazaBacklog fromDocuments(
    Map<String, Map<String, dynamic>> documents, {
    required DateTime today,
  }) {
    final lastDate = dateKey(today);
    final entries = <QazaEntry>[];
    for (final document in documents.entries) {
      final date = document.key;
      final parsed = DateTime.tryParse(date);
      if (parsed == null ||
          dateKey(parsed) != date ||
          date.compareTo(lastDate) > 0) {
        continue;
      }
      final statuses = prayerStatusesFromDocument(document.value);
      for (final key in prayerKeys) {
        if (statuses[key]?.state == PrayerState.missed) {
          entries.add(QazaEntry(date: date, prayerKey: key));
        }
      }
    }
    entries.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0
          ? byDate
          : prayerKeys.indexOf(a.prayerKey).compareTo(
                prayerKeys.indexOf(b.prayerKey),
              );
    });
    return QazaBacklog._(entries);
  }
}
