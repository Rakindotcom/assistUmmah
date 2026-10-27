import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_client_id.dart';

class GoogleAuthentication {
  static GoogleSignIn get _client => GoogleSignIn(
        scopes: const ['email'],
        serverClientId: defaultTargetPlatform == TargetPlatform.android
            ? googleServerClientId
            : null,
      );

  static Future<AuthCredential?> _credential() async {
    final account = await _client.signIn();
    if (account == null) return null;
    final tokens = await account.authentication;
    return GoogleAuthProvider.credential(
      accessToken: tokens.accessToken,
      idToken: tokens.idToken,
    );
  }

  static Future<UserCredential?> signIn() async {
    if (kIsWeb) {
      return FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    }
    final credential = await _credential();
    if (credential == null) return null;
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  static Future<bool> reauthenticate(User user) async {
    if (kIsWeb) {
      await user.reauthenticateWithPopup(GoogleAuthProvider());
      return true;
    }
    final credential = await _credential();
    if (credential == null) return false;
    // Firebase rejects credentials belonging to a different account.
    await user.reauthenticateWithCredential(credential);
    return true;
  }

  static Future<void> signOut() async {
    if (!kIsWeb) await _client.signOut();
  }
}
