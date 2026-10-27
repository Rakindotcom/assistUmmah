import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/auth/auth_screen.dart';
import 'package:ummah_assist/src/home_shell.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/contacts_page.dart';

import '../tool/ui_preview_repository.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('AnekBangla')
      ..addFont(rootBundle.load('assets/fonts/AnekBangla.ttf'));
    await loader.load();
  });
  setUp(() => SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty());
  final platform = TargetPlatformVariant.only(TargetPlatform.linux);

  test('body and semantic text colors meet normal-text contrast', () {
    for (final pair in const [
      (AppColors.ink, Colors.white),
      (AppColors.muted, AppColors.canvas),
      (AppColors.brand, Colors.white),
      (AppColors.brand, AppColors.brandSoft),
      (AppColors.success, Colors.white),
      (AppColors.warning, Colors.white),
      (AppColors.danger, Colors.white),
      (AppColors.information, Colors.white),
      (Color(0xFFBCD9CA), Color(0xFF173F35)),
      (Color(0xFFD4E7DC), Color(0xFF173F35)),
    ]) {
      final a = pair.$1.computeLuminance();
      final b = pair.$2.computeLuminance();
      expect((math.max(a, b) + 0.05) / (math.min(a, b) + 0.05),
          greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('dashboard controls have labels and large touch targets',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final day = DateTime(2026, 10, 26);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          locale: AppLocalization.locale,
          supportedLocales: AppLocalization.supportedLocales,
          localizationsDelegates: AppLocalization.delegates,
          home: HomeShell(
              firebaseReady: false,
              repository: UiPreviewRepository(today: day),
              user: null,
              clock: () => day)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('২/৫ সময়মতো পড়া হয়েছে'), findsOneWidget);
      expect(
          find.text('০ মিস • ০ কাযা • ৩ হিসাব নেই • ২ জামাতে'), findsOneWidget);
      expect(find.text('১/৩ সম্পন্ন'), findsOneWidget);
      expect(find.text('৫০% সম্পন্ন'), findsOneWidget);
      expect(find.textContaining('2/৫'), findsNothing);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  }, variant: platform);

  testWidgets('sign-in keyboard order starts with email then password',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const AuthScreen()));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText).last)
            .focusNode
            .hasFocus,
        isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platform);

  testWidgets('failed contact save preserves the draft and retries once',
      (tester) async {
    final repository = _FailingContacts();
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ContactsPage(repository: repository))));
    await tester.pump();
    await tester.tap(find.text('যোগাযোগ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'পরিবারের জন্য সময়');
    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();
    expect(find.text('যোগাযোগ সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'),
        findsOneWidget);
    expect(find.text('পরিবারের জন্য সময়'), findsOneWidget);
    expect(repository.contacts['message']!.length, 2);
    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();
    expect(find.text('পরিবারের জন্য সময়'), findsOneWidget);
    expect(repository.contacts['message']!.length, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platform);
}

class _FailingContacts extends UiPreviewRepository {
  _FailingContacts() : super(today: DateTime(2026, 10, 26));
  bool fail = true;
  @override
  Future<Map<String, dynamic>?> changeContacts(
      void Function(Map<String, List<ContactItem>>) apply) async {
    if (fail) {
      fail = false;
      throw StateError('Simulated write failure');
    }
    return super.changeContacts(apply);
  }
}
