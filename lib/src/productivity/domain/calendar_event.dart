import 'package:characters/characters.dart';

import '../core/records.dart';
import 'calendar_day.dart';
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
    CalendarDay.fromDate(this.start);
    CalendarDay.fromDate(this.end);
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
        // A time interval is one merge field. Independent start/end clocks
        // could otherwise converge to an invalid interval across devices.
        'interval': {
          'start': _utcString(start),
          'end': _utcString(end),
          'timeZone': timeZone,
        },
        'notes': notes,
      };

  factory CalendarEvent.fromRecord(WorkspaceRecord record) {
    if (record.kind != RecordKind.calendarEvent) {
      throw const FormatException('Not a calendar event.');
    }
    final fields = record.fields;
    // The initial hidden-workspace preview wrote separate time fields. It was
    // never shipped, but read it so existing developer backups still restore.
    final interval = fields['interval'] == null
        ? fields
        : Map<String, Object?>.from(fields['interval'] as Map);
    return CalendarEvent(
      id: record.id,
      workspaceId: record.workspaceId,
      title: fields['title'] as String,
      start: parseStoredInstant(interval['start'] as String),
      end: parseStoredInstant(interval['end'] as String),
      timeZone: interval['timeZone'] as String,
      notes: fields['notes'] as String? ?? '',
    );
  }

  bool overlaps(CalendarEvent other) =>
      start.isBefore(other.end) && end.isAfter(other.start);
}

// Fixed-width fractional seconds keep ISO UTC strings in chronological order
// for the Firestore rule's lexical interval comparison.
String _utcString(DateTime instant) {
  final utc = instant.toUtc();
  final prefix = utc.toIso8601String().split('.').first;
  final milliseconds = utc.millisecond.toString().padLeft(3, '0');
  final microseconds = utc.microsecond.toString().padLeft(3, '0');
  return '$prefix.$milliseconds${microseconds}Z';
}
