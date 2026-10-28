import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/pages/settings_page.dart';
import 'support/native_ui_channels.dart';

void main() {
  testWidgets(
      'daily reminder save disables duplicate changes and recovers after failure',
      (tester) async {
    configureNativeUiChannels();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async => switch (call.method) {
                  'initialize' || 'requestNotificationsPermission' => true,
                  'zonedSchedule' || 'cancel' => null,
                  _ => throw StateError(
                      'Unexpected notification call ${call.method}'),
                });
    final repository = _SettingsRepository();
    await tester.pumpWidget(UmmahAssistApp(
        firebaseReady: false,
        home: Scaffold(
            body: SettingsPage(
                repository: repository, user: null, firebaseReady: false))));
    await tester.pumpAndSettle();
    final control = find.widgetWithText(SwitchListTile, 'দৈনিক রিমাইন্ডার');
    await tester.ensureVisible(control);
    await tester.tap(control);
    for (var i = 0; i < 20 && repository.requests == 0; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(repository.requests, 1);
    expect(tester.widget<SwitchListTile>(control).onChanged, isNull);
    expect(find.text('রিমাইন্ডার আপডেট হচ্ছে…'), findsOneWidget);
    await tester.tap(control);
    expect(repository.requests, 1);
    repository.pending.completeError(StateError('network'));
    await tester.pumpAndSettle();
    expect(find.text('রিমাইন্ডার আপডেট করা যায়নি'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(control).onChanged, isNotNull);
    expect(tester.widget<SwitchListTile>(control).value, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}

class _SettingsRepository extends AppRepository {
  _SettingsRepository() : super(uid: 'settings-test', firebaseReady: false);
  final pending = Completer<void>();
  int requests = 0;
  @override
  Future<Map<String, dynamic>?> loadSettings() async => null;
  @override
  Future<void> saveNotificationSettings(Map<String, bool> notifications) {
    requests++;
    return pending.future;
  }
}
