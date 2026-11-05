import 'package:characters/characters.dart';

import '../core/records.dart';
import 'planning_time_zone.dart';
import 'stored_instant.dart';

/// A locally owned commitment. Instants are stored in UTC; the original IANA
/// zone remains with the event so its wall time survives travel and DST.
class CalendarEvent {
  CalendarEvent({
    required this.id,
    required this.workspaceId,
    required String title,
    required DateTime start,
    required DateTime end,
    required this.timeZone,
    this.notes = '',
  })  : title = title.trim(),
        start = start.toUtc(),
        end = end.toUtc() {
    validateRecordId(id);
    validateRecordId(workspaceId);
    if (this.title.isEmpty ||
        this.title.characters.length > 200 ||
        notes.length > 10000 ||
        !this.end.isAfter(this.start) ||
        this.end.difference(this.start) > const Duration(days: 366) ||
        timeZone.isEmpty ||
        timeZone.length > 100) {
      throw const FormatException('Invalid calendar event.');
    }
    try {
      PlanningTimeZone.location(timeZone);
    } catch (_) {
      throw const FormatException('Unknown event time zone.');
    }
  }

  final String id, workspaceId, title, timeZone, notes;
  final DateTime start, end;

  Map<String, Object?> toFields() => {
        'workspaceId': workspaceId,
        'title': title,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'timeZone': timeZone,
        'notes': notes,
      };

  factory CalendarEvent.fromRecord(WorkspaceRecord record) {
    if (record.kind != RecordKind.calendarEvent) {
      throw const FormatException('Not a calendar event.');
    }
    final fields = record.fields;
    return CalendarEvent(
      id: record.id,
      workspaceId: record.workspaceId,
      title: fields['title'] as String,
      start: parseStoredInstant(fields['start'] as String),
      end: parseStoredInstant(fields['end'] as String),
      timeZone: fields['timeZone'] as String,
      notes: fields['notes'] as String? ?? '',
    );
  }

  bool overlaps(CalendarEvent other) =>
      start.isBefore(other.end) && end.isAfter(other.start);
}
