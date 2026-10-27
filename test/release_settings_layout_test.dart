import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/pages/settings_page.dart';
import 'support/native_ui_channels.dart';

void main() {
  testWidgets(
      'native account and diagnostic controls fit at 320px with large text',
      (tester) async {
    configureNativeUiChannels();
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const UmmahAssistApp(
        firebaseReady: false,
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(
                    size: Size(320, 720), textScaler: TextScaler.linear(1.6)),
                child: SettingsPage(
                    repository:
                        AppRepository(uid: 'demo', firebaseReady: false),
                    user: null,
                    firebaseReady: true)))));
    await tester.pumpAndSettle();
    expect(find.text('সমস্যার রিপোর্ট পাঠান'), findsOneWidget);
    expect(find.text('অ্যাকাউন্ট মুছে ফেলুন'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('অ্যাকাউন্ট মুছে ফেলুন'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
