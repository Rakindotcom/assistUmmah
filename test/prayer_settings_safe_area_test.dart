import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/pages/prayer_time_settings_sheet.dart';
import 'package:ummah_assist/src/prayer_times_service.dart';

void main() {
  testWidgets('prayer settings save stays above three-button navigation',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    PrayerTimeConfig? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            saved = await showModalBottomSheet<PrayerTimeConfig>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => PrayerTimeSettingsSheet(
                initial: PrayerTimeConfig(
                  latitude: 23.81,
                  longitude: 90.41,
                  placeName: 'ঢাকা',
                  timeZoneId: 'Asia/Dhaka',
                ),
              ),
            );
          },
          child: const Text('Open'),
        );
      })),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'সময় সংরক্ষণ করুন');
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(844 - 48));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved?.placeName, 'ঢাকা');
    expect(find.byType(PrayerTimeSettingsSheet), findsNothing);
  });
}
