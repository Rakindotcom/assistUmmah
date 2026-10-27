import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/account/delete_account_page.dart';
import 'package:ummah_assist/src/account/privacy_page.dart';
import 'package:ummah_assist/src/app_theme.dart';

void main() {
  testWidgets(
      'requires acknowledgement and password; sends only one pending request',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: DeleteAccountPage(
            usesPassword: true,
            onDelete: (password) {
              expect(password, 'secret');
              calls++;
              return pending.future;
            })));
    final submit =
        find.widgetWithText(FilledButton, 'স্থায়ীভাবে মুছে ফেলার অনুরোধ করুন');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });
  testWidgets('wrong password retains the form and permits a retry',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: DeleteAccountPage(
            usesPassword: true,
            onDelete: (_) async =>
                throw FirebaseAuthException(code: 'wrong-password'))));
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    final submit = find.byType(FilledButton);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('পাসওয়ার্ড সঠিক নয়। আবার চেষ্টা করুন।'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'bad');
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });
  testWidgets(
      'deletion and bundled privacy fit a narrow screen with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final page in [
      const DeleteAccountPage(usesPassword: false),
      const PrivacyPage()
    ]) {
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!),
          home: page));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.scrollUntilVisible(find.text('নীতির পরিবর্তন'), 500,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('নীতির পরিবর্তন'), findsOneWidget);
  });
}
