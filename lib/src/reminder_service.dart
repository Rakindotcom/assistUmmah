import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'prayer_alerts.dart';
import 'prayer_times_service.dart';
import 'productivity/domain/task_reminder_plan.dart';

class TaskAlertScheduleResult {
  const TaskAlertScheduleResult(
      {required this.permissionGranted,
      required this.exact,
      required this.scheduledCount,
      required this.deferredCount});
  final bool permissionGranted, exact;
  final int scheduledCount, deferredCount;
}

class TaskAlertDelivery {
  const TaskAlertDelivery(this.scope, this.result);
  final int scope;
  final TaskAlertScheduleResult result;
}

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
  Future<void> _queue = Future<void>.value();
  int _generation = 0;
  int _dailyRevision = 0;
  int _prayerRevision = 0;
  int _prayerPreferenceUpdates = 0;
  int _taskScope = 0, _taskRevision = 0;
  String? _taskOwner;
  bool _taskInitialCleanup = false;
  TaskReminderPlan? _taskPlan;
  final _taskIds = <int>{};
  final taskDelivery = ValueNotifier<TaskAlertDelivery?>(null);

  /// Claiming a new account invalidates old requests synchronously, before any
  /// platform await. No native work occurs until that owner supplies its plan.
  int claimTaskReminderScope(String uid) {
    _taskRevision++;
    _taskPlan = null;
    _taskOwner = taskReminderOwner(uid);
    _taskInitialCleanup = true;
    return ++_taskScope;
  }

  Future<bool> requestTaskReminderPermission(int scope) => _enqueue(() async {
        if (!supported || scope != _taskScope) return false;
        await _initialize();
        if (scope != _taskScope) return false;
        final granted = await _notificationPermission(request: true);
        return scope == _taskScope && granted;
      });

  Future<TaskAlertScheduleResult?> syncTaskAlerts(
      int scope, TaskReminderPlan? plan) {
    if (scope != _taskScope) return Future.value();
    if (plan != null && plan.owner != _taskOwner) {
      throw StateError('Reminder plan belongs to another account.');
    }
    final revision = ++_taskRevision;
    final generation = _generation;
    _taskPlan = plan;
    return _enqueue(() async {
      if (scope != _taskScope ||
          revision != _taskRevision ||
          generation != _generation) {
        return null;
      }
      if (!supported) return null;
      if (plan != null) await _initialize();
      if (scope != _taskScope ||
          revision != _taskRevision ||
          generation != _generation) {
        return null;
      }
      return _refreshTaskAlerts();
    });
  }

  Future<void> releaseTaskReminderScope(int scope) {
    if (scope != _taskScope) return Future.value();
    _taskRevision++;
    _taskPlan = null;
    _taskOwner = null;
    final released = ++_taskScope;
    return _enqueue(() async {
      if (!supported || released != _taskScope) return;
      final pending = await _plugin.pendingNotificationRequests();
      if (released != _taskScope) return;
      await _loadTaskIds(pending, includeDisplayed: true);
      if (released != _taskScope) return;
      await _cancelTaskAlerts();
    });
  }

  bool _isTaskAlertId(int? id) =>
      id != null &&
      id >= taskAlertIdBase &&
      id < taskAlertIdBase + taskAlertSlotCount;

  Future<void> _loadTaskIds(List<PendingNotificationRequest> pending,
      {bool includeDisplayed = false}) async {
    _taskIds
      ..clear()
      ..addAll(pending.where((r) => _isTaskAlertId(r.id)).map((r) => r.id));
    if (includeDisplayed) {
      final displayed = await _plugin.getActiveNotifications();
      _taskIds.addAll(
          displayed.where((r) => _isTaskAlertId(r.id)).map((r) => r.id!));
    }
  }

  Future<void> _cancelTaskAlerts() async {
    final ids = {..._taskIds};
    Object? failure;
    for (final id in ids) {
      try {
        await _plugin.cancel(id);
        _taskIds.remove(id);
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }

  Future<void> _vacateTaskSlots() async {
    if (_taskOwner == null) return;
    // Vacate before adding prayer/daily alerts: iOS can discard an older
    // unrelated request as soon as a 65th notification is added. Reallocating
    // only afterward would be too late to preserve those other reminders.
    final pending = await _plugin.pendingNotificationRequests();
    await _loadTaskIds(pending);
    await _cancelTaskAlerts();
  }

  Future<TaskAlertScheduleResult?> _refreshTaskAlerts() async {
    final scope = _taskScope, revision = _taskRevision;
    final generation = _generation, plan = _taskPlan;
    bool current() =>
        scope == _taskScope &&
        revision == _taskRevision &&
        generation == _generation;
    final pending = await _plugin.pendingNotificationRequests();
    if (!current()) return null;
    await _loadTaskIds(pending,
        includeDisplayed: _taskInitialCleanup || plan == null);
    if (!current()) return null;
    await _cancelTaskAlerts();
    if (!current()) return null;
    _taskInitialCleanup = false;
    final allowed =
        plan == null || await _notificationPermission(request: false);
    if (!current()) return null;
    var exact = false;
    if (allowed && plan != null && plan.totalCount > 0) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      exact = android == null ||
          (await android.canScheduleExactNotifications() ?? false);
    }
    if (!current()) return null;
    final now = DateTime.now().toUtc();
    final future = plan?.reminders.where((r) => r.time.isAfter(now)).toList() ??
        const <PlannedTaskReminder>[];
    final total = plan == null
        ? 0
        : plan.totalCount - (plan.reminders.length - future.length);
    final otherCount =
        pending.where((value) => !_isTaskAlertId(value.id)).length;
    final capacity = defaultTargetPlatform == TargetPlatform.iOS
        ? (64 - otherCount).clamp(0, taskAlertSlotCount)
        : taskAlertSlotCount;
    final count = !allowed
        ? 0
        : (total > capacity ? capacity - 1 : capacity).clamp(0, future.length);
    final selected = future.take(count).toList();
    Future<void> schedule(int id, String title, String body, DateTime time,
        String payload) async {
      if (!current()) return;
      _taskIds.add(id);
      Future<void> write(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          title,
          body,
          tz.TZDateTime.from(time, tz.UTC),
          const NotificationDetails(
              android: AndroidNotificationDetails(
                  'task_reminders', 'Task reminders',
                  channelDescription: 'Reminders explicitly added to tasks',
                  importance: Importance.high,
                  priority: Priority.high,
                  visibility: NotificationVisibility.private),
              iOS: DarwinNotificationDetails()),
          androidScheduleMode: mode,
          payload: payload);
      try {
        await write(exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle);
      } on PlatformException catch (error) {
        if (!current()) return;
        if (!exact || error.code != 'exact_alarms_not_permitted') rethrow;
        // Permission can be revoked between the capability check and schedule.
        exact = false;
        await write(AndroidScheduleMode.inexactAllowWhileIdle);
      }
    }

    try {
      for (var i = 0; i < selected.length; i++) {
        if (!current()) return null;
        final reminder = selected[i];
        await schedule(
            taskAlertIdBase + i,
            reminder.title,
            plan!.language == 'bn' ? 'কাজের রিমাইন্ডার' : 'Task reminder',
            reminder.time,
            jsonEncode({
              'type': 'productivity-task-v1',
              'owner': plan.owner,
              'taskId': reminder.taskId,
              'workspaceId': reminder.workspaceId
            }));
      }
      if (current() && allowed && total > selected.length && capacity > 0) {
        // A renewal occupies a real slot too. The deferred count is exposed in
        // Settings; background refill is not promised by a foreground session.
        final time = selected.isEmpty
            ? now.add(const Duration(minutes: 1))
            : selected.last.time;
        await schedule(
            taskAlertRenewalId,
            plan!.language == 'bn'
                ? 'কাজের রিমাইন্ডার রিফ্রেশ করুন'
                : 'Refresh task reminders',
            plan.language == 'bn'
                ? 'পরের রিমাইন্ডারগুলো চালু রাখতে অ্যাপটি খুলুন।'
                : 'Open the app to schedule the remaining reminders.',
            time,
            jsonEncode(
                {'type': 'productivity-task-renewal-v1', 'owner': plan.owner}));
      }
    } catch (_) {
      await _cancelTaskAlerts();
      rethrow;
    }
    if (!current()) return null;
    final result = TaskAlertScheduleResult(
        permissionGranted: allowed,
        exact: exact,
        scheduledCount: selected.length,
        deferredCount: total - selected.length);
    taskDelivery.value = TaskAlertDelivery(scope, result);
    return result;
  }

  int get dailyRevision => _dailyRevision;
  int get prayerRevision => _prayerRevision;

  bool get prayerPreferencesChanging => _prayerPreferenceUpdates > 0;

  /// An explicit edit includes native permission UI, scheduling and persistence.
  /// Resume refreshes must not enqueue the previous stored preference mid-edit.
  /// Revisions also invalidate refresh reads started before the edit began.
  Future<T> updatePrayerPreferences<T>(Future<T> Function() update) async {
    _prayerPreferenceUpdates++;
    _prayerRevision++;
    try {
      return await update();
    } finally {
      _prayerPreferenceUpdates--;
      _prayerRevision++;
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

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
  }) {
    final generation = _generation;
    _dailyRevision++;
    final saved = Map<String, bool>.of(preferences);
    return _enqueue(() => generation != _generation
        ? Future.value(false)
        : _sync(saved, requestPermission: requestPermission));
  }

  Future<bool> _sync(
    Map<String, bool> preferences, {
    required bool requestPermission,
  }) async {
    if (!supported) return false;
    await _initialize();
    // Daily reminders follow the device's current zone, independently of the
    // global timezone.local value used (and reset) by other modules.
    final zone = preferences.values.any((enabled) => enabled)
        ? PrayerTimeService.location(
            (await FlutterTimezone.getLocalTimezone()).identifier)
        : null;
    await _vacateTaskSlots();

    if (requestPermission && preferences.values.any((value) => value)) {
      if (!await _notificationPermission(request: true)) return false;
    }

    for (final reminder in _reminders) {
      await _plugin.cancel(reminder.id);
      if (preferences[reminder.key] == true) {
        await _schedule(reminder, zone!);
      }
    }
    if (_taskPlan != null) await _refreshTaskAlerts();
    return true;
  }

  Future<PrayerAlertScheduleResult> syncPrayerAlerts({
    required PrayerTimeConfig? config,
    required PrayerAlertSettings settings,
    bool requestPermission = false,
  }) {
    final generation = _generation;
    _prayerRevision++;
    return _enqueue(() => generation != _generation
        ? Future.value(const PrayerAlertScheduleResult(
            permissionGranted: false, exact: false, scheduledCount: 0))
        : _syncPrayerAlerts(
            config: config,
            settings: settings,
            requestPermission: requestPermission,
          ));
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
    await _vacateTaskSlots();

    if (!settings.enabled) {
      await _cancelPrayerAlerts();
      if (_taskPlan != null) await _refreshTaskAlerts();
      return const PrayerAlertScheduleResult(
        permissionGranted: true,
        exact: true,
        scheduledCount: 0,
      );
    }
    if (config == null) {
      await _cancelPrayerAlerts();
      if (_taskPlan != null) await _refreshTaskAlerts();
      return const PrayerAlertScheduleResult(
        permissionGranted: true,
        exact: true,
        scheduledCount: 0,
      );
    }
    if (!await _notificationPermission(request: requestPermission)) {
      await _cancelPrayerAlerts();
      if (_taskPlan != null) await _refreshTaskAlerts();
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
    if (_taskPlan != null) await _refreshTaskAlerts();
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

  Future<void> cancelAll() {
    // Invalidate queued work immediately, then finish any in-flight operation
    // before cancellation. A signed-out account cannot leave reminders behind.
    _generation++;
    _dailyRevision++;
    _prayerRevision++;
    _taskRevision++;
    _taskScope++;
    _taskPlan = null;
    _taskOwner = null;
    _taskInitialCleanup = false;
    return _enqueue(() async {
      if (!supported) return;
      // Native cancellation clears pending and displayed notifications without
      // needing timezone or notification initialization to succeed first.
      await _plugin.cancelAll();
      _taskIds.clear();
    });
  }

  Future<void> _schedule(_Reminder reminder, tz.Location zone) async {
    final now = tz.TZDateTime.now(zone);
    var next = tz.TZDateTime(
      zone,
      now.year,
      now.month,
      now.day,
      reminder.hour,
    );
    if (!next.isAfter(now)) {
      next = tz.TZDateTime(
        zone,
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
