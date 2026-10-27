import 'models.dart';

bool fivePrayersCompleted(Map<String, dynamic>? prayerDocument) {
  final summary = PrayerSummary.fromDocument(prayerDocument);
  return summary.unlogged == 0 && summary.missed == 0;
}

Map<String, bool> linkedImanValues(
  Map<String, bool> saved,
  bool prayerLinked,
  Map<String, dynamic>? prayerDocument,
) {
  if (!prayerLinked) return saved;
  return {
    ...saved,
    'prayer': fivePrayersCompleted(prayerDocument),
  };
}

Map<String, bool> imanValuesForDocuments(
  Map<String, dynamic>? growthDocument,
  Map<String, dynamic>? prayerDocument,
) =>
    linkedImanValues(
      parseBoolMap(asStringMap(growthDocument?['growthData'])['iman']),
      growthDocument?['prayerLinked'] == true,
      prayerDocument,
    );
