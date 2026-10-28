import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';

void main() {
  testWidgets('returning to Prayer loads another device change',
      (tester) async {
    final repository = _PrayerRepository();
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    expect(_fajr(tester), PrayerState.unlogged);

    await tester.pumpWidget(_page(repository, active: false));
    repository.prayers['fajr'] = const PrayerStatus(state: PrayerState.prayed);
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    expect(_fajr(tester), PrayerState.prayed);
  });

  testWidgets('active Prayer refreshes after app resume', (tester) async {
    final repository = _PrayerRepository();
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    repository.prayers['fajr'] = const PrayerStatus(state: PrayerState.missed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_fajr(tester), PrayerState.missed);
  });

  testWidgets('phone pull-to-refresh reloads Prayer status', (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _PrayerRepository();
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    repository.prayers['fajr'] = const PrayerStatus(state: PrayerState.prayed);
    await tester.drag(find.byType(ListView), const Offset(0, 360));
    await tester.pumpAndSettle();
    expect(repository.reads, 2);
    expect(_fajr(tester), PrayerState.prayed);
  });

  testWidgets('late Prayer response cannot replace a newer response',
      (tester) async {
    final repository = _DeferredPrayerRepository();
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    await tester.pumpWidget(_page(repository, active: false));
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pumpWidget(_page(repository, active: false));
    await tester.pumpWidget(_page(repository, active: true));
    expect(repository.refreshes, hasLength(2));

    repository.refreshes[1].complete(_document(PrayerState.prayed));
    await tester.pump();
    expect(_fajr(tester), PrayerState.prayed);
    repository.refreshes[0].complete(_document(PrayerState.missed));
    await tester.pump();
    expect(_fajr(tester), PrayerState.prayed);
  });

  testWidgets('failed Prayer refresh retains last status and retry',
      (tester) async {
    final repository = _DeferredPrayerRepository();
    repository.prayers['fajr'] = const PrayerStatus(state: PrayerState.prayed);
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    await tester.pumpWidget(_page(repository, active: false));
    await tester.pumpWidget(_page(repository, active: true));
    expect(_fajr(tester), PrayerState.prayed);
    repository.refreshes.single.completeError(StateError('network'));
    await tester.pump();
    expect(_fajr(tester), PrayerState.prayed);
    expect(find.text('সর্বশেষ নামাজের হিসাব আনা যায়নি'), findsOneWidget);
    expect(find.text('রিট্রাই'), findsOneWidget);
  });

  testWidgets('Prayer refresh waits for a pending status save', (tester) async {
    final repository = _DelayedSavePrayerRepository();
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('prayer_state_fajr')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('পড়া হয়েছে').last);
    await tester.pump();
    expect(_fajr(tester), PrayerState.prayed);
    expect(find.text('নামাজের হিসাব সংরক্ষণ হচ্ছে…'), findsOneWidget);
    await tester.pumpWidget(_page(repository, active: false));
    await tester.pumpWidget(_page(repository, active: true));
    expect(repository.reads, 1);

    repository.saveGate.complete();
    await tester.pump();
    await tester.pump();
    expect(repository.reads, 2);
    expect(_fajr(tester), PrayerState.prayed);
    expect(find.text('নামাজের হিসাব সংরক্ষণ হচ্ছে…'), findsNothing);
  });
}

Widget _page(_PrayerRepository repository, {required bool active}) =>
    MaterialApp(
      home: Scaffold(
        body: PrayerPage(
          repository: repository,
          day: DateTime(2026, 10, 25),
          historical: true,
          active: active,
        ),
      ),
    );

PrayerState? _fajr(WidgetTester tester) => tester
    .widget<DropdownButton<PrayerState>>(
        find.byKey(const ValueKey('prayer_state_fajr')))
    .value;

Map<String, dynamic> _document(PrayerState state) => {
      'prayers': {
        'fajr': PrayerStatus(state: state).toMap(),
      },
    };

class _PrayerRepository extends AppRepository {
  _PrayerRepository() : super(uid: 'prayer-test', firebaseReady: false);

  final prayers = <String, PrayerStatus>{};
  int reads = 0;

  @override
  bool get canSync => true;

  @override
  Future<Map<String, dynamic>?> loadPrayerDocument(String date) async {
    reads++;
    return {
      'prayers': prayers.map((key, value) => MapEntry(key, value.toMap())),
    };
  }

  @override
  Future<void> savePrayerStatus({
    required String date,
    required String prayerKey,
    required PrayerStatus status,
  }) async {
    prayers[prayerKey] = status;
  }
}

class _DeferredPrayerRepository extends _PrayerRepository {
  int loads = 0;
  final refreshes = <Completer<Map<String, dynamic>?>>[];

  @override
  Future<Map<String, dynamic>?> loadPrayerDocument(String date) {
    loads++;
    if (loads == 1) return super.loadPrayerDocument(date);
    final refresh = Completer<Map<String, dynamic>?>();
    refreshes.add(refresh);
    return refresh.future;
  }
}

class _DelayedSavePrayerRepository extends _PrayerRepository {
  final saveGate = Completer<void>();

  @override
  Future<void> savePrayerStatus({
    required String date,
    required String prayerKey,
    required PrayerStatus status,
  }) async {
    await saveGate.future;
    await super
        .savePrayerStatus(date: date, prayerKey: prayerKey, status: status);
  }
}
