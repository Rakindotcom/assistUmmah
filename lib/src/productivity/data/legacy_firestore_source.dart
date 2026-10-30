import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'legacy_task_migration.dart';

/// Activation requires deployed fence rules and the new task UI on every route.
/// This adapter is not called from the legacy UI: freezing its task document
/// before the cutover would prevent existing users from saving their tasks.
class LegacyFirestoreSource {
  LegacyFirestoreSource(
      {required this.uid, required this.firestore, required this.auth});
  final String uid;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  void _assertAccount() {
    if (auth.currentUser?.uid != uid) {
      throw const LegacyMigrationFailure('account-changed');
    }
  }

  Future<LegacyTaskMigration> freezeAndPrepare() async {
    _assertAccount();
    final reference = firestore.collection('userTasks').doc(uid);
    final plan = await firestore.runTransaction((transaction) async {
      _assertAccount();
      final marker = await transaction
          .get(firestore.collection('accountDeletions').doc(uid));
      final snapshot = await transaction.get(reference);
      _assertAccount();
      if (marker.exists) throw const LegacyMigrationFailure('account-deleting');
      final source = _portable(snapshot.data() ?? <String, dynamic>{})
          as Map<String, Object?>;
      final version = source['productivityMigrationVersion'];
      if (version != null && version != 1) {
        throw const LegacyMigrationFailure('unsupported-migration-version');
      }
      // Validate the complete plan before locking any legacy write path.
      final migration = LegacyTaskMigration.prepare(
          {...source, 'productivityMigrationVersion': 1});
      if (version == null) {
        transaction.set(reference, {'productivityMigrationVersion': 1},
            SetOptions(merge: true));
      }
      return migration;
    });
    _assertAccount();
    return plan;
  }

  Object? _portable(Object? value) {
    if (value is Timestamp) {
      return {
        '__firestoreType': 'timestamp',
        'seconds': value.seconds,
        'nanoseconds': value.nanoseconds
      };
    }
    if (value is GeoPoint) {
      return {
        '__firestoreType': 'geoPoint',
        'latitude': value.latitude,
        'longitude': value.longitude
      };
    }
    if (value is DocumentReference) {
      return {'__firestoreType': 'reference', 'path': value.path};
    }
    if (value is List) return value.map(_portable).toList();
    if (value is Map<String, dynamic>) {
      return value.map((key, item) => MapEntry(key, _portable(item)));
    }
    return value;
  }
}
