import '../core/records.dart';
import '../domain/calendar_event.dart';
import '../domain/stored_instant.dart';
import 'productivity_database.dart';

class CalendarEventFailure implements Exception {
  const CalendarEventFailure(this.code);
  final String code;
}

class CalendarEventRepository {
  const CalendarEventRepository(this.database);
  final ProductivityDatabase database;

  Stream<List<CalendarEvent>> watchEvents() => database
      .watch(kind: RecordKind.calendarEvent)
      .map((records) => records.map(CalendarEvent.fromRecord).toList()
        ..sort((a, b) => a.start.compareTo(b.start)));

  Future<CalendarEvent> create(CalendarEvent event) async {
    final records = await database.changeRecords(
        kinds: const {RecordKind.calendarEvent},
        plan: (records) {
          if (records.any((record) => record.id == event.id)) {
            throw const CalendarEventFailure('already-exists');
          }
          return [
            RecordMutation(
                kind: RecordKind.calendarEvent,
                id: event.id,
                workspaceId: event.workspaceId,
                patch: event.toFields())
          ];
        });
    return CalendarEvent.fromRecord(records.single);
  }

  /// Applies only edited fields; validation and write share a transaction.
  Future<CalendarEvent> edit(String id, Map<String, Object?> patch) async {
    validateRecordId(id);
    const editable = {'title', 'start', 'end', 'timeZone', 'notes'};
    if (patch.isEmpty || patch.keys.any((key) => !editable.contains(key))) {
      throw const CalendarEventFailure('invalid-field');
    }
    CalendarEvent? unchanged;
    final records = await database.changeRecords(
        kinds: const {RecordKind.calendarEvent},
        plan: (records) {
          final current =
              records.where((record) => record.id == id).firstOrNull;
          if (current == null || current.deleted) {
            throw const CalendarEventFailure('not-found');
          }
          final combined = {...current.fields, ...patch};
          final candidate = CalendarEvent(
              id: id,
              workspaceId: current.workspaceId,
              title: combined['title'] as String,
              start: parseStoredInstant(combined['start'] as String),
              end: parseStoredInstant(combined['end'] as String),
              timeZone: combined['timeZone'] as String,
              notes: combined['notes'] as String? ?? '');
          final changed = <String, Object?>{};
          final normalized = candidate.toFields();
          for (final key in patch.keys) {
            if (current.fields[key] != normalized[key]) {
              changed[key] = normalized[key];
            }
          }
          if (changed.isEmpty) {
            unchanged = CalendarEvent.fromRecord(current);
            return [];
          }
          return [
            RecordMutation(
                kind: RecordKind.calendarEvent,
                id: id,
                workspaceId: current.workspaceId,
                patch: changed)
          ];
        });
    return unchanged ?? CalendarEvent.fromRecord(records.single);
  }

  Future<void> delete(String id) async {
    validateRecordId(id);
    await database.changeRecords(
        kinds: const {RecordKind.calendarEvent},
        plan: (records) {
          final current =
              records.where((record) => record.id == id).firstOrNull;
          if (current == null || current.deleted) return [];
          return [
            RecordMutation(
                kind: RecordKind.calendarEvent,
                id: id,
                workspaceId: current.workspaceId,
                patch: const {},
                deleted: true)
          ];
        });
  }
}
