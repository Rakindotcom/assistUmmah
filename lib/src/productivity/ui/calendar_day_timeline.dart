import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/calendar_day.dart';
import '../domain/calendar_event.dart';
import '../domain/experience_options.dart';
import '../domain/planning_time_zone.dart';
import '../domain/task.dart';
import 'experience_strings.dart';

/// An elapsed-time grid. Building ticks from instants (rather than assuming a
/// 24-hour civil day) keeps spring and autumn clock changes in the right place.
class CalendarDayTimeline extends StatefulWidget {
  const CalendarDayTimeline({
    super.key,
    required this.day,
    required this.events,
    this.tasks = const [],
    required this.options,
    required this.onOpen,
    this.onOpenTask,
    this.now,
    this.clock,
  });

  final CalendarDay day;
  final List<CalendarEvent> events;
  final List<ProductivityTask> tasks;
  final ExperienceOptions options;
  final ValueChanged<CalendarEvent> onOpen;
  final ValueChanged<ProductivityTask>? onOpenTask;
  final DateTime? now;

  /// A live clock can be injected without disabling minute and resume updates.
  /// [now] instead renders a fixed snapshot with no timer.
  final DateTime Function()? clock;

  static const double pixelsPerHour = 72;
  static const double gutter = 72;
  static const double minimumLaneWidth = 112;

  @override
  State<CalendarDayTimeline> createState() => _CalendarDayTimelineState();
}

