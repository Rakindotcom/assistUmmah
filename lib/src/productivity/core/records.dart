import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

enum RecordKind {
  workspace,
  task,
  taskOccurrence,
  project,
  milestone,
  goal,
  goalMetric,
  habit,
  habitLog,
  calendarEvent,
  timeBlock,
  focusSession,
  note,
  dailyReview,
  integrationConnection,
}

String newRecordId() {
  final random = Random.secure();
  return List.generate(
      16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

void validateOwner(String value) {
  if (value.trim().isEmpty || value.length > 128 || value.contains('/')) {
    throw const FormatException('Invalid account identity.');
  }
}

void validateRecordId(String value) {
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,96}$').hasMatch(value)) {
    throw const FormatException('Invalid record identity.');
  }
}

/// A logical clock, independent of inaccurate device wall clocks. A stable
/// device identity breaks concurrent ties deterministically on every client.
class VersionStamp implements Comparable<VersionStamp> {
  VersionStamp(this.counter, this.device) {
    if (counter < 1 || counter > 9007199254740991) {
      throw const FormatException('Invalid logical clock.');
    }
    validateRecordId(device);
  }
  final int counter;
  final String device;

  @override
  int compareTo(VersionStamp other) {
    final order = counter.compareTo(other.counter);
    return order == 0 ? device.compareTo(other.device) : order;
  }

  @override
  bool operator ==(Object other) =>
      other is VersionStamp &&
      counter == other.counter &&
      device == other.device;

  @override
  int get hashCode => Object.hash(counter, device);

  Map<String, Object> toJson() => {'counter': counter, 'device': device};
  factory VersionStamp.fromJson(Map<String, dynamic> json) =>
      VersionStamp(json['counter'] as int, json['device'] as String);
}

Object? _canonical(Object? value, [int depth = 0]) {
  if (depth > 32) throw const FormatException('JSON nesting is too deep.');
  if (value is int && value.abs() > 9007199254740991) {
    throw const FormatException('Integer exceeds portable JSON precision.');
  }
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double && value.isFinite) return value;
  if (value is List) {
    return value
        .map((item) => _canonical(item, depth + 1))
        .toList(growable: false);
  }
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key], depth + 1)};
  }
  throw const FormatException('Only finite JSON values are supported.');
}

String canonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _immutable(Object? value) {
  if (value is List) return List<Object?>.unmodifiable(value.map(_immutable));
  if (value is Map<String, dynamic>) {
    return Map<String, Object?>.unmodifiable(
        value.map((key, item) => MapEntry(key, _immutable(item))));
  }
  return value;
}

Map<String, Object?> validatedFields(Map<String, Object?> fields) {
  if (fields.length > 128 ||
      fields.keys.any((key) =>
          key != '_deleted' &&
          !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(key))) {
    throw const FormatException('Invalid record field.');
  }
  if (fields.containsKey('_deleted') && fields['_deleted'] is! bool) {
    throw const FormatException('Invalid deletion state.');
  }
  if (fields.containsKey('workspaceId')) {
    if (fields['workspaceId'] is! String) {
      throw const FormatException('Invalid workspace identity.');
    }
    validateRecordId(fields['workspaceId'] as String);
  }
  final serialized = jsonEncode(_canonical(fields, 8));
  if (utf8.encode(serialized).length > 262144) {
    throw const FormatException(
        'Record is too large. Use attachment references.');
  }
  return _immutable(jsonDecode(serialized)) as Map<String, Object?>;
}

class WorkspaceRecord {
  WorkspaceRecord({
    required this.ownerId,
    required this.kind,
    required this.id,
    required Map<String, Object?> fields,
    required Map<String, VersionStamp> clocks,
    this.revision = 0,
    required this.modifiedAtMillis,
  })  : fields = validatedFields(fields),
        clocks = Map.unmodifiable(clocks) {
    validateOwner(ownerId);
    validateRecordId(id);
    if (fields['workspaceId'] is! String || fields['_deleted'] is! bool) {
      throw const FormatException(
          'Record is missing identity or deletion state.');
    }
    if (revision < 0 ||
        fields.keys.any((key) => !clocks.containsKey(key)) ||
        clocks.keys.any((key) => !fields.containsKey(key))) {
      throw const FormatException('Invalid record version.');
    }
    validateRecordId(workspaceId);
  }

