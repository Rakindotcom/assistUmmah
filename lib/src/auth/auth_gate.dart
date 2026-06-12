import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../home_shell.dart';
import 'auth_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      return const HomeShell(
        firebaseReady: false,
        repository: AppRepository(uid: 'demo', firebaseReady: false),
        user: null,
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const AuthScreen();
        }

        final repository = AppRepository(uid: user.uid, firebaseReady: true);
        repository
            .ensureUserDocument(
              email: user.email,
              displayName: user.displayName,
            )
            .catchError((_) {});

        return HomeShell(
          firebaseReady: true,
          repository: repository,
          user: user,
        );
      },
    );
  }
}
