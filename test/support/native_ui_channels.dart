import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/reminder_service.dart';

/// Native services are stubbed for widget layout tests, not delivery testing.
void configureNativeUiChannels() {
  ReminderService.resetForTesting();
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    IOSFlutterLocalNotificationsPlugin.registerWith();
  } else {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  }
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
      (call) async {
    if (call.method == 'getLocalTimezone') return 'Asia/Dhaka';
    throw UnsupportedError('Unexpected timezone method: ${call.method}');
  });
  messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => switch (call.method) {
            'initialize' ||
            'areNotificationsEnabled' ||
            'canScheduleExactNotifications' =>
              true,
            'checkPermissions' => {
                'isEnabled': true,
                'isAlertEnabled': true,
                'isBadgeEnabled': true,
                'isSoundEnabled': true,
              },
            'cancel' => null,
            _ => throw UnsupportedError(
                'Unexpected notification method: ${call.method}'),
          });
}