  final String ownerId, id;
  final RecordKind kind;
  final Map<String, Object?> fields;
  final Map<String, VersionStamp> clocks;
  final int revision, modifiedAtMillis;
  String get key => '${kind.name}--$id';
  String get workspaceId => fields['workspaceId'] as String;
  bool get deleted => fields['_deleted'] == true;
  int get maxClock =>
      clocks.values.fold(0, (current, stamp) => max(current, stamp.counter));

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'ownerId': ownerId,
        'kind': kind.name,
        'id': id,
        'workspaceId': workspaceId,
        'fields': fields,
        'clocks': clocks.map((key, value) => MapEntry(key, value.toJson())),
        'revision': revision,
        'modifiedAtMillis': modifiedAtMillis,
      };

  factory WorkspaceRecord.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported record schema.');
    }
    final record = WorkspaceRecord(
      ownerId: json['ownerId'] as String,
      kind: RecordKind.values.byName(json['kind'] as String),
      id: json['id'] as String,
      fields: Map<String, Object?>.from(json['fields'] as Map),
      clocks: (json['clocks'] as Map).map((key, value) => MapEntry(
          key as String,
          VersionStamp.fromJson(Map<String, dynamic>.from(value as Map)))),
      revision: json['revision'] as int,
      modifiedAtMillis: json['modifiedAtMillis'] as int,
    );
    if (json['workspaceId'] != record.workspaceId) {
      throw const FormatException(
          'Workspace projection does not match record.');
    }
    return record;
  }
}

/// Merge independent fields, never a whole stale document. Deleted records stay
/// tombstoned until an explicit restore supplies a newer deletion-field clock.
WorkspaceRecord mergeRecords(WorkspaceRecord local, WorkspaceRecord incoming) {
  if (local.ownerId != incoming.ownerId || local.key != incoming.key) {
    throw const FormatException('Cannot merge different record identities.');
  }
  final fields = {...local.fields};
  final clocks = {...local.clocks};
  for (final entry in incoming.fields.entries) {
    final stamp = incoming.clocks[entry.key]!;
    final previous = clocks[entry.key];
    final comparison = previous == null ? 1 : stamp.compareTo(previous);
    if (comparison > 0) {
      fields[entry.key] = entry.value;
      clocks[entry.key] = stamp;
    } else if (comparison == 0 &&
        canonicalJson(fields[entry.key]) != canonicalJson(entry.value)) {
      throw const FormatException(
          'A version clock was reused for different data.');
    }
  }
  return WorkspaceRecord(
      ownerId: local.ownerId,
      kind: local.kind,
      id: local.id,
      fields: fields,
      clocks: clocks,
      revision: max(local.revision, incoming.revision),
      modifiedAtMillis: max(local.modifiedAtMillis, incoming.modifiedAtMillis));
}

