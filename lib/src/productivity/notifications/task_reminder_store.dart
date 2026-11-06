import 'package:shared_preferences/shared_preferences.dart';

import '../domain/task_reminder_plan.dart';

/// Notification consent belongs to this account on this device. It is not
/// imported from a backup or synchronized into another device's permissions.
class TaskReminderStore {
  TaskReminderStore(this.uid, {SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();
  final String uid;
  final SharedPreferencesAsync _preferences;
  String get _key => 'task_reminders_v1_${taskReminderOwner(uid)}';
  Future<bool> load() async => await _preferences.getBool(_key) ?? false;
  Future<void> save(bool enabled) => _preferences.setBool(_key, enabled);
  Future<void> remove() => _preferences.remove(_key);
}
