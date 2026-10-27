import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/dashboard_summary.dart';
import 'package:ummah_assist/src/models.dart';

void main() {
  test('custom checklist configuration round-trips per profile', () {
    final base = GrowthChecklistConfig.defaults();
    final changed = base.withItems('life', 'student', [
      const ChecklistItem('customStudy', 'Read a chapter'),
    ]);
    final restored = GrowthChecklistConfig.fromMap(changed.toMap());

    expect(restored.lifeFor('student').single.label, 'Read a chapter');
    expect(restored.lifeFor('professional').length,
        lifeChecklists['professional']!.length);
    expect(restored.iman.length, imanChecklist.length);
  });

  test('saved item snapshots preserve historical scores after template edits',
      () {
    final day = {
      'userType': 'student',
      'growthData': {
        'iman': {'customDhikr': true},
        'life': {'customStudy': true},
      },
      'checklistItems': const GrowthChecklistSnapshot(
        iman: [ChecklistItem('customDhikr', 'Dhikr')],
        life: [ChecklistItem('customStudy', 'Study')],
      ).toMap(),
    };
    final changedConfig = GrowthChecklistConfig.defaults().withItems(
      'iman',
      'student',
      [const ChecklistItem('other', 'Different item')],
    );

    expect(changedConfig.iman.single.key, 'other');
    final summary = DashboardSummary.fromDocuments(growth: day);
    expect(summary.imanScore, 100);
    expect(summary.lifeScore, 100);
    expect(summary.overallScore, 100);
  });

  test('legacy days still use the original built-in checklist', () {
    final summary = DashboardSummary.fromDocuments(growth: {
      'userType': 'student',
      'growthData': {
        'iman': {'istigfar': true},
        'life': {'deepStudy': true},
      },
    });
    expect(summary.imanScore, 20);
    expect(summary.lifeScore, 20);
  });

  test('invalid and duplicate checklist items are ignored', () {
    final items = parseChecklistItems([
      {'key': 'safe', 'label': ' First '},
      {'key': 'safe', 'label': 'Duplicate'},
      {'key': 'bad.key', 'label': 'Unsafe key'},
      {'key': 'empty', 'label': '   '},
    ]);
    expect(items.map((item) => item.label), ['First']);
  });
}