class SyncOperation {
  SyncOperation(
      {required this.id,
      required this.ownerId,
      required this.kind,
      required this.recordId,
      required Map<String, Object?> patch,
      required this.stamp,
      required this.createdAtMillis,
      this.createOnly = false,
      this.attempts = 0,
      this.retryAtMillis = 0,
      this.errorCode})
      : patch = validatedFields(patch) {
    validateRecordId(id);
    validateRecordId(recordId);
    validateOwner(ownerId);
    if (patch.isEmpty || attempts < 0 || retryAtMillis < 0) {
      throw const FormatException('Invalid sync operation.');
    }
  }
  final String id, ownerId, recordId;
  final RecordKind kind;
  final Map<String, Object?> patch;
  final VersionStamp stamp;
  final int createdAtMillis, attempts, retryAtMillis;
  final String? errorCode;
  final bool createOnly;
  String get recordKey => '${kind.name}--$recordId';
  Map<String, Object?> get payload => {
        'id': id,
        'ownerId': ownerId,
        'kind': kind.name,
        'recordId': recordId,
        'patch': patch,
        'stamp': stamp.toJson(),
        'createdAtMillis': createdAtMillis,
        'createOnly': createOnly,
      };
  String get fingerprint =>
      sha256.convert(utf8.encode(canonicalJson(payload))).toString();
  Map<String, Object?> toJson() => {
        ...payload,
        'attempts': attempts,
        'retryAtMillis': retryAtMillis,
        'errorCode': errorCode
      };
  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
      id: json['id'] as String,
      ownerId: json['ownerId'] as String,
      kind: RecordKind.values.byName(json['kind'] as String),
      recordId: json['recordId'] as String,
      patch: Map<String, Object?>.from(json['patch'] as Map),
      stamp: VersionStamp.fromJson(
          Map<String, dynamic>.from(json['stamp'] as Map)),
      createdAtMillis: json['createdAtMillis'] as int,
      createOnly: json['createOnly'] == true,
      attempts: json['attempts'] as int? ?? 0,
      retryAtMillis: json['retryAtMillis'] as int? ?? 0,
      errorCode: json['errorCode'] as String?);
}

class OperationApplication {
  OperationApplication(
      this.record, List<String> accepted, List<String> rejected)
      : acceptedFields = List.unmodifiable(accepted),
        rejectedFields = List.unmodifiable(rejected);
  final WorkspaceRecord record;
  final List<String> acceptedFields, rejectedFields;
}

OperationApplication applyRecordOperation(
    WorkspaceRecord? previous, SyncOperation operation) {
  if (previous != null &&
      (previous.ownerId != operation.ownerId ||
          previous.key != operation.recordKey)) {
    throw const FormatException('Operation account or identity mismatch.');
  }
  if (previous != null && operation.createOnly) {
    return OperationApplication(previous, const [], const []);
  }
  final values = {...?previous?.fields};
  final clocks = {...?previous?.clocks};
  final accepted = <String>[], rejected = <String>[];
  for (final entry in operation.patch.entries) {
    final oldClock = clocks[entry.key];
    final order = oldClock == null ? 1 : operation.stamp.compareTo(oldClock);
    if (order > 0) {
      values[entry.key] = entry.value;
      clocks[entry.key] = operation.stamp;
      accepted.add(entry.key);
    } else if (order == 0 &&
        canonicalJson(values[entry.key]) != canonicalJson(entry.value)) {
      throw const FormatException(
          'A version clock was reused for different data.');
    } else if (order < 0) {
      rejected.add(entry.key);
    }
  }
  if (accepted.isEmpty && previous != null) {
    return OperationApplication(previous, accepted, rejected);
  }
  return OperationApplication(
      WorkspaceRecord(
          ownerId: operation.ownerId,
          kind: operation.kind,
          id: operation.recordId,
          fields: values,
          clocks: clocks,
          revision: (previous?.revision ?? 0) + 1,
          modifiedAtMillis:
              max(previous?.modifiedAtMillis ?? 0, operation.createdAtMillis)),
      accepted,
      rejected);
}

class SyncCursor {
  const SyncCursor(this.seconds, this.nanoseconds, this.documentId);
  final int seconds, nanoseconds;
  final String documentId;
  Map<String, Object> toJson() => {
        'seconds': seconds,
        'nanoseconds': nanoseconds,
        'documentId': documentId
      };
  factory SyncCursor.fromJson(Map<String, dynamic> json) => SyncCursor(
      json['seconds'] as int,
      json['nanoseconds'] as int,
      json['documentId'] as String);
}

class SyncSnapshot {
  const SyncSnapshot(
      {required this.pending,
      required this.failed,
      required this.needsAttention,
      this.lastSuccessMillis,
      this.lastErrorCode});
  final int pending, failed, needsAttention;
  final int? lastSuccessMillis;
  final String? lastErrorCode;
  bool get synchronized => pending == 0;
}
