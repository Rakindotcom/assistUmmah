import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../account/account_service.dart';
import '../account/delete_account_page.dart';
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
          user: null);
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user == null) return const AuthScreen();
        return _AccountAccessGate(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class _AccountAccessGate extends StatefulWidget {
  const _AccountAccessGate({super.key, required this.user});
  final User user;
  @override
  State<_AccountAccessGate> createState() => _AccountAccessGateState();
}

class _AccountAccessGateState extends State<_AccountAccessGate> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _status;
  bool _signingOut = false;
  String? _signOutError;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  void _watch() {
    _status = FirebaseFirestore.instance
        .collection('accountDeletions')
        .doc(widget.user.uid)
        .snapshots();
  }

  Future<void> _signOut() async {
    setState(() {
      _signingOut = true;
      _signOutError = null;
    });
    try {
      await AccountService.signOut();
    } catch (_) {
      if (mounted) {
        setState(
            () => _signOutError = 'সাইন আউট করা যায়নি। আবার চেষ্টা করুন।');
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _status,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (!snapshot.hasError && snapshot.data?.exists == false) {
            return HomeShell(
                key: ValueKey('home-${widget.user.uid}'),
                firebaseReady: true,
                user: widget.user,
                repository:
                    AppRepository(uid: widget.user.uid, firebaseReady: true));
          }
          final failed = snapshot.hasError;
          return Scaffold(
              body: SafeArea(
                  child: Center(
                      child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  Icon(
                      failed
                          ? Icons.cloud_off_outlined
                          : Icons.person_remove_outlined,
                      size: 48),
                  const SizedBox(height: 20),
                  Text(
                      failed
                          ? 'অ্যাকাউন্টের অবস্থা জানা যায়নি'
                          : 'অ্যাকাউন্ট মুছে ফেলা বাকি আছে',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(
                      failed
                          ? 'ইন্টারনেট সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।'
                          : 'আগের বার মোছা শেষ হয়নি। পরিচয় আবার নিশ্চিত করে বাকি তথ্য ও অ্যাকাউন্ট মুছে ফেলুন। নতুন তথ্য রাখা বন্ধ আছে।',
                      textAlign: TextAlign.center),
                  if (!failed)
                    FilledButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => DeleteAccountPage(
                                    usesPassword: widget.user.providerData.any(
                                        (p) => p.providerId == 'password')))),
                        child: const Text('মুছে ফেলা সম্পন্ন করুন')),
                  if (failed)
                    FilledButton(
                        onPressed: () => setState(_watch),
                        child: const Text('আবার চেষ্টা করুন')),
                  TextButton(
                      onPressed: _signingOut ? null : _signOut,
                      child: const Text('সাইন আউট')),
                  if (_signOutError != null)
                    Text(_signOutError!, textAlign: TextAlign.center),
                ]),
          ))));
        },
      );
}
