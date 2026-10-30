import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';

import '../core/records.dart';
import '../domain/calendar_day.dart';
import '../domain/recurrence.dart';
import '../domain/task.dart';
import '../domain/task_occurrence.dart';
import 'productivity_database.dart';
import 'task_repository.dart';

class LegacyMigrationFailure implements Exception {
  const LegacyMigrationFailure(this.code);
  final String code;
  @override
  String toString() => 'LegacyMigrationFailure($code)';
}

/// A deterministic import of an immutable, server-fenced legacy snapshot.
/// Do not pass loadTasksForDate(): that method rolls over and writes the source.
class LegacyTaskMigration {
  LegacyTaskMigration._(
      this.sourceChecksum, this.records, this.taskCount, this.occurrenceCount);
  final String sourceChecksum;
  final List<RecordMutation> records;
  final int taskCount, occurrenceCount;
  static const workspaceId = 'personal';
  static const checkpointId = 'legacy_task_migration_v1';
  static String taskId(String sourceId) => _id('legacy-task', sourceId);
  static String seriesId(String sourceId) => _id('legacy-series', sourceId);
  static String _id(String namespace, String value) =>
      sha256.convert(utf8.encode('$namespace:$value')).toString();

  /// Input is portable JSON. The Firestore adapter must preserve Timestamp and
  /// other non-JSON values as explicitly tagged JSON before calling this method.
  factory LegacyTaskMigration.prepare(Map<String, Object?> snapshot) {
    if (snapshot['productivityMigrationVersion'] != 1) {
      throw const LegacyMigrationFailure('source-not-fenced');
    }
    final json = canonicalJson(snapshot);
    if (utf8.encode(json).length > 2 * 1024 * 1024) {
      throw const LegacyMigrationFailure('source-too-large');
    }
    final checksum = sha256.convert(utf8.encode(json)).toString();
    final planned = <String, RecordMutation>{};
    final series = <String, ProductivityTask>{};
    var taskCount = 0, occurrenceCount = 0;
    String requiredText(Map<String, dynamic> value, String key) {
      final field = value[key];
      if (field is! String || field.trim().isEmpty) {
        throw const LegacyMigrationFailure('invalid-source-field');
      }
      return field;
    }

    Map<String, dynamic> object(Object? value) {
      if (value is! Map<String, dynamic>) {
        throw const LegacyMigrationFailure('invalid-source-object');
      }
      return value;
    }

    Iterable<Object?> array(Object? value) {
      if (value == null) return const [];
      if (value is! List) {
        throw const LegacyMigrationFailure('invalid-source-array');
      }
      return value;
    }

    String shortTitle(String text) {
      if (text.length <= 500) return text;
      final title = StringBuffer();
      for (final character in text.characters) {
        if (title.length + character.length > 500) break;
        title.write(character);
      }
      return title.isEmpty ? 'Imported task' : title.toString();
    }

    void add(RecordKind kind, String id, Map<String, Object?> fields) {
      final key = '${kind.name}--$id';
      final previous = planned[key];
      if (previous != null) {
        if (canonicalJson(previous.patch) != canonicalJson(fields)) {
          throw const LegacyMigrationFailure('conflicting-source-identity');
        }
        return;
      }
      planned[key] = RecordMutation(
          kind: kind,
          id: id,
          workspaceId: workspaceId,
          patch: fields,
          ifAbsent: true);
      if (kind == RecordKind.task) taskCount++;
      if (kind == RecordKind.taskOccurrence) occurrenceCount++;
    }

    for (final raw in array(snapshot['recurringTasks'])) {
      final value = object(raw);
      final sourceId = requiredText(value, 'id');
      final text = requiredText(value, 'text');
      final start = CalendarDay.parse(requiredText(value, 'startDate'));
      final repeat = requiredText(value, 'repeat');
      if (repeat != 'daily' && repeat != 'weekly') {
        throw const LegacyMigrationFailure('unknown-recurrence');
      }
      final section = requiredText(value, 'section');
      final task = ProductivityTask(
          id: seriesId(sourceId),
          workspaceId: workspaceId,
          title: shortTitle(text),
          description: text.length > 500 ? text : '',
          priority:
              section == 'mustDo' ? TaskPriority.high : TaskPriority.normal,
          tags: [section],
          startDate: start,
          inbox: false,
          recurrence: RecurrenceRule(
              start: start,
              frequency: repeat == 'daily'
                  ? RecurrenceFrequency.daily
                  : RecurrenceFrequency.weekly));
      add(RecordKind.task, task.id, {...task.toFields(), 'legacy': value});
      series[sourceId] = task;
    }

    void importItem(Object? raw, String bucket, String section) {
      final value = object(raw);
      final sourceId = requiredText(value, 'id');
      final text = requiredText(value, 'text');
      if (value['completed'] is! bool) {
        throw const LegacyMigrationFailure('invalid-completion');
      }
      final complete = value['completed'] == true;
      final recurrenceId = value['recurrenceId'];
      final recurring = recurrenceId is String ? series[recurrenceId] : null;
      String? date =
          value['dueDate'] is String && (value['dueDate'] as String).isNotEmpty
              ? value['dueDate'] as String
              : value['dateCreated'] as String?;
      date = date == null || date.isEmpty
          ? snapshot['dateUpdated'] as String?
          : date;
      final day = date == null || date.isEmpty ? null : CalendarDay.parse(date);
      if (recurring != null) {
        if (day == null) {
          throw const LegacyMigrationFailure('missing-occurrence-date');
        }
        final occurrence = TaskOccurrence(
            id: TaskRepository.occurrenceId(recurring.id, day),
            workspaceId: workspaceId,
            taskId: recurring.id,
            day: day,
            status: complete ? TaskStatus.completed : TaskStatus.notStarted);
        add(RecordKind.taskOccurrence, occurrence.id, {
          ...occurrence.toFields(),
          'legacy': value,
          'legacyBucket': bucket
        });
      } else {
        final task = ProductivityTask(
            id: taskId(sourceId),
            workspaceId: workspaceId,
            title: shortTitle(text),
            description: text.length > 500 ? text : '',
            status: complete ? TaskStatus.completed : TaskStatus.notStarted,
            priority:
                section == 'mustDo' ? TaskPriority.high : TaskPriority.normal,
            tags: [section],
            scheduledDay: day,
            inbox: day == null);
        add(RecordKind.task, task.id,
            {...task.toFields(), 'legacy': value, 'legacyBucket': bucket});
      }
    }

    for (final bucket in ['todayTasks', 'missedTasks']) {
      if (snapshot[bucket] == null) continue;
      final buckets = object(snapshot[bucket]);
      for (final entry in buckets.entries) {
        for (final raw in array(entry.value)) {
          importItem(raw, bucket, entry.key);
        }
      }
    }
    for (final raw in array(snapshot['scheduledTasks'])) {
      final value = object(raw);
      importItem(value, 'scheduledTasks', requiredText(value, 'section'));
    }

    // Preserve every source field, including unknown legacy metadata, in bounded
    // Unicode-safe chunks. No timestamp or completed-time guess is introduced.
    final chunks = <String>[];
    final chunk = StringBuffer();
    for (final rune in json.runes) {
      chunk.writeCharCode(rune);
      if (chunk.length >= 16000) {
        chunks.add(chunk.toString());
        chunk.clear();
      }
    }
    if (chunk.isNotEmpty) chunks.add(chunk.toString());
    for (var index = 0; index < chunks.length; index++) {
      add(RecordKind.note, _id('legacy-backup-$checksum', '$index'), {
        'workspaceId': workspaceId,
        'type': 'legacyArchive',
        'title': 'Original tasks — part ${index + 1}',
        'body': chunks[index],
        'sourceChecksum': checksum,
        'partIndex': index,
        'partCount': chunks.length,
        'readOnly': true,
      });
    }
    return LegacyTaskMigration._(checksum, List.unmodifiable(planned.values),
        taskCount, occurrenceCount);
  }

  /// Interrupted batches can be replayed. Existing imported/user-edited records
  /// are create-only, and the final checkpoint is written only after every batch.
  Future<void> apply(ProductivityDatabase database) async {
    final checkpoint = await database.get(RecordKind.workspace, checkpointId);
    if (checkpoint != null) {
      if (checkpoint.fields['sourceChecksum'] != sourceChecksum) {
        throw const LegacyMigrationFailure('source-changed-after-cutover');
      }
      return;
    }
    for (var offset = 0; offset < records.length; offset += 200) {
      final end = offset + 200 < records.length ? offset + 200 : records.length;
      await database.mutateBatch(records.sublist(offset, end));
    }
    await database.mutate(
        kind: RecordKind.workspace,
        id: checkpointId,
        workspaceId: workspaceId,
        ifAbsent: true,
        patch: {
          'workspaceId': workspaceId,
          'type': 'migration',
          'version': 1,
          'sourceChecksum': sourceChecksum,
          'taskCount': taskCount,
          'occurrenceCount': occurrenceCount,
          'complete': true,
        });
  }
}
