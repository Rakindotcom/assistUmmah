import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/home_shell.dart';
import 'package:ummah_assist/src/prayer_times_service.dart';
import '../test/support/native_ui_channels.dart';
import 'ui_preview_repository.dart';

void main() {
  testWidgets('render home prayer services and offline duas on a phone',
      (tester) async {
    configureNativeUiChannels();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    for (final font in [
      ('AnekBangla', 'assets/fonts/AnekBangla.ttf'),
      ('NotoNaskhArabic', 'assets/fonts/NotoNaskhArabic.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf')
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = tz.TZDateTime(
        PrayerTimeService.location('Asia/Dhaka'), 2026, 10, 29, 12, 30);
    final repository = UiPreviewRepository(today: day);
    await PrayerTimeStore(repository.uid).save(PrayerTimeConfig(
        latitude: 23.81,
        longitude: 90.41,
        placeName: 'ঢাকা',
        timeZoneId: 'Asia/Dhaka'));
    await tester.pumpWidget(RepaintBoundary(
        key: const Key('home-preview'),
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            locale: AppLocalization.locale,
            supportedLocales: AppLocalization.supportedLocales,
            localizationsDelegates: AppLocalization.delegates,
            home: HomeShell(
                firebaseReady: true,
                repository: repository,
                user: null,
                clock: () => day))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await precacheImage(
          const ResizeImage(AssetImage('assets/brand/app_icon.png'), width: 34),
          tester.element(find.byType(HomeShell)));
    });
    await tester.pump();
    final semantics = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
    await _capture(tester, 'home-phone');
    await Scrollable.ensureVisible(tester.element(find.text('নামাজের হিসাব')),
        alignment: 0.1);
    await tester.pumpAndSettle();
    await _capture(tester, 'home-daily-phone');
    await tester.ensureVisible(find.byKey(const Key('home-fasting')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-fasting')));
    await tester.pumpAndSettle();
    await _capture(tester, 'fasting-phone');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('home-dua')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-dua')));
    await tester.pumpAndSettle();
    await _capture(tester, 'dua-library-phone');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('home-preview')));
  await tester.runAsync(() async {
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('.local/previews');
    await folder.create(recursive: true);
    await File('${folder.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}
