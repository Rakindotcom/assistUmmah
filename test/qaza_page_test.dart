import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';
import 'package:ummah_assist/src/pages/qaza_page.dart';
import 'package:ummah_assist/src/qaza_backlog.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('prayer page opens qaza from every recorded date', (
    tester,
  ) async {
    final repository = _QazaRepository();
    repository.documents.addAll({
      '2024-01-02': _missed('dhuhr'),
      '2026-10-24': _missed('fajr'),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrayerPage(
            repository: repository,
            day: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final link = find.text('সব দিনের কাযা');
    await tester.ensureVisible(link);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(link);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('২ ওয়াক্ত কাযা বাকি'), findsOneWidget);
    expect(find.text('২৪/১০/২০২৬'), findsOneWidget);
    expect(find.text('০২/০১/২০২৪'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the backlog waits for a pending prayer save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _QazaRepository()..pendingSave = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrayerPage(
            repository: repository,
            day: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final selector = find.byKey(const ValueKey('prayer_state_fajr'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('মিস হয়েছে').last);
    await tester.pump();

    final link = find.text('সব দিনের কাযা');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pump();
    expect(find.text('কাযার তালিকা'), findsNothing);

    repository.pendingSave!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('১ ওয়াক্ত কাযা বাকি'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completing qaza removes only the selected prayer', (
    tester,
  ) async {
    final repository = _QazaRepository();
    repository.documents['2026-10-24'] = {
      'prayers': {
        'fajr': {'state': 'missed'},
        'dhuhr': {'state': 'missed'},
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QazaPage(
            repository: repository,
            today: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('২ ওয়াক্ত কাযা বাকি'), findsOneWidget);

    await tester.tap(find.text('কাযা সম্পন্ন').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.completedId, '2026-10-24:fajr');
    expect(find.text('১ ওয়াক্ত কাযা বাকি'), findsOneWidget);
    expect(find.text('যুহর'), findsOneWidget);
    expect(
      prayerStatusesFromDocument(repository.documents['2026-10-24'])['fajr']
          ?.state,
      PrayerState.madeUp,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed completion keeps the backlog item visible', (
    tester,
  ) async {
    final repository = _QazaRepository()..failCompletion = true;
    repository.documents['2026-10-24'] = _missed('fajr');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QazaPage(
            repository: repository,
            today: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('কাযা সম্পন্ন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('১ ওয়াক্ত কাযা বাকি'), findsOneWidget);
    expect(find.text('কাযা সম্পন্ন করা যায়নি। আবার চেষ্টা করুন।'),
        findsOneWidget);
  });

  testWidgets('refresh failure keeps the last backlog visible for retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _QazaRepository();
    repository.documents['2026-10-24'] = _missed('fajr');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QazaPage(repository: repository, today: DateTime(2026, 10, 25)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('১ ওয়াক্ত কাযা বাকি'), findsOneWidget);

    final gate = Completer<void>();
    repository.loadGate = gate.future;
    repository.failLoad = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('১ ওয়াক্ত কাযা বাকি'), findsOneWidget);
    expect(find.text('ফজর'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'কাযা সম্পন্ন'))
            .onPressed,
        isNull);

    gate.complete();
    await tester.pump();
    expect(find.text('নতুন তালিকা লোড করা যায়নি'), findsOneWidget);
    expect(find.text('ফজর'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'কাযা সম্পন্ন'))
            .onPressed,
        isNotNull);

    repository.failLoad = false;
    await tester.tap(find.text('রিট্রাই'));
    await tester.pumpAndSettle();
    expect(find.text('নতুন তালিকা লোড করা যায়নি'), findsNothing);
    expect(find.text('১ ওয়াক্ত কাযা বাকি'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale completion refreshes instead of overwriting a correction',
      (
    tester,
  ) async {
    final repository = _QazaRepository();
    repository.documents['2026-10-24'] = _missed('fajr');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QazaPage(
            repository: repository,
            today: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    repository.documents['2026-10-24'] = {
      'prayers': {
        'fajr': {'state': 'prayed'},
      },
    };

    await tester.tap(find.text('কাযা সম্পন্ন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('কোনো মিসড নামাজ চিহ্নিত নেই'), findsOneWidget);
    expect(find.text('এই নামাজের অবস্থা অন্য কোথাও বদলে গেছে'), findsOneWidget);
    expect(repository.completedId, isNull);
  });
}

Map<String, dynamic> _missed(String key) => {
      'prayers': {
        key: {'state': 'missed'},
      },
    };

class _QazaRepository extends AppRepository {
  _QazaRepository() : super(uid: 'test-user', firebaseReady: false);

  final Map<String, Map<String, dynamic>> documents = {};
  String? completedId;
  bool failCompletion = false;
  Completer<void>? pendingSave;
  Future<void>? loadGate;
  bool failLoad = false;

  @override
  bool get canSync => true;

  @override
  Future<Map<String, dynamic>?> loadPrayerDocument(String date) async =>
      documents[date];

  @override
  Future<void> savePrayerStatus({
    required String date,
    required String prayerKey,
    required PrayerStatus status,
  }) async {
    await pendingSave?.future;
    final document = documents.putIfAbsent(date, () => {});
    document['prayers'] = {
      ...asStringMap(document['prayers']),
      prayerKey: status.toMap(),
    };
  }

  @override
  Future<QazaBacklog> loadQazaBacklog({DateTime? today}) async {
    final gate = loadGate;
    if (gate != null) await gate;
    if (failLoad) throw StateError('Simulated backlog read failure');
    return QazaBacklog.fromDocuments(
      documents,
      today: today ?? DateTime(2026, 10, 26),
    );
  }

  @override
  Future<bool> completeQazaIfMissed({
    required String date,
    required String prayerKey,
  }) async {
    if (failCompletion) throw StateError('Simulated write failure');
    final document = documents[date];
    if (prayerStatusesFromDocument(document)[prayerKey]?.state !=
        PrayerState.missed) {
      return false;
    }
    completedId = '$date:$prayerKey';
    document!['prayers'] = {
      ...asStringMap(document['prayers']),
      prayerKey: const PrayerStatus(state: PrayerState.madeUp).toMap(),
    };
    return true;
  }
}
