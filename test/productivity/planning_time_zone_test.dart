import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/planning_time_zone.dart';
import 'package:ummah_assist/src/productivity/domain/stored_instant.dart';

void main() {
  test('stored instants reject missing offsets and normalized invalid dates',
      () {
    expect(parseStoredInstant('2026-10-30T09:15:00.123Z'),
        DateTime.utc(2026, 10, 30, 9, 15, 0, 123));
    expect(
        () => parseStoredInstant('2026-10-30T09:15:00'), throwsFormatException);
    expect(() => parseStoredInstant('2026-02-30T09:15:00Z'),
        throwsFormatException);
    expect(() => parseStoredInstant('2026-10-30T25:15:00Z'),
        throwsFormatException);
  });
  test('Bangladesh wall time resolves independently of the device timezone',
      () {
    expect(
        PlanningTimeZone.candidates(
            CalendarDay(2026, 10, 30), 9, 15, 'Asia/Dhaka'),
        [DateTime.utc(2026, 10, 30, 3, 15)]);
  });
  test('DST spring gap is empty rather than silently becoming a later meeting',
      () {
    expect(
        PlanningTimeZone.candidates(
            CalendarDay(2026, 3, 8), 2, 30, 'America/New_York'),
        isEmpty);
  });
  test('DST fall overlap returns both instants in chronological order', () {
    expect(
        PlanningTimeZone.candidates(
            CalendarDay(2026, 11, 1), 1, 30, 'America/New_York'),
        [DateTime.utc(2026, 11, 1, 5, 30), DateTime.utc(2026, 11, 1, 6, 30)]);
  });
  test('half-hour DST transitions are resolved without one-hour assumptions',
      () {
    expect(
        PlanningTimeZone.candidates(
            CalendarDay(2026, 10, 4), 2, 15, 'Australia/Lord_Howe'),
        isEmpty);
    expect(
        PlanningTimeZone.candidates(
            CalendarDay(2026, 4, 5), 1, 45, 'Australia/Lord_Howe'),
        hasLength(2));
  });
  test('invalid clock inputs fail instead of normalizing into another day', () {
    expect(
        () => PlanningTimeZone.candidates(
            CalendarDay(2026, 10, 30), 24, 0, 'Asia/Dhaka'),
        throwsFormatException);
  });
}