class _CalendarDayTimelineState extends State<CalendarDayTimeline>
    with WidgetsBindingObserver {
  late final ScrollController _vertical =
      ScrollController(initialScrollOffset: _initialOffset());
  Timer? _minuteTimer;
  bool _active = true;

  DateTime _now() =>
      (widget.now ?? widget.clock?.call() ?? DateTime.now()).toUtc();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _active = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _scheduleMinute();
  }

  @override
  void didUpdateWidget(CalendarDayTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.now != widget.now || oldWidget.clock != widget.clock) {
      _scheduleMinute();
    }
  }

  void _scheduleMinute() {
    _minuteTimer?.cancel();
    if (!_active || widget.now != null) return;
    final now = _now();
    final elapsed = now.second * Duration.microsecondsPerSecond +
        now.millisecond * Duration.microsecondsPerMillisecond +
        now.microsecond;
    _minuteTimer = Timer(
        Duration(microseconds: Duration.microsecondsPerMinute - elapsed), () {
      if (!mounted) return;
      setState(() {});
      _scheduleMinute();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active && widget.now == null && mounted) setState(() {});
    _scheduleMinute();
  }

  double _initialOffset() {
    final place = PlanningTimeZone.location(widget.options.timeZone);
    final start =
        tz.TZDateTime(place, widget.day.year, widget.day.month, widget.day.day)
            .toUtc();
    final next = widget.day.addDays(1);
    final end = tz.TZDateTime(place, next.year, next.month, next.day).toUtc();
    final now = _now();
    final today = now.isBefore(end) && !now.isBefore(start);
    final enabled = widget.options.modules.map((module) => module.name).toSet();
    final starts = <({DateTime start, DateTime end})>[
      for (final event in widget.events) (start: event.start, end: event.end),
      for (final task in widget.tasks)
        if (enabled.contains(task.workspaceId) &&
            !task.archived &&
            task.scheduledAt != null &&
            task.estimatedMinutes > 0)
          (
            start: task.scheduledAt!,
            end: task.scheduledAt!.add(Duration(minutes: task.estimatedMinutes))
          ),
    ];
    final upcoming = starts
        .where((item) => item.start.isBefore(end) && item.end.isAfter(start))
        .where((item) => !today || item.end.isAfter(now))
        .map((item) => item.start.isBefore(start) ? start : item.start)
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
    WidgetsBinding.instance.removeObserver(this);
    _minuteTimer?.cancel();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final place = PlanningTimeZone.location(widget.options.timeZone);
    final day = widget.day;
    final options = widget.options;
    final events = widget.events;
    final tasks = widget.tasks;
    final now = _now();
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

    final enabled = options.modules.map((module) => module.name).toSet();
    final entries = <_TimelineEntry>[
      for (final event in events)
        if (event.start.isBefore(end) && event.end.isAfter(start))
          _TimelineEntry.event(
              event,
              event.start.isBefore(start) ? start : event.start,
              event.end.isAfter(end) ? end : event.end),
      for (final task in tasks)
        if (enabled.contains(task.workspaceId) &&
            !task.archived &&
            task.scheduledAt != null &&
            task.estimatedMinutes > 0)
          if (task.scheduledAt!.isBefore(end) &&
              task.scheduledAt!
                  .add(Duration(minutes: task.estimatedMinutes))
                  .isAfter(start))
            _TimelineEntry.task(
                task,
                task.scheduledAt!.isBefore(start) ? start : task.scheduledAt!,
                task.scheduledAt!
                        .add(Duration(minutes: task.estimatedMinutes))
                        .isAfter(end)
                    ? end
                    : task.scheduledAt!
                        .add(Duration(minutes: task.estimatedMinutes))),
    ]..sort((a, b) {
        final order = a.start.compareTo(b.start);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    final strings = ExperienceStrings(options.language);
    final localizations = MaterialLocalizations.of(context);
    String time(DateTime instant) {
      final local = tz.TZDateTime.from(instant, place);
      final formatted = localizations.formatTimeOfDay(
          TimeOfDay.fromDateTime(local),
          alwaysUse24HourFormat: options.use24HourClock);
      return strings.number(formatted);
    }

    String endpoint(DateTime instant) {
      final localDay = CalendarDay.fromDate(tz.TZDateTime.from(instant, place));
      return localDay == day
          ? time(instant)
          : '${strings.number(localDay.toString())} ${time(instant)}';
    }

    String range(_TimelineEntry entry) =>
        '${endpoint(entry.originalStart)}–${endpoint(entry.originalEnd)}';

    String description(_TimelineEntry entry) {
      final module = WorkspaceModule.values
          .where((value) => value.name == entry.workspaceId)
          .firstOrNull;
      final workspace =
          module == null ? entry.workspaceId : strings.module(module);
      final source = entry.task == null
          ? strings.text('Event', 'ইভেন্ট')
          : strings.text('Scheduled task', 'সময় নির্ধারিত কাজ');
      return '$source · $workspace · ${entry.title} · ${range(entry)}';
    }

    final labelStyle = Theme.of(context).textTheme.labelMedium;
    final textScaler = MediaQuery.textScalerOf(context);
    TextPainter measure(String value) => TextPainter(
        text: TextSpan(text: value, style: labelStyle),
        textDirection: Directionality.of(context),
        textScaler: textScaler)
      ..layout();
    final line = measure('Ag');
    var minimumHeight = math.max(48.0, line.height * 2 + 6);
    line.dispose();
    var minimumLaneWidth = CalendarDayTimeline.minimumLaneWidth;
    for (final entry in entries) {
      final label = measure(range(entry));
      final title = measure(entry.title);
      minimumLaneWidth = math.max(minimumLaneWidth, label.width + 20);
      minimumHeight = math.max(minimumHeight, label.height + title.height + 6);
      label.dispose();
      title.dispose();
    }
    double pixels(Duration value) =>
        value.inMicroseconds *
        CalendarDayTimeline.pixelsPerHour /
        Duration.microsecondsPerHour;
    double blockHeight(_TimelineEntry entry) =>
        math.max(minimumHeight, pixels(entry.end.difference(entry.start)) - 4);

    // Minimum tap targets and readable labels can extend beyond a short event.
    // Allocate their rendered extents so adjacent short events cannot cover
    // each other's labels or intercept each other's taps.
    final laneEnds = <double>[];
    for (final entry in entries) {
      final top = pixels(entry.start.difference(start));
      final bottom = top + blockHeight(entry);
      var lane = laneEnds.indexWhere((value) => value <= top);
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(bottom);
      } else {
        laneEnds[lane] = bottom;
      }
      entry.lane = lane;
    }

    final height = entries.fold<double>(
        minutes * CalendarDayTimeline.pixelsPerHour / 60 + 24,
        (current, entry) => math.max(
            current,
            pixels(entry.start.difference(start)) +
                6 +
                blockHeight(entry) +
                8));
    return LayoutBuilder(builder: (context, constraints) {
      final visibleWidth = constraints.maxWidth;
      final width = math.max(
          visibleWidth,
          CalendarDayTimeline.gutter +
              12 +
              math.max(1, laneEnds.length) * minimumLaneWidth);
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
                              key: const ValueKey('calendar-timeline-now'),
                              top: pixels(now.difference(start)),
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
                              top: pixels(entry.start.difference(start)) + 6,
                              left: CalendarDayTimeline.gutter +
                                  entry.lane * laneWidth,
                              width: laneWidth - 4,
                              height: blockHeight(entry),
                              child: Material(
                                  key: ValueKey(
                                      'calendar-${entry.task == null ? 'event' : 'task'}-${entry.id}'),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                  clipBehavior: Clip.antiAlias,
                                  child: Tooltip(
                                      message: description(entry),
                                      child: InkWell(
                                          onTap: entry.task == null
                                              ? () =>
                                                  widget.onOpen(entry.event!)
                                              : widget.onOpenTask == null
                                                  ? null
                                                  : () => widget
                                                      .onOpenTask!(entry.task!),
                                          child: Stack(children: [
                                            Positioned(
                                                left: 0,
                                                top: 0,
                                                width: 4,
                                                height: math.min(
                                                    blockHeight(entry),
                                                    math.max(
                                                        1.0,
                                                        pixels(entry.end
                                                            .difference(
                                                                entry.start)))),
                                                child: ColoredBox(
                                                    key: ValueKey(
                                                        'calendar-duration-${entry.task == null ? 'event' : 'task'}-${entry.id}'),
                                                    color: entry.task == null
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .secondary)),
                                            Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(entry.title,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: labelStyle),
                                                      Text(range(entry),
                                                          maxLines: 1,
                                                          style: labelStyle),
                                                    ])),
                                          ]))))),
                      ])))));
    });
  }
}

class _TimelineEntry {
  _TimelineEntry.event(CalendarEvent value, this.start, this.end)
      : event = value,
        task = null,
        id = value.id,
        workspaceId = value.workspaceId,
        title = value.title,
        originalStart = value.start,
        originalEnd = value.end;
  _TimelineEntry.task(ProductivityTask value, this.start, this.end)
      : event = null,
        task = value,
        id = value.id,
        workspaceId = value.workspaceId,
        title = value.title,
        originalStart = value.scheduledAt!,
        originalEnd =
            value.scheduledAt!.add(Duration(minutes: value.estimatedMinutes));
  final CalendarEvent? event;
  final ProductivityTask? task;
  final String id, title, workspaceId;
  final DateTime originalStart, originalEnd;
  final DateTime start, end;
  int lane = 0;
}
