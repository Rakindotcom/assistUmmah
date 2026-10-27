import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_bootstrap.dart';

void main() {
  testWidgets('startup failure shows recovery and retry without a blank screen',
      (tester) async {
    var attempts = 0;
    final retry = Completer<void>();
    await tester.pumpWidget(AppBootstrap(initialize: () {
      attempts++;
      if (attempts == 1) {
        return Future<void>.error(
            StateError('Synthetic initialization failure'));
      }
      return retry.future;
    }));
    await tester.pump();
    expect(tester.takeException(), isStateError);
    expect(find.text('অ্যাপ চালু করা যায়নি'), findsOneWidget);
    await tester.tap(find.text('আবার চেষ্টা করুন'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    retry.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
