import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/records.dart';
import 'productivity_remote.dart';

class FirestoreProductivityRemote implements ProductivityRemote {
  FirestoreProductivityRemote(
      {required this.uid, FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;
  final String uid;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  CollectionReference<Map<String, dynamic>> get _records =>
      _db.collection('users').doc(uid).collection('productivity');
  CollectionReference<Map<String, dynamic>> get _changes =>
      _db.collection('users').doc(uid).collection('productivityChanges');

  void _assertAccount() {
    if (_auth.currentUser?.uid != uid) {
      throw const SyncFailure('account-changed', permanent: true);
    }
  }

  @override
  Future<RemoteAcknowledgement> apply(SyncOperation operation) async {
    _assertAccount();
    if (operation.ownerId != uid) {
      throw const SyncFailure('account-mismatch', permanent: true);
    }
    final reference = _records.doc(operation.recordKey);
    final receiptRef = _changes.doc(operation.id);
    final marker = _db.collection('accountDeletions').doc(uid);
    return _db.runTransaction((transaction) async {
      _assertAccount();
      final deletion = await transaction.get(marker);
      final receipt = await transaction.get(receiptRef);
      final snapshot = await transaction.get(reference);
      if (deletion.exists) {
        throw const SyncFailure('account-deleting', permanent: true);
      }
      final previous =
          snapshot.exists ? WorkspaceRecord.fromJson(snapshot.data()!) : null;
      if (receipt.exists) {
        if (receipt.data()!['fingerprint'] != operation.fingerprint ||
            previous == null) {
          throw const SyncFailure('operation-identity-reused', permanent: true);
        }
        return RemoteAcknowledgement(previous,
            rejectedFields: List<String>.from(
                receipt.data()!['rejectedFields'] as List? ?? []));
      }
      final application = applyRecordOperation(previous, operation);
      final record = application.record;
      final accepted = application.acceptedFields;
      final rejected = application.rejectedFields;
      _assertAccount();
      if (accepted.isNotEmpty) {
        transaction.set(reference, {
          ...record.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(receiptRef, {
        ...operation.payload,
        'fingerprint': operation.fingerprint,
        'acceptedFields': accepted,
        'rejectedFields': rejected,
        'before': {for (final key in accepted) key: previous?.fields[key]},
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return RemoteAcknowledgement(record, rejectedFields: rejected);
    });
  }

  @override
  Future<RemotePage> pull(SyncCursor? cursor, {int limit = 100}) async {
    _assertAccount();
    if (limit < 1 || limit > 200) throw ArgumentError.value(limit, 'limit');
    Query<Map<String, dynamic>> query = _records
        .orderBy('updatedAt')
        .orderBy(FieldPath.documentId)
        .limit(limit);
    if (cursor != null) {
      query = query.startAfter([
        Timestamp(cursor.seconds, cursor.nanoseconds),
        cursor.documentId,
      ]);
    }
    final snapshot = await query.get(const GetOptions(source: Source.server));
    _assertAccount();
    SyncCursor? next = cursor;
    if (snapshot.docs.isNotEmpty) {
      final last = snapshot.docs.last;
      final timestamp = last.data()['updatedAt'] as Timestamp;
      next = SyncCursor(timestamp.seconds, timestamp.nanoseconds, last.id);
    }
    return RemotePage(
        snapshot.docs
            .map((doc) => WorkspaceRecord.fromJson(doc.data()))
            .toList(growable: false),
        cursor: next,
        hasMore: snapshot.docs.length == limit);
  }
}
