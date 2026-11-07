import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'firestore_portable_document.dart';
import 'legacy_task_migration.dart';

class _LegacyPreparation {
  const _LegacyPreparation.success() : failure = null;
  const _LegacyPreparation.failure(this.failure);
  final LegacyMigrationFailure? failure;
}

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
    final result =
        await firestore.runTransaction<_LegacyPreparation>((transaction) async {
      try {
        _assertAccount();
        final marker = await transaction
            .get(firestore.collection('accountDeletions').doc(uid));
        final snapshot = await transaction.get(reference);
        _assertAccount();
        if (marker.exists) {
          return const _LegacyPreparation.failure(
              LegacyMigrationFailure('account-deleting'));
        }
        final source = _portable(snapshot.data() ?? <String, dynamic>{})
            as Map<String, Object?>;
        final version = source['productivityMigrationVersion'];
        if (version != null && version != 1) {
          return const _LegacyPreparation.failure(
              LegacyMigrationFailure('unsupported-migration-version'));
        }
        // Validate the complete plan before locking any legacy write path.
        LegacyTaskMigration.prepare(
            {...source, 'productivityMigrationVersion': 1});
        if (version == null) {
          transaction.set(reference, {'productivityMigrationVersion': 1},
              SetOptions(merge: true));
        }
        return const _LegacyPreparation.success();
      } on LegacyMigrationFailure catch (failure) {
        // Return domain failures across the JS Promise boundary. Throwing a
        // Dart object inside the callback boxes it as a NativeError on web.
        return _LegacyPreparation.failure(failure);
      } on FormatException {
        return const _LegacyPreparation.failure(
            LegacyMigrationFailure('invalid-source-value'));
      } on TypeError {
        return const _LegacyPreparation.failure(
            LegacyMigrationFailure('invalid-source-value'));
      }
    });
    _assertAccount();
    if (result.failure != null) throw result.failure!;
    // The source is now immutable under the deployed fence rules. Read its
    // typed REST representation so web/native SDK timestamp and integer
    // conversions cannot change the archive or checksum across devices.
    final source = await _readFrozenSource();
    _assertAccount();
    try {
      return LegacyTaskMigration.prepare(source);
    } on FormatException {
      throw const LegacyMigrationFailure('invalid-source-value');
    }
  }

  Future<Map<String, Object?>> _readFrozenSource() async {
    _assertAccount();
    final uri = legacySnapshotUri(
        projectId: firestore.app.options.projectId,
        databaseId: firestore.databaseId,
        uid: uid,
        host: firestore.settings.host,
        sslEnabled: firestore.settings.sslEnabled ?? true);
    final token = await auth.currentUser!.getIdToken().timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw const LegacyMigrationFailure('source-auth-unavailable'));
    _assertAccount();
    if (token == null || token.isEmpty) {
      throw const LegacyMigrationFailure('source-auth-unavailable');
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['Authorization'] = 'Bearer $token';
      final response =
          await client.send(request).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const LegacyMigrationFailure('source-read-failed');
      }
      Future<List<int>> body() async {
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 8 * 1024 * 1024) {
            throw const LegacyMigrationFailure('source-too-large');
          }
          bytes.addAll(chunk);
        }
        return bytes;
      }

      final bytes = await body().timeout(const Duration(seconds: 15));
      _assertAccount();
      final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (document['name'] != uri.pathSegments.skip(1).join('/')) {
        throw const LegacyMigrationFailure('source-identity-mismatch');
      }
      return decodeFirestoreFields(
          Map<String, dynamic>.from(document['fields'] as Map? ?? {}));
    } on FormatException {
      throw const LegacyMigrationFailure('invalid-source-value');
    } on TypeError {
      throw const LegacyMigrationFailure('invalid-source-value');
    } finally {
      client.close();
    }
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
    if (value is Blob) {
      return {'__firestoreType': 'bytes', 'base64': base64Encode(value.bytes)};
    }
    if (value is int && value.abs() > 9007199254740991) {
      return {'__firestoreType': 'integer', 'value': value.toString()};
    }
    if (value is double && !value.isFinite) {
      return {'__firestoreType': 'double', 'value': value.toString()};
    }
    if (value is List) return value.map(_portable).toList();
    if (value is Map<String, dynamic>) {
      return value.map((key, item) => MapEntry(key, _portable(item)));
    }
    return value;
  }
}
