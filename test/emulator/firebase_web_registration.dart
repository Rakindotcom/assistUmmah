import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

// Flutter's browser unit-test runner does not perform app plugin registration.
// Register the real SDK implementations; emulator routing still happens before
// any auth or Firestore operation in the test fixture.
void registerFirebaseEmulatorTestPlugins() {
  FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
  FirebaseAuthWeb.registerWith(webPluginRegistrar);
  FirebaseCoreWeb.registerWith(webPluginRegistrar);
  webPluginRegistrar.registerMessageHandler();
}
