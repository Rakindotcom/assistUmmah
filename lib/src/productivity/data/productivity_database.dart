import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sembast/sembast.dart';

import '../core/records.dart';
import '../domain/calendar_event.dart';
import 'database_platform.dart';

class ProductivityDatabase {
  ProductivityDatabase._(this.uid, this._db, this.deviceId, this._clock);
  final String uid, deviceId;
  final Database _db;
  final DateTime Function() _clock;
  static final _records = stringMapStoreFactory.store('records');
  static final _outbox = stringMapStoreFactory.store('outbox');
  static final _changes = stringMapStoreFactory.store('changes');
  static final _conflicts = stringMapStoreFactory.store('conflicts');
  static final _meta = StoreRef<String, Object?>('metadata');

  /// Close the account's active session before deleting its local database.
  static Future<void> eraseAccountData(String uid,
      {DatabaseFactory? factory, String? path}) async {
    validateOwner(uid);
    if ((factory == null) != (path == null)) {
      throw ArgumentError('Pass both a database factory and path.');
    }
    if (factory == null) {
      final location = await productivityDatabaseLocation(
          sha256.convert(utf8.encode(uid)).toString());
      factory = location.$1;
      path = location.$2;
    }
    await factory.deleteDatabase(path!);
  }

  static Future<ProductivityDatabase> open(
      {required String uid,
      DatabaseFactory? factory,
      String? path,
      DateTime Function()? clock}) async {
    validateOwner(uid);
    if ((factory == null) != (path == null)) {
      throw ArgumentError('Pass both a database factory and path.');
    }
    if (factory == null) {
      final location = await productivityDatabaseLocation(
          sha256.convert(utf8.encode(uid)).toString());
      factory = location.$1;
      path = location.$2;
    }
    final db = await factory.openDatabase(path!, version: 1);
    try {
      final device = await db.transaction((transaction) async {
        final owner = await _meta.record('owner').get(transaction);
        if (owner != null && owner != uid) {
          throw StateError(
              'A local database cannot be opened for another account.');
        }
        await _meta.record('owner').put(transaction, uid);
        final existing =
            await _meta.record('device').get(transaction) as String?;
        final device = existing ?? newRecordId();
        await _meta.record('device').put(transaction, device);
        return device;
      });
      return ProductivityDatabase._(uid, db, device, clock ?? DateTime.now);
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  Future<bool> get frozen async =>
      await _meta.record('frozen').get(_db) == true;
  Future<void> freeze() => _db.transaction((transaction) async {
        await _meta.record('frozen').put(transaction, true);
      });

  Future<void> _assertWritable(DatabaseClient transaction) async {
    if (await _meta.record('frozen').get(transaction) == true) {
      throw StateError('Account data is frozen for deletion.');
    }
  }

  Future<WorkspaceRecord?> get(RecordKind kind, String id) async {
    final raw = await _records.record('${kind.name}--$id').get(_db);
    return raw == null ? null : _decode(raw);
  }

  WorkspaceRecord _decode(Map<String, Object?> json) {
    final record = WorkspaceRecord.fromJson(json);
    if (record.ownerId != uid) {
      throw StateError('Record belongs to another account.');
    }
    return record;
  }

  Future<List<WorkspaceRecord>> list(
      {RecordKind? kind,
      String? workspaceId,
      bool includeDeleted = false}) async {
    final records = await _records.find(_db,
        finder: kind == null
            ? null
            : Finder(filter: Filter.equals('kind', kind.name)));
    return records
        .map((row) => _decode(row.value))
        .where((record) =>
            (includeDeleted || !record.deleted) &&
            (workspaceId == null || record.workspaceId == workspaceId))
        .toList(growable: false);
  }

  Stream<List<WorkspaceRecord>> watch(
          {RecordKind? kind,
          String? workspaceId,
          bool includeDeleted = false}) =>
      _records
          .query(
              finder: kind == null
                  ? null
                  : Finder(filter: Filter.equals('kind', kind.name)))
          .onSnapshots(_db)
          .map((rows) => rows
              .map((row) => _decode(row.value))
              .where((record) =>
                  (includeDeleted || !record.deleted) &&
                  (workspaceId == null || record.workspaceId == workspaceId))
              .toList(growable: false));

  /// Watches a bounded set of record kinds across this account's workspaces.
  /// Useful for planning views that must not treat each workspace as having
  /// an independent daily capacity.
  Stream<List<WorkspaceRecord>> watchKinds(Set<RecordKind> kinds,
      {bool includeDeleted = false}) {
    if (kinds.isEmpty) throw ArgumentError.value(kinds, 'kinds');
    return _records
        .query(
            finder: Finder(
                filter: Filter.inList(
                    'kind', kinds.map((kind) => kind.name).toList())))
        .onSnapshots(_db)
        .map((rows) => rows
            .map((row) => _decode(row.value))
            .where((record) => includeDeleted || !record.deleted)
            .toList(growable: false));
  }

  /// Record, audit entry, clock and outbox commit together before returning.
  Future<WorkspaceRecord> mutate(
          {required RecordKind kind,
          required String id,
          required String workspaceId,
          required Map<String, Object?> patch,
          bool? deleted,
          bool ifAbsent = false}) async =>
      (await mutateBatch([
        RecordMutation(
            kind: kind,
            id: id,
            workspaceId: workspaceId,
            patch: patch,
            deleted: deleted,
            ifAbsent: ifAbsent),
      ]))
          .single;

  Future<List<WorkspaceRecord>> mutateBatch(List<RecordMutation> mutations) {
    if (mutations.length > 1000) {
      throw ArgumentError('Mutation batch is too large.');
    }
    final identifiers = List.generate(mutations.length, (_) => newRecordId());
    final now = _clock().toUtc().millisecondsSinceEpoch;
    return _db.transaction((transaction) async {
      await _assertWritable(transaction);
      final result = <WorkspaceRecord>[];
      for (var index = 0; index < mutations.length; index++) {
        result.add(await _commit(
            transaction, mutations[index], identifiers[index], now));
      }
      return result;
    });
  }

  /// Read-dependent domain decisions and their writes share one transaction.
  /// The planner must be pure: IndexedDB can retry it after a competing tab.
  /// Include deleted records when checking identity/reference invariants.
  Future<List<WorkspaceRecord>> changeRecords({
    required Set<RecordKind> kinds,
    required List<RecordMutation> Function(List<WorkspaceRecord>) plan,
  }) {
    final identifiers = <String>[];
    final now = _clock().toUtc().millisecondsSinceEpoch;
    return _db.transaction((transaction) async {
      await _assertWritable(transaction);
      final rows = await _records.find(transaction,
          finder: Finder(
              filter:
                  Filter.inList('kind', kinds.map((k) => k.name).toList())));
      final records = List<WorkspaceRecord>.unmodifiable(
          rows.map((row) => _decode(row.value)));
      final mutations = plan(records);
      if (mutations.length > 1000 ||
          mutations.any((mutation) => !kinds.contains(mutation.kind))) {
        throw ArgumentError('Invalid domain transaction.');
      }
      while (identifiers.length < mutations.length) {
        identifiers.add(newRecordId());
      }
      final result = <WorkspaceRecord>[];
      for (var index = 0; index < mutations.length; index++) {
        result.add(await _commit(
            transaction, mutations[index], identifiers[index], now));
      }
      return result;
    });
  }

  Future<WorkspaceRecord> _commit(DatabaseClient transaction,
      RecordMutation mutation, String operationId, int now) async {
    final key = '${mutation.kind.name}--${mutation.id}';
    final raw = await _records.record(key).get(transaction);
    final previous = raw == null ? null : _decode(raw);
    if (previous != null && mutation.ifAbsent) return previous;
    final changes = validatedFields({
      if (previous == null) 'workspaceId': mutation.workspaceId,
      if (previous == null || mutation.deleted != null)
        '_deleted': mutation.deleted ?? false,
      ...mutation.patch,
    });
    if (previous != null &&
        previous.workspaceId != mutation.workspaceId &&
        changes['workspaceId'] != mutation.workspaceId) {
      throw ArgumentError(
          'Changing workspace requires an explicit workspaceId patch.');
    }
    if (changes.isEmpty) throw ArgumentError('No fields changed.');
    final counter =
        (await _meta.record('clock').get(transaction) as int? ?? 0) + 1;
    final stamp = VersionStamp(counter, deviceId);
    final record = WorkspaceRecord(
        ownerId: uid,
        kind: mutation.kind,
        id: mutation.id,
        fields: {...?previous?.fields, ...changes},
        clocks: {
          ...?previous?.clocks,
          for (final key in changes.keys) key: stamp
        },
        revision: previous?.revision ?? 0,
        modifiedAtMillis: now);
    final operation = SyncOperation(
        id: operationId,
        ownerId: uid,
        kind: mutation.kind,
        recordId: mutation.id,
        patch: changes,
        stamp: stamp,
        createdAtMillis: now,
        createOnly: mutation.ifAbsent && previous == null);
    await _records.record(key).put(transaction, record.toJson());
    await _outbox.record(operationId).put(transaction, operation.toJson());
    for (final field in changes.keys) {
      await _conflicts.record('$key--$field').delete(transaction);
    }
    await _changes.record(operationId).put(transaction, {
      ...operation.payload,
      'before': previous?.toJson(),
      'source': 'local',
    });
    await _meta.record('clock').put(transaction, counter);
    return record;
  }

  /// Consistent logical backup, including unsynced values, trash and local
  /// history. It contains no authentication token or provider credential.
  Future<String> exportArchive() => _db.transaction((transaction) async {
        final records = await _records.find(transaction,
            finder: Finder(sortOrders: [SortOrder(Field.key)]));
        final changes = await _changes.find(transaction,
            finder: Finder(sortOrders: [SortOrder(Field.key)]));
        final conflicts = await _conflicts.find(transaction,
            finder: Finder(sortOrders: [SortOrder(Field.key)]));
        final payload = <String, Object?>{
          'format': 'rober-pothe-workspace',
          'formatVersion': 2,
          'ownerId': uid,
          'exportedAt': _clock().toUtc().toIso8601String(),
          'records': records.map((row) => _decode(row.value).toJson()).toList(),
          'history': changes.map((row) => row.value).toList(),
          'conflicts': conflicts
              .map((row) => FieldConflict.fromJson(row.value).toJson())
              .toList(),
        };
        return jsonEncode({
          ...payload,
          'checksum':
              sha256.convert(utf8.encode(canonicalJson(payload))).toString()
        });
      });

  /// Validates the complete archive before an atomic merge. New logical clocks
  /// make restored values proper edits; retrying the same file is a no-op.
  Future<int> importArchive(String source,
      {void Function(List<WorkspaceRecord>)? validateRecords}) async {
    if (utf8.encode(source).length > 25 * 1024 * 1024) {
      throw const FormatException('Backup exceeds the 25 MB import limit.');
    }
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic> ||
        data['format'] != 'rober-pothe-workspace' ||
        (data['formatVersion'] != 1 && data['formatVersion'] != 2) ||
        data['ownerId'] != uid ||
        data['records'] is! List ||
        data['history'] is! List ||
        (data['formatVersion'] == 2 && data['conflicts'] is! List)) {
      throw const FormatException('Unsupported backup or a different account.');
    }
    final payload = {...data}..remove('checksum');
    if (data['checksum'] !=
        sha256.convert(utf8.encode(canonicalJson(payload))).toString()) {
      throw const FormatException('Backup checksum does not match.');
    }
    final rawRecords = data['records'] as List;
    if (rawRecords.length > 20000) {
      throw const FormatException('Too many records in backup.');
    }
    final records = rawRecords
        .map((raw) =>
            WorkspaceRecord.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList(growable: false);
    if (records.any((record) => record.ownerId != uid) ||
        records.map((record) => record.key).toSet().length != records.length) {
      throw const FormatException(
          'Backup contains mixed owners or duplicate records.');
    }
    validateRecords?.call(List.unmodifiable(records));
    final recordsByKey = {for (final record in records) record.key: record};
    final history = (data['history'] as List).map((raw) {
      final item = Map<String, Object?>.from(raw as Map);
      final operation = SyncOperation.fromJson(item);
      if (operation.ownerId != uid || item['source'] != 'local') {
        throw const FormatException('Invalid backup history.');
      }
      if (item['before'] != null) {
        final before = WorkspaceRecord.fromJson(
            Map<String, dynamic>.from(item['before'] as Map));
        if (before.ownerId != uid ||
            before.id != operation.recordId ||
            before.kind != operation.kind) {
          throw const FormatException('Invalid backup history identity.');
        }
        validateRecords?.call([before]);
        validateRecords?.call([applyRecordOperation(before, operation).record]);
      } else {
        validateRecords?.call([applyRecordOperation(null, operation).record]);
      }
      return item;
    }).toList(growable: false);
    final rawConflicts = data['formatVersion'] == 2
        ? data['conflicts'] as List
        : const <Object?>[];
    if (rawConflicts.length > 20000) {
      throw const FormatException('Too many conflicts in backup.');
    }
    final historyById = {for (final item in history) item['id']: item};
    if (historyById.length != history.length) {
      throw const FormatException('Duplicate change history in backup.');
    }
    final conflicts = rawConflicts.map((raw) {
      try {
        final conflict =
            FieldConflict.fromJson(Map<String, dynamic>.from(raw as Map));
        final source = recordsByKey[conflict.recordKey];
        final origin = historyById[conflict.operationId];
        final patch = origin?['patch'];
        final rejected = origin?['rejectedFields'];
        if (source == null ||
            source.workspaceId != conflict.workspaceId ||
            source.clocks[conflict.field] != conflict.cloudStamp ||
            canonicalJson(source.fields[conflict.field]) !=
                canonicalJson(conflict.cloudValue) ||
            origin?['kind'] != conflict.kind.name ||
            origin?['recordId'] != conflict.recordId ||
            patch is! Map ||
            !patch.containsKey(conflict.field) ||
            canonicalJson(patch[conflict.field]) !=
                canonicalJson(conflict.localValue) ||
            rejected is! List ||
            !rejected.contains(conflict.field)) {
          throw const FormatException('Invalid conflict in backup.');
        }
        return conflict;
      } on TypeError {
        throw const FormatException('Invalid conflict in backup.');
      } on ArgumentError {
        throw const FormatException('Invalid conflict in backup.');
      }
    }).toList(growable: false);
    if (conflicts.map((conflict) => conflict.key).toSet().length !=
        conflicts.length) {
      throw const FormatException('Duplicate conflict in backup.');
    }
    final identifiers = List.generate(records.length, (_) => newRecordId());
    final now = _clock().toUtc().millisecondsSinceEpoch;
    return _db.transaction((transaction) async {
      await _assertWritable(transaction);
      var logical = await _meta.record('clock').get(transaction) as int? ?? 0;
      for (final record in records) {
        logical = max(logical, record.maxClock);
      }
      await _meta.record('clock').put(transaction, logical);
      var changed = 0;
      for (var index = 0; index < records.length; index++) {
        final record = records[index];
        final old = await _records.record(record.key).get(transaction);
        final previous = old == null ? null : _decode(old);
        final patch = <String, Object?>{
          for (final entry in record.fields.entries)
            if (entry.key != '_deleted' &&
                (previous == null ||
                    canonicalJson(previous.fields[entry.key]) !=
                        canonicalJson(entry.value)))
              entry.key: entry.value,
        };
        final deletion = previous == null || previous.deleted != record.deleted
            ? record.deleted
            : null;
        if (patch.isEmpty && deletion == null) continue;
        await _commit(
            transaction,
            RecordMutation(
                kind: record.kind,
                id: record.id,
                workspaceId: record.workspaceId,
                patch: patch,
                deleted: deletion),
            identifiers[index],
            now);
        changed++;
      }
      for (final entry in history) {
        final key = entry['id'] as String;
        if (!await _changes.record(key).exists(transaction)) {
          await _changes.record(key).put(transaction, entry);
        }
      }
      for (final conflict in conflicts) {
        if (await _conflicts.record(conflict.key).exists(transaction)) continue;
        final raw = await _records.record(conflict.recordKey).get(transaction);
        if (raw == null) {
          throw const FormatException('Conflict record is missing.');
        }
        final current = _decode(raw);
        final stamp = current.clocks[conflict.field];
        if (stamp == null) {
          throw const FormatException('Conflict field is missing.');
        }
        await _conflicts.record(conflict.key).put(
            transaction,
            FieldConflict(
                    kind: conflict.kind,
                    recordId: conflict.recordId,
                    workspaceId: current.workspaceId,
                    field: conflict.field,
                    localValue: conflict.localValue,
                    cloudValue: current.fields[conflict.field],
                    cloudStamp: stamp,
                    operationId: conflict.operationId,
                    createdAtMillis: conflict.createdAtMillis)
                .toJson());
      }
      return changed;
    });
  }

  Future<List<SyncOperation>> pending(
      {int limit = 50, bool includeDelayed = false}) async {
    final rows = await _outbox.find(_db,
        finder: Finder(
          sortOrders: [SortOrder('stamp.counter'), SortOrder('id')],
        ));
    // The first operation for a record must be acknowledged before a later
    // patch can be sent. A rejected create must never turn its next patch into
    // an incomplete remote record. Other records remain independently usable.
    final earliest = <String, SyncOperation>{};
    final attention = <String>{};
    for (final row in rows) {
      final operation = SyncOperation.fromJson(row.value);
      earliest.putIfAbsent(operation.recordKey, () => operation);
      if (row.value['needsAttention'] == true) {
        attention.add(operation.recordKey);
      }
    }
    final now = _clock().toUtc().millisecondsSinceEpoch;
    return earliest.entries
        .where((entry) =>
            !attention.contains(entry.key) &&
            (includeDelayed || entry.value.retryAtMillis <= now))
        .map((entry) => entry.value)
        .take(limit)
        .toList(growable: false);
  }

  Future<List<SyncOperation>> queued() async {
    final rows = await _outbox.find(_db,
        finder:
            Finder(sortOrders: [SortOrder('stamp.counter'), SortOrder('id')]));
    return rows
        .map((row) => SyncOperation.fromJson(row.value))
        .toList(growable: false);
  }

  /// Explicitly rejected operations stay intact for a future conflict review.
  Future<List<SyncOperation>> attention() async {
    final rows = await _outbox.find(_db,
        finder: Finder(filter: Filter.equals('needsAttention', true)));
    return rows
        .map((row) => SyncOperation.fromJson(row.value))
        .toList(growable: false);
  }

  Future<List<FieldConflict>> fieldConflicts() async {
    final rows = await _conflicts.find(_db,
        finder: Finder(sortOrders: [SortOrder('createdAtMillis')]));
    return rows
        .map((row) => FieldConflict.fromJson(row.value))
        .toList(growable: false);
  }

  Future<void> keepCloudValue(FieldConflict expected) =>
      _db.transaction((transaction) async {
        await _assertWritable(transaction);
        final current = await _currentConflict(transaction, expected);
        await _conflicts.record(current.key).delete(transaction);
        await _changes.record(current.operationId).update(transaction, {
          'conflictResolution': 'cloud',
        });
      });

  /// Reapply an explicitly reviewed value with a fresh logical clock. A cloud
  /// update during review invalidates the selection and requires a fresh look.
  Future<SyncOperation> retryMyValue(
    FieldConflict expected, {
    required void Function(WorkspaceRecord, List<WorkspaceRecord>) validate,
  }) {
    final operationId = newRecordId();
    final now = _clock().toUtc().millisecondsSinceEpoch;
    return _db.transaction((transaction) async {
      await _assertWritable(transaction);
      final conflict = await _currentConflict(transaction, expected);
      final raw = await _records.record(conflict.recordKey).get(transaction);
      if (raw == null) throw StateError('Conflicted record is missing.');
      final record = _decode(raw);
      if (record.clocks[conflict.field] != conflict.cloudStamp ||
          canonicalJson(record.fields[conflict.field]) !=
              canonicalJson(conflict.cloudValue)) {
        throw StateError('The record changed during conflict review.');
      }
      final candidate = WorkspaceRecord(
          ownerId: uid,
          kind: record.kind,
          id: record.id,
          fields: {
            ...record.fields,
            conflict.field: conflict.localValue,
          },
          clocks: record.clocks,
          revision: record.revision,
          modifiedAtMillis: now);
      final rows = await _records.find(transaction);
      validate(
          candidate, List.unmodifiable(rows.map((row) => _decode(row.value))));
      final mutation = RecordMutation(
          kind: record.kind,
          id: record.id,
          workspaceId: candidate.workspaceId,
          patch: conflict.field == '_deleted'
              ? const {}
              : {conflict.field: conflict.localValue},
          deleted: conflict.field == '_deleted'
              ? conflict.localValue as bool
              : null);
      await _commit(transaction, mutation, operationId, now);
      await _changes.record(operationId).update(transaction, {
        'reason': 'field-conflict-review',
        'reviewedOperationId': conflict.operationId,
      });
      final queued = await _outbox.record(operationId).get(transaction);
      return SyncOperation.fromJson(queued!);
    });
  }

  Future<FieldConflict> _currentConflict(
      DatabaseClient transaction, FieldConflict expected) async {
    final raw = await _conflicts.record(expected.key).get(transaction);
    if (raw == null) throw StateError('Conflict is already resolved.');
    final current = FieldConflict.fromJson(raw);
    if (current.operationId != expected.operationId ||
        current.cloudStamp != expected.cloudStamp ||
        current.workspaceId != expected.workspaceId ||
        canonicalJson(current.cloudValue) !=
            canonicalJson(expected.cloudValue) ||
        canonicalJson(current.localValue) !=
            canonicalJson(expected.localValue)) {
      throw StateError('Conflict changed during review.');
    }
    return current;
  }

  /// Called only after a user reviews and corrects a graph conflict. The old
  /// operations were rejected before a server write; their immutable audit
  /// entries remain, while one fresh patch includes every unsynced field.
  Future<SyncOperation> resubmitTaskGraphConflict(
    String taskId, {
    required void Function(WorkspaceRecord, List<WorkspaceRecord>) validate,
  }) {
    validateRecordId(taskId);
    final operationId = newRecordId();
    final now = _clock().toUtc().millisecondsSinceEpoch;
    return _db.transaction((transaction) async {
      await _assertWritable(transaction);
      final key = '${RecordKind.task.name}--$taskId';
      final raw = await _records.record(key).get(transaction);
      if (raw == null) throw StateError('Task no longer exists.');
      final record = _decode(raw);
      final rows = await _records.find(transaction);
      validate(
          record, List.unmodifiable(rows.map((row) => _decode(row.value))));
      final outbox = await _outbox.find(transaction,
          finder: Finder(sortOrders: [SortOrder('stamp.counter')]));
      final operations = outbox
          .map((row) => (row.value, SyncOperation.fromJson(row.value)))
          .where((entry) => entry.$2.recordKey == key)
          .toList(growable: false);
      const recoverable = {
        'circular-reference',
        'different-workspace',
        'invalid-task'
      };
      final rejected = operations
          .where((entry) => entry.$1['needsAttention'] == true)
          .toList(growable: false);
      if (rejected.isEmpty ||
          rejected.any((entry) => !recoverable.contains(entry.$2.errorCode))) {
        throw StateError('This task has no reviewed graph conflict.');
      }
      final fields = <String>{
        for (final entry in operations) ...entry.$2.patch.keys
      };
      final patch = {
        for (final field in fields) field: record.fields[field],
      };
      final counter = max(
              await _meta.record('clock').get(transaction) as int? ?? 0,
              record.maxClock) +
          1;
      final stamp = VersionStamp(counter, deviceId);
      final rebased = WorkspaceRecord(
          ownerId: uid,
          kind: record.kind,
          id: record.id,
          fields: record.fields,
          clocks: {
            ...record.clocks,
            for (final field in fields) field: stamp,
          },
          revision: record.revision,
          modifiedAtMillis: now);
      final operation = SyncOperation(
          id: operationId,
          ownerId: uid,
          kind: RecordKind.task,
          recordId: taskId,
          patch: patch,
          stamp: stamp,
          createdAtMillis: now);
      for (final entry in operations) {
        await _outbox.record(entry.$2.id).delete(transaction);
        await _changes.record(entry.$2.id).update(transaction, {
          'supersededBy': operationId,
        });
      }
      await _records.record(key).put(transaction, rebased.toJson());
      await _outbox.record(operationId).put(transaction, operation.toJson());
      await _changes.record(operationId).put(transaction, {
        ...operation.payload,
        'before': record.toJson(),
        'source': 'local',
        'reason': 'graph-conflict-review',
        'supersedes': operations.map((entry) => entry.$2.id).toList(),
      });
      await _meta.record('clock').put(transaction, counter);
      return operation;
    });
  }

  Future<void> _merge(
      DatabaseClient transaction, WorkspaceRecord incoming) async {
    if (incoming.ownerId != uid) throw StateError('Remote account mismatch.');
    final old = await _records.record(incoming.key).get(transaction);
    final merged =
        old == null ? incoming : mergeRecords(_decode(old), incoming);
    if (merged.kind == RecordKind.calendarEvent) {
      CalendarEvent.fromRecord(merged);
    }
    await _records.record(merged.key).put(transaction, merged.toJson());
    for (final entry in incoming.fields.entries) {
      final conflictKey = '${incoming.key}--${entry.key}';
      final rawConflict = await _conflicts.record(conflictKey).get(transaction);
      if (rawConflict == null) continue;
      final conflict = FieldConflict.fromJson(rawConflict);
      final incomingStamp = incoming.clocks[entry.key]!;
      if (incomingStamp.compareTo(conflict.cloudStamp) > 0) {
        await _conflicts.record(conflictKey).put(
            transaction,
            FieldConflict(
              kind: conflict.kind,
              recordId: conflict.recordId,
              workspaceId: incoming.workspaceId,
              field: conflict.field,
              localValue: conflict.localValue,
              cloudValue: entry.value,
              cloudStamp: incomingStamp,
              operationId: conflict.operationId,
              createdAtMillis: conflict.createdAtMillis,
            ).toJson());
      }
    }
    final current = await _meta.record('clock').get(transaction) as int? ?? 0;
    await _meta
        .record('clock')
        .put(transaction, max(current, incoming.maxClock));
  }

  Future<void> acknowledge(SyncOperation operation, WorkspaceRecord canonical,
          {List<String> rejectedFields = const []}) =>
      _db.transaction((transaction) async {
        await _assertWritable(transaction);
        if (operation.ownerId != uid || operation.recordKey != canonical.key) {
          throw StateError('Sync acknowledgement identity mismatch.');
        }
        final rawLocal = await _records.record(canonical.key).get(transaction);
        final local = rawLocal == null ? null : _decode(rawLocal);
        if (operation.createOnly) {
          // Drop unaccepted initialization clocks while preserving real local
          // edits made after this generated record was first queued.
          final raw = await _records.record(canonical.key).get(transaction);
          if (raw != null) {
            final local = _decode(raw);
            final retained = local.fields.keys.where(
                (key) => local.clocks[key]!.compareTo(operation.stamp) != 0);
            final rebased = WorkspaceRecord(
                ownerId: uid,
                kind: canonical.kind,
                id: canonical.id,
                fields: {
                  ...canonical.fields,
                  for (final key in retained) key: local.fields[key]
                },
                clocks: {
                  ...canonical.clocks,
                  for (final key in retained) key: local.clocks[key]!
                },
                revision: max(local.revision, canonical.revision),
                modifiedAtMillis:
                    max(local.modifiedAtMillis, canonical.modifiedAtMillis));
            await _records
                .record(canonical.key)
                .put(transaction, mergeRecords(rebased, canonical).toJson());
          }
        }
        await _merge(transaction, canonical);
        for (final field in rejectedFields) {
          if (!operation.patch.containsKey(field) ||
              local?.clocks[field] != operation.stamp ||
              !canonical.clocks.containsKey(field) ||
              canonicalJson(operation.patch[field]) ==
                  canonicalJson(canonical.fields[field])) {
            continue;
          }
          final conflict = FieldConflict(
              kind: operation.kind,
              recordId: operation.recordId,
              workspaceId: canonical.workspaceId,
              field: field,
              localValue: operation.patch[field],
              cloudValue: canonical.fields[field],
              cloudStamp: canonical.clocks[field]!,
              operationId: operation.id,
              createdAtMillis: _clock().toUtc().millisecondsSinceEpoch);
          await _conflicts
              .record(conflict.key)
              .put(transaction, conflict.toJson());
        }
        await _outbox.record(operation.id).delete(transaction);
        await _changes.record(operation.id).update(transaction, {
          'acknowledged': true,
          'rejectedFields': rejectedFields,
          'remoteRevision': canonical.revision,
        });
      });

  Future<SyncCursor?> get cursor async {
    final value = await _meta.record('cursor').get(_db);
    return value == null
        ? null
        : SyncCursor.fromJson(Map<String, dynamic>.from(value as Map));
  }

  Future<void> acceptPage(List<WorkspaceRecord> records, SyncCursor? cursor) =>
      _db.transaction((transaction) async {
        await _assertWritable(transaction);
        for (final record in records) {
          await _merge(transaction, record);
        }
        if (cursor != null) {
          await _meta.record('cursor').put(transaction, cursor.toJson());
        }
      });

  Future<void> recordFailure(SyncOperation operation, String code,
          {bool permanent = false}) =>
      _db.transaction((transaction) async {
        final raw = await _outbox.record(operation.id).get(transaction);
        if (raw == null) return;
        final attempt = (raw['attempts'] as int? ?? 0) + 1;
        final delay = permanent
            ? const Duration(hours: 24)
            : Duration(seconds: min(900, 5 * (1 << min(attempt - 1, 8))));
        await _outbox.record(operation.id).update(transaction, {
          'attempts': attempt,
          'errorCode': code,
          'needsAttention': permanent,
          'retryAtMillis': _clock().toUtc().add(delay).millisecondsSinceEpoch,
        });
        await _meta.record('lastErrorCode').put(transaction, code);
      });

  Future<void> recordSyncSuccess() => _db.transaction((transaction) async {
        await _meta
            .record('lastSuccess')
            .put(transaction, _clock().toUtc().millisecondsSinceEpoch);
        await _meta.record('lastErrorCode').delete(transaction);
      });

  Future<SyncSnapshot> syncSnapshot() async {
    final rows = await _outbox.find(_db);
    final conflicts = await _conflicts.count(_db);
    return SyncSnapshot(
        pending: rows.length,
        failed: rows
            .where((row) => (row.value['attempts'] as int? ?? 0) > 0)
            .length,
        needsAttention:
            rows.where((row) => row.value['needsAttention'] == true).length +
                conflicts,
        lastSuccessMillis: await _meta.record('lastSuccess').get(_db) as int?,
        lastErrorCode: await _meta.record('lastErrorCode').get(_db) as String?);
  }

  Stream<SyncSnapshot> watchSync() => Stream<SyncSnapshot>.multi((controller) {
        var canceled = false;
        var generation = 0;
        Future<void> emit() async {
          final request = ++generation;
          try {
            final snapshot = await syncSnapshot();
            if (!canceled && request == generation) controller.add(snapshot);
          } catch (error, stack) {
            if (!canceled) controller.addError(error, stack);
          }
        }

        final outbox = _outbox
            .query()
            .onSnapshots(_db)
            .listen((_) => unawaited(emit()), onError: controller.addError);
        final metadata = _meta
            .query()
            .onSnapshots(_db)
            .listen((_) => unawaited(emit()), onError: controller.addError);
        final conflicts = _conflicts
            .query()
            .onSnapshots(_db)
            .listen((_) => unawaited(emit()), onError: controller.addError);
        controller.onCancel = () async {
          canceled = true;
          await outbox.cancel();
          await metadata.cancel();
          await conflicts.cancel();
        };
      });

  Future<List<Map<String, Object?>>> history(
          RecordKind kind, String id) async =>
      (await _changes.find(_db,
              finder: Finder(
                  filter: Filter.and([
                    Filter.equals('kind', kind.name),
                    Filter.equals('recordId', id)
                  ]),
                  sortOrders: [SortOrder('stamp.counter', false)])))
          .map((row) => row.value)
          .toList(growable: false);

  Future<void> close() => _db.close();
}

class RecordMutation {
  RecordMutation(
      {required this.kind,
      required this.id,
      required this.workspaceId,
      required Map<String, Object?> patch,
      this.deleted,
      this.ifAbsent = false})
      : patch = validatedFields(patch) {
    validateRecordId(id);
    validateRecordId(workspaceId);
    if (patch.containsKey('_deleted')) {
      throw ArgumentError('Use the explicit delete/restore argument.');
    }
    if (patch.containsKey('workspaceId') &&
        patch['workspaceId'] != workspaceId) {
      throw ArgumentError('Workspace argument and patch must agree.');
    }
  }
  final RecordKind kind;
  final String id, workspaceId;
  final Map<String, Object?> patch;
  final bool? deleted;
  final bool ifAbsent;
}
