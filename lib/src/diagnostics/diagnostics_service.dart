import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diagnostics_consent.dart';

class DiagnosticsService {
  static DiagnosticsConsent? _consent;
  static bool _installed = false;
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static bool get enabled => _consent?.enabled ?? false;

  static Future<void> initialize() async {
    if (!supported) return;
    final preferences = SharedPreferencesAsync();
    final saved = await preferences.getBool('optional_crash_reports') ?? false;
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(saved && kReleaseMode);
    if (!saved) await crashlytics.deleteUnsentReports();
    _consent = DiagnosticsConsent(
        enabled: saved,
        apply: (value) async {
          if (!enabled && value) await crashlytics.deleteUnsentReports();
          await crashlytics
              .setCrashlyticsCollectionEnabled(value && kReleaseMode);
          if (!value) await crashlytics.deleteUnsentReports();
        },
        persist: (value) =>
            preferences.setBool('optional_crash_reports', value));
    if (_installed) return;
    _installed = true;
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      (previousFlutter ?? FlutterError.presentError)(details);
      _record(details.exception, details.stack ?? StackTrace.empty, false);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _record(error, stack, true);
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  static Future<void> setEnabled(bool value) async {
    if (!supported) return;
    if (_consent == null) await initialize();
    await _consent!.setEnabled(value);
  }

  static void _record(Object error, StackTrace stack, bool fatal) {
    if (!enabled || !kReleaseMode) return;
    // Error messages may contain user input. Report the type and call stack
    // without attaching account IDs, names, email, tasks or religious records.
    unawaited(FirebaseCrashlytics.instance
        .recordError(
          Exception(error.runtimeType.toString()),
          stack,
          fatal: fatal,
        )
        .catchError((Object _) {}));
  }
}
