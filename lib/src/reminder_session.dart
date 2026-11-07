import 'app_repository.dart';
import 'models.dart';
import 'prayer_alerts.dart';
import 'prayer_times_service.dart';
import 'reminder_service.dart';

/// Refreshes device reminders independently of which screen has been opened.
class ReminderSession {
  ReminderSession({
    required this.repository,
    Set<String>? enabledDailyKeys,
    this.prayerAlertsEnabled = true,
  }) : enabledDailyKeys = Set.unmodifiable(
            enabledDailyKeys ?? const {'prayer', 'tasks', 'growth'}) {
    if (!const {'prayer', 'tasks', 'growth'}
        .containsAll(this.enabledDailyKeys)) {
      throw ArgumentError.value(enabledDailyKeys, 'enabledDailyKeys');
    }
  }

  final AppRepository repository;
  final Set<String> enabledDailyKeys;
  final bool prayerAlertsEnabled;
  int _request = 0;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _request++;
  }

  /// Returns false on failure so the shell can offer a retry. Permission is
  /// requested only from the explicit settings controls, never on app launch.
  Future<bool> refresh() async {
    if (_disposed || !repository.canSync || !ReminderService.supported) {
      return true;
    }
    final request = ++_request;
    final service = ReminderService.instance;
    final dailyRevision = service.dailyRevision;
    final prayerRevision = service.prayerRevision;
    bool current() => !_disposed && request == _request;

    Future<bool> daily() async {
      try {
        if (enabledDailyKeys.isEmpty) {
          await service.sync(const {
            'prayer': false,
            'tasks': false,
            'growth': false,
          });
          return true;
        }
        final data = await repository.loadSettings();
        if (!current() || service.dailyRevision != dailyRevision) return true;
        final preferences = parseBoolMap(data?['notifications']);
        await service.sync({
          for (final key in ['prayer', 'tasks', 'growth'])
            key: data?['remindersConfigured'] == true &&
                enabledDailyKeys.contains(key) &&
                preferences[key] == true,
        });
        return true;
      } catch (_) {
        return false;
      }
    }

    Future<bool> prayers() async {
      try {
        if (!prayerAlertsEnabled) {
          await service.syncPrayerAlerts(
              config: null, settings: PrayerAlertSettings());
          return true;
        }
        final config = await PrayerTimeStore(repository.uid).load();
        final settings = await PrayerAlertStore(repository.uid).load();
        if (!current() || service.prayerRevision != prayerRevision) return true;
        await service.syncPrayerAlerts(config: config, settings: settings);
        return true;
      } catch (_) {
        return false;
      }
    }

    final results = await Future.wait([daily(), prayers()]);
    return !current() || results.every((result) => result);
  }
}
