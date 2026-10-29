import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app.dart';
import 'package:ummah_assist/src/pages/dashboard_page.dart';
import 'package:ummah_assist/src/pages/prayer_time_settings_sheet.dart';

import 'support/native_ui_channels.dart';

void main() {
  setUp(() {
    configureNativeUiChannels();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('shows app title in offline preview', (tester) async {
    await tester.pumpWidget(const UmmahAssistApp(firebaseReady: false));

    expect(find.text('রবের পথে'), findsOneWidget);
    expect(find.byType(DashboardPage), findsOneWidget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('আসসালামু আলাইকুম'), findsOneWidget);
    expect(find.text('এখনো লগ করা হয়নি'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dashboard action opens prayer tracking on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const UmmahAssistApp(firebaseReady: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('নামাজ দেখুন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('নামাজ ট্র্যাকিং'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('আরও'));
    await tester.pump();
    expect(find.text('সেটিংস ও রিপোর্ট'), findsOneWidget);
    await tester.tap(find.text('দিনপঞ্জি'));
    await tester.pump();
    expect(find.text('দিন নির্বাচন করুন'), findsOneWidget);
    await tester.tap(find.byTooltip('আরও পৃষ্ঠায় ফিরুন'));
    await tester.pump();
    await tester.ensureVisible(find.text('যোগাযোগ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('যোগাযোগ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('জরুরি যোগাযোগ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Android system back returns from details to More then Today',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const UmmahAssistApp(firebaseReady: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('আরও'));
    await tester.pump();
    await tester.tap(find.text('কুরআন রিডিং'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('দৈনিক লক্ষ্য'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('সেটিংস ও রিপোর্ট'), findsOneWidget);
    expect(find.text('দৈনিক লক্ষ্য'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('আসসালামু আলাইকুম'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('manual prayer location shows a calculated schedule',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const UmmahAssistApp(firebaseReady: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('নামাজ দেখুন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('সেট করুন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PrayerTimeSettingsSheet), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'স্থানের নাম'),
      'Dhaka',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'অক্ষাংশ'),
      '23.81',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'দ্রাঘিমাংশ'),
      '90.41',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'টাইম জোন'),
      'Asia/Dhaka',
    );
    tester.testTextInput.hide();
    await tester.pump();
    final sheetScroll = find
        .descendant(
          of: find.byType(PrayerTimeSettingsSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(sheetScroll).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.text('সময় সংরক্ষণ করুন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(PrayerTimeSettingsSheet), findsNothing);
    expect(find.text('নামাজের সময় সংরক্ষণ করা যায়নি'), findsNothing);
    expect(find.textContaining('Dhaka • করাচি'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone route transitions ignore actions on inactive tabs',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const UmmahAssistApp(firebaseReady: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('নামাজ দেখুন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final backlog = find.text('সব দিনের কাযা');
    await tester.ensureVisible(backlog);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(backlog);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('কাযার তালিকা'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('নামাজ ট্র্যাকিং'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Dhikr counter opens from More on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const UmmahAssistApp(firebaseReady: false));
    await tester.pump();
    await tester.tap(find.text('আরও'));
    await tester.pump();
    await tester.tap(find.text('যিকিরের লক্ষ্য'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('লক্ষ্য সম্পাদনা'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('dhikr-plus-subhanallah')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('dhikr-plus-subhanallah')));
    await tester.pump();
    expect(find.text('১ / ৩৩'), findsOneWidget);
    await tester.tap(find.byTooltip('আরও পৃষ্ঠায় ফিরুন'));
    await tester.pump();
    expect(find.text('সেটিংস ও রিপোর্ট'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Quran page opens from More and returns to its caller',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const UmmahAssistApp(firebaseReady: false));
    await tester.pump();
    await tester.tap(find.text('আরও'));
    await tester.pump();
    await tester.tap(find.text('কুরআন রিডিং'));
    await tester.pump();
    expect(find.text('দৈনিক লক্ষ্য'), findsOneWidget);
    await tester.tap(find.byTooltip('আরও পৃষ্ঠায় ফিরুন'));
    await tester.pump();
    expect(find.text('সেটিংস ও রিপোর্ট'), findsOneWidget);

    await tester.tap(find.text('গ্রোথ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('কুরআন রিডিং লক্ষ্য'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('কুরআন রিডিং লক্ষ্য'));
    await tester.pump();
    expect(find.text('দৈনিক লক্ষ্য'), findsOneWidget);
    await tester.tap(find.byTooltip('গ্রোথ পৃষ্ঠায় ফিরুন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('গ্রোথ চেকলিস্ট'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
