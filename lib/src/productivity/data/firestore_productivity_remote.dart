import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/records.dart';
import '../domain/task.dart';
import '../domain/task_graph.dart';
import 'productivity_remote.dart';

class _GraphSnapshot {
  const _GraphSnapshot(this.revision, this.graph);
  final int revision;
  final TaskGraph graph;
}

class _ApplyResult {
  const _ApplyResult(this.acknowledgement, this.graph);
  final RemoteAcknowledgement acknowledgement;
  final _GraphSnapshot? graph;
}

class FirestoreProductivityRemote implements ProductivityRemote {
  FirestoreProductivityRemote(
      {required this.uid, FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;
  final String uid;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  _GraphSnapshot? _cachedGraph;
  CollectionReference<Map<String, dynamic>> get _records =>
      _db.collection('users').doc(uid).collection('productivity');
  CollectionReference<Map<String, dynamic>> get _changes =>
      _db.collection('users').doc(uid).collection('productivityChanges');
  CollectionReference<Map<String, dynamic>> get _graphEdges =>
      _db.collection('users').doc(uid).collection('productivityGraph');
  DocumentReference<Map<String, dynamic>> get _graphControl => _db
      .collection('users')
      .doc(uid)
      .collection('productivityControl')
      .doc('taskGraph');

  void _assertAccount() {
    if (_auth.currentUser?.uid != uid) {
      throw const SyncFailure('account-changed', permanent: true);
    }
  }

  Future<_GraphSnapshot> _readGraph() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      _assertAccount();
      final before =
          await _graphControl.get(const GetOptions(source: Source.server));
      final revision = before.exists ? before.data()!['revision'] as int : 0;
      if (_cachedGraph?.revision == revision) return _cachedGraph!;
      final nodes = <TaskGraphNode>[];
      QueryDocumentSnapshot<Map<String, dynamic>>? last;
      while (true) {
        Query<Map<String, dynamic>> query =
            _graphEdges.orderBy(FieldPath.documentId).limit(200);
        if (last != null) query = query.startAfterDocument(last);
        final page = await query.get(const GetOptions(source: Source.server));
        _assertAccount();
        for (final document in page.docs) {
          final data = document.data();
          if (data['ownerId'] != uid || document.id != data['id']) {
            throw const SyncFailure('invalid-task-graph', permanent: true);
          }
          nodes.add(TaskGraphNode.fromProjection(data));
        }
        if (page.docs.length < 200) break;
        last = page.docs.last;
      }
      final after =
          await _graphControl.get(const GetOptions(source: Source.server));
      _assertAccount();
      final endRevision = after.exists ? after.data()!['revision'] as int : 0;
      if (revision != endRevision) continue;
      if (revision == 0 && nodes.isNotEmpty) {
        throw const SyncFailure('invalid-task-graph', permanent: true);
      }
      try {
        final graph = TaskGraph(nodes);
        graph.validate();
        return _cachedGraph = _GraphSnapshot(revision, graph);
      } on TaskGraphConflict {
        throw const SyncFailure('invalid-task-graph', permanent: true);
      } on FormatException {
        throw const SyncFailure('invalid-task-graph', permanent: true);
      }
    }
    throw const SyncFailure('graph-busy');
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
    for (var attempt = 0; attempt < 3; attempt++) {
      final graph =
          operation.kind == RecordKind.task ? await _readGraph() : null;
      try {
        final result =
            await _db.runTransaction<_ApplyResult>((transaction) async {
          _assertAccount();
          final deletion = await transaction.get(marker);
          final receipt = await transaction.get(receiptRef);
          final snapshot = await transaction.get(reference);
          final control =
              graph == null ? null : await transaction.get(_graphControl);
          if (deletion.exists) {
            throw const SyncFailure('account-deleting', permanent: true);
          }
          if (graph != null &&
              (control!.exists ? control.data()!['revision'] as int : 0) !=
                  graph.revision) {
            throw const SyncFailure('graph-stale');
          }
          final previous = snapshot.exists
              ? WorkspaceRecord.fromJson(snapshot.data()!)
              : null;
          if (receipt.exists) {
            if (receipt.data()!['fingerprint'] != operation.fingerprint ||
                previous == null) {
              throw const SyncFailure('operation-identity-reused',
                  permanent: true);
            }
            return _ApplyResult(
                RemoteAcknowledgement(previous,
                    rejectedFields: List<String>.from(
                        receipt.data()!['rejectedFields'] as List? ?? [])),
                null);
          }
          final application = applyRecordOperation(previous, operation);
          final record = application.record;
          final accepted = application.acceptedFields;
          final rejected = application.rejectedFields;
          _GraphSnapshot? updatedGraph;
          if (graph != null && accepted.isNotEmpty) {
            try {
              final task = ProductivityTask.fromRecord(record);
              final candidate = graph.graph.replacing(
                  TaskGraphNode.fromTask(task, deleted: record.deleted));
              candidate.validate();
              updatedGraph = _GraphSnapshot(graph.revision + 1, candidate);
            } on TaskGraphConflict catch (error) {
              throw SyncFailure(error.code, permanent: true);
            } on FormatException {
              throw const SyncFailure('invalid-task', permanent: true);
            } on TypeError {
              throw const SyncFailure('invalid-task', permanent: true);
            }
          }
          _assertAccount();
          if (accepted.isNotEmpty) {
            transaction.set(reference, {
              ...record.toJson(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            if (updatedGraph != null) {
              final projection = updatedGraph.graph.nodes[record.id]!;
              transaction.set(_graphEdges.doc(record.id), {
                ...projection.toProjection(),
                'ownerId': uid,
                'taskRevision': record.revision,
                'updatedAt': FieldValue.serverTimestamp(),
              });
              transaction.set(_graphControl, {
                'ownerId': uid,
                'revision': updatedGraph.revision,
                'lastRecordId': record.id,
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
          }
          transaction.set(receiptRef, {
            ...operation.payload,
            'fingerprint': operation.fingerprint,
            'acceptedFields': accepted,
            'rejectedFields': rejected,
            'before': {for (final key in accepted) key: previous?.fields[key]},
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return _ApplyResult(
              RemoteAcknowledgement(record, rejectedFields: rejected),
              updatedGraph);
        });
        if (result.graph != null) _cachedGraph = result.graph;
        return result.acknowledgement;
      } on SyncFailure catch (error) {
        if (error.code != 'graph-stale') rethrow;
        _cachedGraph = null;
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied' || graph == null) rethrow;
        // A concurrent guard update can make Firestore Rules reject the losing
        // transaction before the SDK reports a retryable transaction conflict.
        // Only retry if the server guard actually advanced.
        final current =
            await _graphControl.get(const GetOptions(source: Source.server));
        _assertAccount();
        final revision =
            current.exists ? current.data()!['revision'] as int : 0;
        if (revision == graph.revision) rethrow;
        _cachedGraph = null;
      }
    }
    throw const SyncFailure('graph-busy');
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
