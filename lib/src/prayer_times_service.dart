import 'dart:convert';

import 'package:adhan_dart/adhan_dart.dart' as adhan;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'display_formatters.dart';

const prayerCalculationMethods = <String, String>{
  'karachi': 'করাচি',
  'muslimWorldLeague': 'মুসলিম ওয়ার্ল্ড লীগ',
  'ummAlQura': 'উম্মুল কুরা',
  'egyptian': 'মিশরীয় জরিপ কর্তৃপক্ষ',
  'northAmerica': 'উত্তর আমেরিকা (ISNA)',
  'singapore': 'সিঙ্গাপুর',
  'moonsightingCommittee': 'মুনসাইটিং কমিটি',
};

class PrayerTimeConfig {
  PrayerTimeConfig({
    required this.latitude,
    required this.longitude,
    required this.placeName,
    required this.timeZoneId,
    this.method = 'karachi',
    this.madhab = 'hanafi',
    Map<String, int> adjustments = const {},
  }) : adjustments = Map.unmodifiable(adjustments) {
    if (!latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('Invalid coordinates');
    }
    if (placeName.trim().isEmpty || placeName.length > 60) {
      throw const FormatException('Invalid place name');
    }
    if (!prayerCalculationMethods.containsKey(method) ||
        (madhab != 'hanafi' && madhab != 'shafi')) {
      throw const FormatException('Invalid calculation settings');
    }
    for (final entry in adjustments.entries) {
      if (!prayerKeys.contains(entry.key) || entry.value.abs() > 60) {
        throw const FormatException('Invalid prayer adjustment');
      }
    }
    PrayerTimeService.location(timeZoneId);
  }

  final double latitude;
  final double longitude;
  final String placeName;
  final String timeZoneId;
  final String method;
  final String madhab;
  final Map<String, int> adjustments;

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'placeName': placeName,
        'timeZoneId': timeZoneId,
        'method': method,
        'madhab': madhab,
        'adjustments': adjustments,
      };

  factory PrayerTimeConfig.fromJson(Map<String, dynamic> json) {
    final rawAdjustments = asStringMap(json['adjustments']);
    return PrayerTimeConfig(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      placeName: json['placeName'] as String,
      timeZoneId: json['timeZoneId'] as String,
      method: json['method'] as String? ?? 'karachi',
      madhab: json['madhab'] as String? ?? 'hanafi',
      adjustments: rawAdjustments.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      ),
    );
  }

  PrayerTimeConfig copyWith({
    String? method,
    String? madhab,
    Map<String, int>? adjustments,
  }) =>
      PrayerTimeConfig(
        latitude: latitude,
        longitude: longitude,
        placeName: placeName,
        timeZoneId: timeZoneId,
        method: method ?? this.method,
        madhab: madhab ?? this.madhab,
        adjustments: adjustments ?? this.adjustments,
      );
}

class PrayerTimeEntry {
  const PrayerTimeEntry(this.key, this.time);

  final String key;
  final tz.TZDateTime time;
}

class PrayerSchedule {
  const PrayerSchedule(this.entries);

  final List<PrayerTimeEntry> entries;

  PrayerTimeEntry? nextAfter(DateTime now) {
    for (final entry in entries) {
      if (entry.time.isAfter(now)) return entry;
    }
    return null;
  }
}

class PrayerTimeService {
  PrayerTimeService._();

  static bool _timezonesReady = false;

  static tz.Location location(String timeZoneId) {
    if (!_timezonesReady) {
      timezone_data.initializeTimeZones();
      _timezonesReady = true;
    }
    return tz.getLocation(timeZoneId);
  }

  static PrayerSchedule forDay(PrayerTimeConfig config, DateTime day) {
    final zone = location(config.timeZoneId);
    final parameters = _parameters(config);
    final times = adhan.PrayerTimes(
      date: DateTime(day.year, day.month, day.day),
      coordinates: adhan.Coordinates(config.latitude, config.longitude),
      calculationParameters: parameters,
    );
    return PrayerSchedule([
      PrayerTimeEntry('fajr', tz.TZDateTime.from(times.fajr, zone)),
      PrayerTimeEntry('dhuhr', tz.TZDateTime.from(times.dhuhr, zone)),
      PrayerTimeEntry('asr', tz.TZDateTime.from(times.asr, zone)),
      PrayerTimeEntry('maghrib', tz.TZDateTime.from(times.maghrib, zone)),
      PrayerTimeEntry('isha', tz.TZDateTime.from(times.isha, zone)),
    ]);
  }

  static PrayerTimeEntry nextPrayer(PrayerTimeConfig config, DateTime now) {
    final localNow = tz.TZDateTime.from(now, location(config.timeZoneId));
    final today = forDay(config, localNow);
    final next = today.nextAfter(now);
    if (next != null) return next;
    final tomorrow = DateTime(localNow.year, localNow.month, localNow.day + 1);
    return forDay(config, tomorrow).entries.first;
  }

  static adhan.CalculationParameters _parameters(PrayerTimeConfig config) {
    final parameters = switch (config.method) {
      'muslimWorldLeague' =>
        adhan.CalculationMethodParameters.muslimWorldLeague(),
      'ummAlQura' => adhan.CalculationMethodParameters.ummAlQura(),
      'egyptian' => adhan.CalculationMethodParameters.egyptian(),
      'northAmerica' => adhan.CalculationMethodParameters.northAmerica(),
      'singapore' => adhan.CalculationMethodParameters.singapore(),
      'moonsightingCommittee' =>
        adhan.CalculationMethodParameters.moonsightingCommittee(),
      _ => adhan.CalculationMethodParameters.karachi(),
    };
    parameters.madhab =
        config.madhab == 'hanafi' ? adhan.Madhab.hanafi : adhan.Madhab.shafi;
    parameters.polarCircleResolution = adhan.PolarCircleResolution.aqrabBalad;
    parameters.highLatitudeRule = config.latitude.abs() > 48
        ? adhan.HighLatitudeRule.seventhOfTheNight
        : adhan.HighLatitudeRule.middleOfTheNight;
    for (final key in prayerKeys) {
      parameters.adjustments[_adhanPrayer(key)] = config.adjustments[key] ?? 0;
    }
    return parameters;
  }

  static adhan.Prayer _adhanPrayer(String key) => switch (key) {
        'fajr' => adhan.Prayer.fajr,
        'dhuhr' => adhan.Prayer.dhuhr,
        'asr' => adhan.Prayer.asr,
        'maghrib' => adhan.Prayer.maghrib,
        _ => adhan.Prayer.isha,
      };
}

/// Prayer location stays on this device and is separated by signed-in user.
class PrayerTimeStore {
  PrayerTimeStore(this.uid, {SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  final String uid;
  final SharedPreferencesAsync _preferences;

  String get _key => 'prayer_time_config_v1_$uid';

  Future<PrayerTimeConfig?> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return null;
    try {
      return PrayerTimeConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  Future<void> save(PrayerTimeConfig config) =>
      _preferences.setString(_key, jsonEncode(config.toJson()));

  Future<void> remove() => _preferences.remove(_key);
}

class PrayerLocationService {
  PrayerLocationService._();

  static Future<(double, double)> currentCoordinates() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location service is disabled');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission was denied');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 15),
      ),
    );
    // City-scale coordinates are sufficient for times and reduce the amount of
    // location detail retained on the device.
    double round(double value) => (value * 100).round() / 100;
    return (round(position.latitude), round(position.longitude));
  }
}

String formatPrayerTime(tz.TZDateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return banglaDigits('$hour:$minute');
}
