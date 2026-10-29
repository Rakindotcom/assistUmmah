import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/dua_collection.dart';
import 'package:ummah_assist/src/pages/dua_library_page.dart';

void main() {
  setUpAll(() async {
    for (final font in [
      ('AnekBangla', 'assets/fonts/AnekBangla.ttf'),
      ('NotoNaskhArabic', 'assets/fonts/NotoNaskhArabic.ttf')
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  test('search handles Bengali digits and unvowelled Arabic', () {
    expect(quranDuas.where((d) => d.matches('২০:১১৪')).single.id, 'knowledge');
    expect(quranDuas.where((d) => d.matches('زدني')).single.id, 'knowledge');
    expect(quranDuas.where((d) => d.matches('বাবা-মা')).single.id, 'parents');
    expect(quranDuas.where((d) => d.matches('unmatched text')), isEmpty);
  });

  test('daily dua is stable for the date and copied text keeps its source', () {
    final dua = duaForDay(DateTime(2026, 10, 29));
    expect(duaForDay(DateTime(2026, 10, 29, 23)), same(dua));
    expect(dua.copyText, contains(dua.sourceUrl));
    expect(dua.copyText, contains('দোয়ার অংশ'));
  });

  testWidgets(
      'offline search opens a full dua and copies Arabic meaning and reference',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: const Scaffold(body: DuaLibraryPage())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '২০:১১৪');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('জ্ঞান বৃদ্ধির দোয়া'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('জ্ঞান বৃদ্ধির দোয়া'));
    await tester.pumpAndSettle();
    expect(find.byType(DuaDetailPage), findsOneWidget);
    await tester.ensureVisible(find.text('দোয়া কপি করুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('দোয়া কপি করুন'));
    await tester.pumpAndSettle();
    expect(copied, contains('رَبِّ زِدْنِي عِلْمًا'));
    expect(copied, contains('https://quran.com/20/114'));
    expect(copied, contains('আমার জ্ঞান বাড়িয়ে দিন'));
    expect(tester.takeException(), isNull);
  });
}
