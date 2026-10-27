import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'prayer_times_service.dart';

const prayerAlertDaysAhead = 10;
const prayerAlertIdBase = 2000;
const prayerAlertRenewalId = 2050;
const prayerAlertLeadOptions = [0, 5, 10, 15, 30];

class PrayerAlertSettings {
  PrayerAlertSettings({
    this.enabled = false,
    Map<String, bool>? selectedPrayers,
    this.leadMinutes = 0,
    this.silent = false,
    this.quietEnabled = false,
    this.quietStartMinute = 22 * 60,
    this.quietEndMinute = 5 * 60,
  }) : selectedPrayers = Map.unmodifiable(
          selectedPrayers ?? {for (final key in prayerKeys) key: true},
        ) {
    if (!prayerAlertLeadOptions.contains(leadMinutes) ||
        this.selectedPrayers.keys.any((key) => !prayerKeys.contains(key)) ||
        quietStartMinute < 0 ||
        quietStartMinute >= 24 * 60 ||
        quietEndMinute < 0 ||
        quietEndMinute >= 24 * 60 ||
        (quietEnabled && quietStartMinute == quietEndMinute)) {
      throw const FormatException('Invalid prayer alert settings');
    }
  }

  final bool enabled;
  final Map<String, bool> selectedPrayers;
  final int leadMinutes;
  final bool silent;
  final bool quietEnabled;
  final int quietStartMinute;
  final int quietEndMinute;

  PrayerAlertSettings copyWith({
    bool? enabled,
    Map<String, bool>? selectedPrayers,
    int? leadMinutes,
    bool? silent,
    bool? quietEnabled,
    int? quietStartMinute,
    int? quietEndMinute,
  }) =>
      PrayerAlertSettings(
        enabled: enabled ?? this.enabled,
        selectedPrayers: selectedPrayers ?? this.selectedPrayers,
        leadMinutes: leadMinutes ?? this.leadMinutes,
        silent: silent ?? this.silent,
        quietEnabled: quietEnabled ?? this.quietEnabled,
        quietStartMinute: quietStartMinute ?? this.quietStartMinute,
        quietEndMinute: quietEndMinute ?? this.quietEndMinute,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'selectedPrayers': selectedPrayers,
        'leadMinutes': leadMinutes,
        'silent': silent,
        'quietEnabled': quietEnabled,
        'quietStartMinute': quietStartMinute,
        'quietEndMinute': quietEndMinute,
      };

  factory PrayerAlertSettings.fromJson(Map<String, dynamic> json) {
    final rawSelected = asStringMap(json['selectedPrayers']);
    return PrayerAlertSettings(
      enabled: json['enabled'] == true,
      selectedPrayers: rawSelected.isEmpty
          ? null
          : rawSelected.map((key, value) => MapEntry(key, value == true)),
      leadMinutes: (json['leadMinutes'] as num?)?.toInt() ?? 0,
      silent: json['silent'] == true,
      quietEnabled: json['quietEnabled'] == true,
      quietStartMinute: (json['quietStartMinute'] as num?)?.toInt() ?? 22 * 60,
      quietEndMinute: (json['quietEndMinute'] as num?)?.toInt() ?? 5 * 60,
    );
  }

  bool isQuietAt(tz.TZDateTime time) {
    if (!quietEnabled) return false;
    final minute = time.hour * 60 + time.minute;
    if (quietStartMinute < quietEndMinute) {
      return minute >= quietStartMinute && minute < quietEndMinute;
    }
    return minute >= quietStartMinute || minute < quietEndMinute;
  }
}

class PlannedPrayerAlert {
  const PlannedPrayerAlert({
    required this.id,
    required this.prayerKey,
    required this.time,
  });

  final int id;
  final String prayerKey;
  final tz.TZDateTime time;
}

class PrayerAlertPlanner {
  PrayerAlertPlanner._();

  static List<PlannedPrayerAlert> upcoming({
    required PrayerTimeConfig config,
    required PrayerAlertSettings settings,
    required DateTime now,
    int daysAhead = prayerAlertDaysAhead,
  }) {
    if (!settings.enabled) return const [];
    if (daysAhead < 1 || daysAhead > prayerAlertDaysAhead) {
      throw ArgumentError.value(daysAhead, 'daysAhead');
    }
    final zone = PrayerTimeService.location(config.timeZoneId);
    final localNow = tz.TZDateTime.from(now, zone);
    final alerts = <PlannedPrayerAlert>[];
    for (var dayIndex = 0; dayIndex < daysAhead; dayIndex++) {
      final day = tz.TZDateTime(
        zone,
        localNow.year,
        localNow.month,
        localNow.day + dayIndex,
      );
      final schedule = PrayerTimeService.forDay(config, day);
      for (var prayerIndex = 0;
          prayerIndex < schedule.entries.length;
          prayerIndex++) {
        final entry = schedule.entries[prayerIndex];
        if (settings.selectedPrayers[entry.key] != true) continue;
        final alertTime = entry.time.subtract(
          Duration(minutes: settings.leadMinutes),
        );
        if (!alertTime.isAfter(now) || settings.isQuietAt(alertTime)) continue;
        alerts.add(PlannedPrayerAlert(
          id: prayerAlertIdBase + dayIndex * prayerKeys.length + prayerIndex,
          prayerKey: entry.key,
          time: alertTime,
        ));
      }
    }
    alerts.sort((a, b) => a.time.compareTo(b.time));
    return alerts;
  }

  static tz.TZDateTime renewalTime(
    PrayerTimeConfig config,
    DateTime now,
  ) {
    final zone = PrayerTimeService.location(config.timeZoneId);
    final localNow = tz.TZDateTime.from(now, zone);
    return tz.TZDateTime(
      zone,
      localNow.year,
      localNow.month,
      localNow.day + prayerAlertDaysAhead - 2,
      12,
    );
  }
}

class PrayerAlertStore {
  PrayerAlertStore(this.uid, {SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  final String uid;
  final SharedPreferencesAsync _preferences;

  String get _key => 'prayer_alert_settings_v1_$uid';

  Future<PrayerAlertSettings> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return PrayerAlertSettings();
    try {
      return PrayerAlertSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return PrayerAlertSettings();
    }
  }

  Future<void> save(PrayerAlertSettings settings) =>
      _preferences.setString(_key, jsonEncode(settings.toJson()));

  Future<void> remove() => _preferences.remove(_key);
}
