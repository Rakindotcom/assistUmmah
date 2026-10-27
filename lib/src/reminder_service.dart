import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'prayer_alerts.dart';
import 'prayer_times_service.dart';

class PrayerAlertScheduleResult {
  const PrayerAlertScheduleResult({
    required this.permissionGranted,
    required this.exact,
    required this.scheduledCount,
  });

  final bool permissionGranted;
  final bool exact;
  final int scheduledCount;
}

class ReminderService {
  ReminderService._();

  static ReminderService _instance = ReminderService._();
  static ReminderService get instance => _instance;

  /// Isolates platform initialization and queued work between widget tests.
  /// Tests must finish pending operations before replacing the service.
  @visibleForTesting
  static void resetForTesting() => _instance = ReminderService._();

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  Future<void> _prayerAlertQueue = Future<void>.value();

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
        android: AndroidInitializationSettings('ic_notification'),
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
      if (!await _notificationPermission(request: true)) return false;
    }

    for (final reminder in _reminders) {
      await _plugin.cancel(reminder.id);
      if (preferences[reminder.key] == true) {
        await _schedule(reminder);
      }
    }
    return true;
  }

  Future<PrayerAlertScheduleResult> syncPrayerAlerts({
    required PrayerTimeConfig? config,
    required PrayerAlertSettings settings,
    bool requestPermission = false,
  }) {
    final operation = _prayerAlertQueue.then(
      (_) => _syncPrayerAlerts(
        config: config,
        settings: settings,
        requestPermission: requestPermission,
      ),
    );
    _prayerAlertQueue = operation.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    return operation;
  }

  Future<PrayerAlertScheduleResult> _syncPrayerAlerts({
    required PrayerTimeConfig? config,
    required PrayerAlertSettings settings,
    required bool requestPermission,
  }) async {
    if (!supported) {
      return const PrayerAlertScheduleResult(
        permissionGranted: false,
        exact: false,
        scheduledCount: 0,
      );
    }
    await _initialize();

    if (!settings.enabled) {
      await _cancelPrayerAlerts();
      return const PrayerAlertScheduleResult(
        permissionGranted: true,
        exact: true,
        scheduledCount: 0,
      );
    }
    if (config == null) {
      await _cancelPrayerAlerts();
      return const PrayerAlertScheduleResult(
        permissionGranted: true,
        exact: true,
        scheduledCount: 0,
      );
    }
    if (!await _notificationPermission(request: requestPermission)) {
      await _cancelPrayerAlerts();
      return const PrayerAlertScheduleResult(
        permissionGranted: false,
        exact: false,
        scheduledCount: 0,
      );
    }

    final now = DateTime.now();
    final plan = PrayerAlertPlanner.upcoming(
      config: config,
      settings: settings,
      now: now,
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    var exact = true;
    if (android != null) {
      exact = await android.canScheduleExactNotifications() ?? false;
      if (!exact && requestPermission) {
        exact = await android.requestExactAlarmsPermission() ?? false;
      }
    }
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    await _cancelPrayerAlerts();
    try {
      for (final alert in plan) {
        final label = prayerLabels[alert.prayerKey] ?? alert.prayerKey;
        await _plugin.zonedSchedule(
          alert.id,
          '$label নামাজের সময়',
          settings.leadMinutes == 0
              ? 'নামাজের সময় হয়েছে।'
              : '${settings.leadMinutes} মিনিট পরে $label নামাজের সময়।',
          alert.time,
          NotificationDetails(
            android: AndroidNotificationDetails(
              settings.silent ? 'prayer_alerts_silent' : 'prayer_alerts_sound',
              'Prayer alerts',
              channelDescription: 'Alerts based on calculated prayer times',
              importance: settings.silent
                  ? Importance.defaultImportance
                  : Importance.high,
              priority:
                  settings.silent ? Priority.defaultPriority : Priority.high,
              playSound: !settings.silent,
              enableVibration: !settings.silent,
            ),
            iOS: DarwinNotificationDetails(presentSound: !settings.silent),
          ),
          androidScheduleMode: mode,
        );
      }
      if (plan.isNotEmpty) {
        await _plugin.zonedSchedule(
          prayerAlertRenewalId,
          'নামাজের অ্যালার্ট রিফ্রেশ করুন',
          'পরবর্তী দিনগুলোর অ্যালার্ট চালু রাখতে অ্যাপটি খুলুন।',
          PrayerAlertPlanner.renewalTime(config, now),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'prayer_alerts_renewal',
              'Prayer alert renewal',
              channelDescription: 'Reminder to refresh upcoming prayer alerts',
              importance: Importance.low,
              playSound: false,
              enableVibration: false,
            ),
            iOS: DarwinNotificationDetails(presentSound: false),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      await _cancelPrayerAlerts();
      rethrow;
    }
    return PrayerAlertScheduleResult(
      permissionGranted: true,
      exact: exact,
      scheduledCount: plan.length,
    );
  }

  Future<bool> _notificationPermission({required bool request}) async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return (request
              ? await android.requestNotificationsPermission()
              : await android.areNotificationsEnabled()) ??
          false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      if (request) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      return (await ios.checkPermissions())?.isEnabled ?? false;
    }
    return false;
  }

  Future<void> _cancelPrayerAlerts() async {
    for (var id = prayerAlertIdBase;
        id < prayerAlertIdBase + prayerAlertDaysAhead * prayerKeys.length;
        id++) {
      await _plugin.cancel(id);
    }
    await _plugin.cancel(prayerAlertRenewalId);
  }

  Future<void> cancelAll() async {
    if (!supported) return;
    await _prayerAlertQueue;
    await _initialize();
    for (final reminder in _reminders) {
      await _plugin.cancel(reminder.id);
    }
    await _cancelPrayerAlerts();
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
