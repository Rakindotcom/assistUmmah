import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  ReminderService._();

  static final instance = ReminderService._();

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;

  Future<void> _initialize() {
    final pending = _initialization;
    if (pending != null) return pending;
    final future = _initializePlugin();
    _initialization = future;
    return future.catchError((Object error, StackTrace stackTrace) {
      _initialization = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _initializePlugin() async {
    tz.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  Future<bool> sync(
    Map<String, bool> preferences, {
    bool requestPermission = false,
  }) async {
    if (!supported) return false;
    await _initialize();

    if (requestPermission && preferences.values.any((value) => value)) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await (android?.requestNotificationsPermission() ??
          ios?.requestPermissions(alert: true, badge: true, sound: true) ??
          Future<bool?>.value(false));
      if (granted != true) return false;
    }

    for (final reminder in _reminders) {
      await _plugin.cancel(reminder.id);
      if (preferences[reminder.key] == true) {
        await _schedule(reminder);
      }
    }
    return true;
  }

  Future<void> cancelAll() async {
    if (!supported) return;
    await _initialize();
    for (final reminder in _reminders) {
      await _plugin.cancel(reminder.id);
    }
  }

  Future<void> _schedule(_Reminder reminder) async {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      reminder.hour,
    );
    if (!next.isAfter(now)) {
      next = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        reminder.hour,
      );
    }

    await _plugin.zonedSchedule(
      reminder.id,
      reminder.title,
      reminder.body,
      next,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminders',
          'Daily reminders',
          channelDescription: 'Daily task, prayer log, and growth reminders',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}

class _Reminder {
  const _Reminder(this.id, this.key, this.hour, this.title, this.body);

  final int id;
  final String key;
  final int hour;
  final String title;
  final String body;
}

const _reminders = [
  _Reminder(1001, 'tasks', 8, 'আজকের কাজ', 'আজকের কাজের তালিকা দেখে নিন।'),
  _Reminder(
    1002,
    'prayer',
    20,
    'নামাজের হিসাব',
    'আজকের নামাজের হিসাব আপডেট করুন।',
  ),
  _Reminder(
    1003,
    'growth',
    21,
    'গ্রোথ চেকলিস্ট',
    'আজকের গ্রোথ চেকলিস্ট পূরণ করুন।',
  ),
];
