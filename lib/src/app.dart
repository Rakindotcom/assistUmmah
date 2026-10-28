import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'app_theme.dart';
import 'app_identity.dart';
import 'app_localization.dart';
import 'auth/auth_gate.dart';
import 'auth/account_navigation_boundary.dart';

class UmmahAssistApp extends StatelessWidget {
  const UmmahAssistApp({super.key, required this.firebaseReady, this.home});

  final bool firebaseReady;
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: AppIdentity.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: AppLocalization.locale,
      supportedLocales: AppLocalization.supportedLocales,
      localizationsDelegates: AppLocalization.delegates,
      home: home ?? AuthGate(firebaseReady: firebaseReady),
    );
    if (!firebaseReady || home != null) return app;
    final auth = FirebaseAuth.instance;
    return AccountNavigationBoundary(
      sessionIds: auth.authStateChanges().map((user) => user?.uid),
      initialSessionId: auth.currentUser?.uid,
      child: app,
    );
  }
}
