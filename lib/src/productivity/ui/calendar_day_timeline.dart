import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/calendar_day.dart';
import '../domain/calendar_event.dart';
import '../domain/experience_options.dart';
import '../domain/planning_time_zone.dart';
import 'experience_strings.dart';

/// An elapsed-time grid. Building ticks from instants (rather than assuming a
/// 24-hour civil day) keeps spring and autumn clock changes in the right place.
class CalendarDayTimeline extends StatefulWidget {
  const CalendarDayTimeline({
    super.key,
    required this.day,
    required this.events,
    required this.options,
    required this.onOpen,
    this.now,
  });

  final CalendarDay day;
  final List<CalendarEvent> events;
  final ExperienceOptions options;
  final ValueChanged<CalendarEvent> onOpen;
  final DateTime? now;

  static const double pixelsPerHour = 72;
  static const double gutter = 72;
  static const double minimumLaneWidth = 112;

  @override
  State<CalendarDayTimeline> createState() => _CalendarDayTimelineState();
}

class _CalendarDayTimelineState extends State<CalendarDayTimeline> {
  late final ScrollController _vertical =
      ScrollController(initialScrollOffset: _initialOffset());

  double _initialOffset() {
    final place = PlanningTimeZone.location(widget.options.timeZone);
    final start =
        tz.TZDateTime(place, widget.day.year, widget.day.month, widget.day.day)
            .toUtc();
    final next = widget.day.addDays(1);
    final end = tz.TZDateTime(place, next.year, next.month, next.day).toUtc();
    final now = (widget.now ?? DateTime.now()).toUtc();
    final today = now.isBefore(end) && !now.isBefore(start);
    final upcoming = widget.events
        .where((event) => event.start.isBefore(end) && event.end.isAfter(start))
        .where((event) => !today || event.end.isAfter(now))
        .map((event) => event.start.isBefore(start) ? start : event.start)
        .toList()
      ..sort();
    final target = upcoming.isNotEmpty
        ? upcoming.first
        : today
            ? now
            : PlanningTimeZone.candidates(
                        widget.day, 8, 0, widget.options.timeZone)
                    .firstOrNull ??
                start.add(const Duration(hours: 8));
    return math.max(0, target.difference(start).inMinutes - 60) *
        CalendarDayTimeline.pixelsPerHour /
        60;
  }

  @override
  void dispose() {
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final place = PlanningTimeZone.location(widget.options.timeZone);
    final day = widget.day;
    final options = widget.options;
    final events = widget.events;
    final now = (widget.now ?? DateTime.now()).toUtc();
    final start = tz.TZDateTime(place, day.year, day.month, day.day).toUtc();
    final next = day.addDays(1);
    final end = tz.TZDateTime(place, next.year, next.month, next.day).toUtc();
    final minutes = end.difference(start).inMinutes;
    if (minutes <= 0) {
      return Center(
          child: Text(ExperienceStrings(options.language).text(
              'This date has no local hours in the selected time zone.',
              'নির্বাচিত সময় অঞ্চলে এই তারিখে কোনো স্থানীয় ঘণ্টা নেই।')));
    }

    final entries = <_TimelineEntry>[
      for (final event in events)
        if (event.start.isBefore(end) && event.end.isAfter(start))
          _TimelineEntry(
              event,
              event.start.isBefore(start) ? start : event.start,
              event.end.isAfter(end) ? end : event.end),
    ]..sort((a, b) {
        final order = a.start.compareTo(b.start);
        return order != 0 ? order : a.event.id.compareTo(b.event.id);
      });
    final laneEnds = <DateTime>[];
    for (final entry in entries) {
      var lane = laneEnds.indexWhere((value) => !value.isAfter(entry.start));
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(entry.end);
      } else {
        laneEnds[lane] = entry.end;
      }
      entry.lane = lane;
    }

    final strings = ExperienceStrings(options.language);
    final localizations = MaterialLocalizations.of(context);
    String time(DateTime instant) {
      final local = tz.TZDateTime.from(instant, place);
      final formatted = localizations.formatTimeOfDay(
          TimeOfDay.fromDateTime(local),
          alwaysUse24HourFormat: options.use24HourClock);
      return strings.number(formatted);
    }

    final height = minutes * CalendarDayTimeline.pixelsPerHour / 60 + 24;
    return LayoutBuilder(builder: (context, constraints) {
      final visibleWidth = constraints.maxWidth;
      final width = math.max(
          visibleWidth,
          CalendarDayTimeline.gutter +
              12 +
              math.max(1, laneEnds.length) *
                  CalendarDayTimeline.minimumLaneWidth);
      final laneWidth = (width - CalendarDayTimeline.gutter - 12) /
          math.max(1, laneEnds.length);
      return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                  controller: _vertical,
                  child: SizedBox(
                      key: const ValueKey('calendar-timeline-grid'),
                      height: height,
                      child: Stack(children: [
                        for (var tick = 0; tick <= minutes; tick += 60)
                          Positioned(
                              top:
                                  tick * CalendarDayTimeline.pixelsPerHour / 60,
                              left: 0,
                              right: 0,
                              child: Row(children: [
                                SizedBox(
                                    width: CalendarDayTimeline.gutter - 6,
                                    child: Text(
                                        '${time(start.add(Duration(minutes: tick)))} ${tz.TZDateTime.from(start.add(Duration(minutes: tick)), place).timeZoneName}',
                                        textAlign: TextAlign.right,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall)),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Divider(
                                        height: 1,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant)),
                              ])),
                        if (now.isAfter(start) && now.isBefore(end))
                          Positioned(
                              top: now.difference(start).inMinutes *
                                  CalendarDayTimeline.pixelsPerHour /
                                  60,
                              left: CalendarDayTimeline.gutter,
                              right: 0,
                              child: Semantics(
                                  label: strings.text(
                                      'Current time', 'বর্তমান সময়'),
                                  child: Divider(
                                      height: 2,
                                      thickness: 2,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                        for (final entry in entries)
                          Positioned(
                              top: entry.start.difference(start).inMinutes * CalendarDayTimeline.pixelsPerHour / 60 +
                                  6,
                              left: CalendarDayTimeline.gutter +
                                  entry.lane * laneWidth,
                              width: laneWidth - 4,
                              height: math.max(
                                  20,
                                  entry.end.difference(entry.start).inMinutes * CalendarDayTimeline.pixelsPerHour / 60 -
                                      4),
                              child: Material(
                                  key: ValueKey(
                                      'calendar-event-${entry.event.id}'),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                      onTap: () => widget.onOpen(entry.event),
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          child: Text('${entry.event.title}  ${time(entry.event.start)}–${time(entry.event.end)}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context).textTheme.labelMedium))))),
                      ])))));
    });
  }
}

class _TimelineEntry {
  _TimelineEntry(this.event, this.start, this.end);
  final CalendarEvent event;
  final DateTime start, end;
  int lane = 0;
}
