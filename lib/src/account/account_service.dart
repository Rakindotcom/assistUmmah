import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/google_auth.dart';
import '../diagnostics/diagnostics_service.dart';
import '../prayer_alerts.dart';
import '../prayer_times_service.dart';
import '../reminder_service.dart';
import 'deletion_plan.dart';
import 'session_cleanup.dart';

class AccountService {
  static const _deletedUidsKey = 'pending_deleted_account_uids';
  static const _clearCacheKey = 'clear_firestore_cache_on_startup';

  static Future<void> clearPendingCache() async {
    final preferences = SharedPreferencesAsync();
    final uids = await preferences.getStringList(_deletedUidsKey) ?? [];
    if (await preferences.getBool(_clearCacheKey) != true && uids.isEmpty) {
      return;
    }
    for (final uid in uids) {
      await PrayerTimeStore(uid).remove();
      await PrayerAlertStore(uid).remove();
    }
    // Run before any Firestore listener starts; terminating a shared instance
    // during account switching would prevent it from being reused afterward.
    await FirebaseFirestore.instance.clearPersistence();
    await preferences.remove(_clearCacheKey);
    await preferences.remove(_deletedUidsKey);
  }

  static Future<bool> signOut() => SessionCleanup(
        endSession: FirebaseAuth.instance.signOut,
        cancelReminders: ReminderService.instance.cancelAll,
        clearGoogleSession: GoogleAuthentication.signOut,
      ).signOut();

  static Future<void> _drain(Query<Map<String, dynamic>> query) async {
    while (true) {
      final snapshot =
          await query.limit(200).get(const GetOptions(source: Source.server));
      if (snapshot.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final document in snapshot.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();
    }
  }

  static Future<bool> deleteAccount({String? password}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw FirebaseAuthException(code: 'unauthenticated');
    final usesPassword =
        user.providerData.any((p) => p.providerId == 'password');
    if (usesPassword) {
      if (password == null || password.isEmpty || user.email == null) {
        throw FirebaseAuthException(code: 'wrong-password');
      }
      await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: user.email!, password: password));
    } else if (!await GoogleAuthentication.reauthenticate(user)) {
      return false;
    }
    await user.getIdToken(true);
    final db = FirebaseFirestore.instance;
    final marker = db.collection('accountDeletions').doc(user.uid);
    final plan = AccountDeletionPlan.fromJson(
        await rootBundle.loadString('assets/legal/account-data-paths.json'));
    await plan.execute(
      uid: user.uid,
      recordRequest: () => db.runTransaction((transaction) async {
        if (!(await transaction.get(marker)).exists) {
          transaction.set(marker, <String, Object?>{});
        }
      }),
      deleteCollection: (path) => _drain(db.collection(path)),
      deleteActivities: (collection, field, uid) =>
          _drain(db.collection(collection).where(field, isEqualTo: uid)),
      deleteDocuments: (paths) async {
        final batch = db.batch();
        for (final path in paths) {
          batch.delete(db.doc(path));
        }
        await batch.commit();
      },
      deleteIdentity: user.delete,
    );
    // Only reach this point after Firestore and Auth deletion both succeeded.
    final preferences = SharedPreferencesAsync();
    for (final cleanup in <Future<void> Function()>[
      () async {
        final uids = await preferences.getStringList(_deletedUidsKey) ?? [];
        await preferences.setStringList(
            _deletedUidsKey, {...uids, user.uid}.toList());
      },
      () => preferences.setBool(_clearCacheKey, true),
      () => DiagnosticsService.setEnabled(false),
      PrayerTimeStore(user.uid).remove,
      PrayerAlertStore(user.uid).remove,
    ]) {
      try {
        await cleanup();
      } catch (_) {/* the UI explains local cache cleanup */}
    }
    try {
      await signOut();
    } catch (_) {/* deleting Auth already ends this identity */}
    return true;
  }
}
