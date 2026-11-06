import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'native_ui_channels.dart';

/// Protocol test double, including iOS eviction at the 65th pending request.
/// It does not establish OS delivery, Doze, reboot or hardware permission UX.
class TaskNotificationPlatform {
  final calls = <MethodCall>[];
  final pending = <int, Map<String, Object?>>{};
  final displayed = <int, Map<String, Object?>>{};
  bool permission = true, exact = true;
  Future<void> Function(MethodCall)? intercept;

  void install({TargetPlatform platform = TargetPlatform.android}) {
    debugDefaultTargetPlatformOverride = platform;
    configureNativeUiChannels();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      calls.add(call);
      await intercept?.call(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'areNotificationsEnabled':
        case 'requestNotificationsPermission':
        case 'requestPermissions':
          return permission;
        case 'canScheduleExactNotifications':
          return exact;
        case 'checkPermissions':
          return {
            'isEnabled': permission,
            'isAlertEnabled': permission,
            'isBadgeEnabled': permission,
            'isSoundEnabled': permission
          };
        case 'pendingNotificationRequests':
          return pending.values.toList();
        case 'getActiveNotifications':
          return displayed.values.toList();
        case 'cancelAll':
          pending.clear();
          displayed.clear();
          return null;
        case 'cancel':
          final id = call.arguments is Map
              ? (call.arguments as Map)['id']
              : call.arguments;
          pending.remove(id);
          displayed.remove(id);
          return null;
        case 'zonedSchedule':
          final args = call.arguments as Map;
          final id = args['id'] as int;
          pending.remove(id);
          pending[id] = {
            'id': id,
            'title': args['title'],
            'body': args['body'],
            'payload': args['payload']
          };
          if (platform == TargetPlatform.iOS && pending.length > 64) {
            pending.remove(pending.keys.first);
          }
          return null;
        default:
          throw StateError('Unexpected notification call ${call.method}');
      }
    });
  }
}
