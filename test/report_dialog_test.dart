import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/report_dialog.dart';

void main() {
  testWidgets(
      'report retries in place and distinguishes no records from zero at large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FailingReportRepository();
    await tester.pumpWidget(UmmahAssistApp(
        firebaseReady: false,
        home: Scaffold(
            body: MediaQuery(
          data: const MediaQueryData(
              size: Size(320, 720), textScaler: TextScaler.linear(1.6)),
          child: ReportDialog(
              repository: repository,
              title: 'মাসিক রিপোর্ট',
              start: DateTime(2026, 10),
              end: DateTime(2026, 10, 28)),
        ))));
    await tester.pumpAndSettle();
    expect(
        find.text('রিপোর্ট লোড করা যায়নি। আবার চেষ্টা করুন।'), findsOneWidget);
    await tester.tap(find.text('আবার চেষ্টা করুন'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(repository.requests, 2);
    repository.retry.complete(ReportSummary.empty);
    await tester.pumpAndSettle();
    expect(find.text('হিসাব নেই'), findsNWidgets(3));
    expect(find.text('০%'), findsNothing);
    expect(find.text('গ্রোথের হিসাব রাখা দিন'), findsOneWidget);
    expect(repository.requests, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FailingReportRepository extends AppRepository {
  _FailingReportRepository() : super(uid: 'report-test', firebaseReady: false);
  int requests = 0;
  final retry = Completer<ReportSummary>();
  @override
  bool get canSync => true;
  @override
  Future<ReportSummary> buildReport(
      {required DateTime start, required DateTime end}) async {
    requests++;
    if (requests == 1) throw StateError('network');
    return retry.future;
  }
}
