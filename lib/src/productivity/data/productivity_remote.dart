import '../core/records.dart';

class RemoteAcknowledgement {
  const RemoteAcknowledgement(this.record, {this.rejectedFields = const []});
  final WorkspaceRecord record;
  final List<String> rejectedFields;
}

class RemotePage {
  const RemotePage(this.records, {this.cursor, required this.hasMore});
  final List<WorkspaceRecord> records;
  final SyncCursor? cursor;
  final bool hasMore;
}

abstract interface class ProductivityRemote {
  Future<RemoteAcknowledgement> apply(SyncOperation operation);
  Future<RemotePage> pull(SyncCursor? cursor, {int limit = 100});
}

class SyncFailure implements Exception {
  const SyncFailure(this.code, {this.permanent = false});
  final String code;
  final bool permanent;
  @override
  String toString() => 'SyncFailure($code)';
}
