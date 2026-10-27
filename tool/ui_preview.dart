// Local preview entry point. Uses no Firebase connection or real user data.
import 'package:flutter/material.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/app_theme.dart';
import 'package:ummah_assist/src/app_identity.dart';
import 'package:ummah_assist/src/app_localization.dart';
import 'package:ummah_assist/src/auth/auth_screen.dart';
import 'package:ummah_assist/src/home_shell.dart';

import 'ui_preview_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = Uri.base.queryParameters['screen'] == 'auth';
  final sample = Uri.base.queryParameters['data'] == 'sample';
  final scale = (double.tryParse(Uri.base.queryParameters['scale'] ?? '') ?? 1)
      .clamp(1.0, 2.0);
  final today = DateTime(2026, 10, 26, 9, 41);
  final repository = sample
      ? UiPreviewRepository(today: today)
      : const AppRepository(uid: 'demo', firebaseReady: false);
  runApp(Builder(
      builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: MaterialApp(
                title: AppIdentity.name,
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                locale: AppLocalization.locale,
                supportedLocales: AppLocalization.supportedLocales,
                localizationsDelegates: AppLocalization.delegates,
                home: auth
                    ? const AuthScreen()
                    : HomeShell(
                        firebaseReady: false,
                        repository: repository,
                        user: null,
                        clock: () => today)),
          )));
}
