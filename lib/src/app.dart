import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_identity.dart';
import 'app_localization.dart';
import 'auth/auth_gate.dart';

class UmmahAssistApp extends StatelessWidget {
  const UmmahAssistApp({super.key, required this.firebaseReady, this.home});

  final bool firebaseReady;
  final Widget? home;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppIdentity.name,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: AppLocalization.locale,
        supportedLocales: AppLocalization.supportedLocales,
        localizationsDelegates: AppLocalization.delegates,
        home: home ?? AuthGate(firebaseReady: firebaseReady),
      );
}
