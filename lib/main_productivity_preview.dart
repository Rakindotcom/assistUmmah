import 'package:flutter/material.dart';

import 'src/account/privacy_page.dart';
import 'src/app.dart';
import 'src/app_repository.dart';
import 'src/productivity/ui/productivity_root.dart';

/// Internal, local-only entrypoint for testing the new experience on Android.
/// It uses a separate account namespace and never initializes Firebase.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(UmmahAssistApp(
      firebaseReady: false,
      home: Banner(
          message: 'PREVIEW',
          location: BannerLocation.topEnd,
          child: ProductivityRoot(
              uid: 'productivity-preview',
              legacyRepository: const AppRepository(
                  uid: 'productivity-preview', firebaseReady: false),
              accountBuilder: (_) => const PrivacyPage()))));
}
