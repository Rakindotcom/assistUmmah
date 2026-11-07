import 'package:flutter/material.dart';

import '../core/records.dart';
import '../data/calendar_event_repository.dart';
import '../data/daily_planning_repository.dart';
import '../data/task_repository.dart';
import '../domain/calendar_day.dart';
import '../domain/calendar_event.dart';
import '../domain/experience_options.dart';
import '../domain/planning_time_zone.dart';
import '../domain/task.dart';
import 'calendar_day_timeline.dart';
import 'daily_planning_page.dart';
import 'experience_strings.dart';

class ProductivityCalendarPage extends StatefulWidget {
  const ProductivityCalendarPage(
      {super.key,
      required this.repository,
      required this.options,
      this.taskRepository,
      this.onOpenTask,
      this.clock});
  final CalendarEventRepository repository;
  final TaskRepository? taskRepository;
  final ValueChanged<ProductivityTask>? onOpenTask;
  final ExperienceOptions options;
  final DateTime Function()? clock;
  @override
  State<ProductivityCalendarPage> createState() =>
      _ProductivityCalendarPageState();
}

class _ProductivityCalendarPageState extends State<ProductivityCalendarPage> {
  late CalendarDay _day = CalendarDay.fromDate(PlanningTimeZone.inZone(
      (widget.clock ?? DateTime.now)(), widget.options.timeZone));
  late Stream<List<CalendarEvent>> _events = widget.repository.watchEvents();
  late Stream<List<ProductivityTask>>? _tasks =
      widget.taskRepository?.watchAllTasks();
  bool _timeline = false;
  bool _planning = false;
  ExperienceStrings get strings => ExperienceStrings(widget.options.language);

  @override
  void didUpdateWidget(ProductivityCalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _events = widget.repository.watchEvents();
    }
    if (oldWidget.taskRepository != widget.taskRepository) {
      _tasks = widget.taskRepository?.watchAllTasks();
    }
  }

  Future<void> _edit([CalendarEvent? event]) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => CalendarEventEditorPage(
            repository: widget.repository,
            options: widget.options,
            day: _day,
            event: event)));
  }

  Future<void> _plan() async {
    final tasks = widget.taskRepository;
    if (tasks == null || _planning) return;
    setState(() => _planning = true);
    try {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => DailyPlanningPage(
              repository:
                  DailyPlanningRepository(tasks.database, clock: widget.clock),
              day: _day,
              options: widget.options)));
      if (mounted && saved == true) setState(() => _timeline = true);
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CalendarEvent>>(
      stream: _events,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Text(strings.text('Could not open calendar events.',
                  'ক্যালেন্ডারের তথ্য খোলা যায়নি।')));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final enabled =
            widget.options.modules.map((module) => module.name).toSet();
        final events = snapshot.data!
            .where((event) => enabled.contains(event.workspaceId))
            .where((event) {
          final location = PlanningTimeZone.location(widget.options.timeZone);
          final start = PlanningTimeZone.inZone(event.start, location.name);
          final end = PlanningTimeZone.inZone(
              event.end.subtract(const Duration(microseconds: 1)),
              location.name);
          final first = CalendarDay.fromDate(start);
          final last = CalendarDay.fromDate(end);
          return !_day.isBefore(first) && !_day.isAfter(last);
        }).toList();
        return Scaffold(
            body: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(children: [
                    IconButton(
                        tooltip: strings.text('Previous day', 'আগের দিন'),
                        onPressed: () =>
                            setState(() => _day = _day.addDays(-1)),
                        icon: const Icon(Icons.chevron_left)),
                    Expanded(
                        child: TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _day.utc,
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(9999, 12, 31));
                              if (picked != null && mounted) {
                                setState(
                                    () => _day = CalendarDay.fromDate(picked));
                              }
                            },
                            child: Text(strings.number(_day.toString())))),
                    IconButton(
                        tooltip: strings.text('Next day', 'পরের দিন'),
                        onPressed: () => setState(() => _day = _day.addDays(1)),
                        icon: const Icon(Icons.chevron_right)),
                    IconButton(
                        tooltip: _timeline
                            ? strings.text('Show agenda', 'ইভেন্ট তালিকা দেখুন')
                            : strings.text('Show hourly timeline',
                                'ঘণ্টাভিত্তিক সময়রেখা দেখুন'),
                        onPressed: () => setState(() => _timeline = !_timeline),
                        icon: Icon(_timeline
                            ? Icons.view_agenda_outlined
                            : Icons.view_timeline_outlined)),
                  ])),
              if (widget.taskRepository != null)
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                            onPressed: _planning ? null : _plan,
                            icon: const Icon(Icons.event_available_outlined),
                            label: Text(strings.text(
                                'Plan this day', 'দিনের পরিকল্পনা'))))),
              Expanded(
                  child: _timeline
                      ? _tasks == null
                          ? _timelineView(events, const [])
                          : StreamBuilder<List<ProductivityTask>>(
                              stream: _tasks,
                              builder: (context, tasks) {
                                if (tasks.hasError) {
                                  return Center(
                                      child: Text(strings.text(
                                          'Could not load scheduled tasks.',
                                          'সময় নির্ধারিত কাজগুলো খোলা যায়নি।')));
                                }
                                if (!tasks.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                return _timelineView(events, tasks.data!);
                              })
                      : events.isEmpty
                          ? Center(
                              child: Text(strings.text('No events on this day.',
                                  'এই দিনে কোনো ইভেন্ট নেই।')))
                          : ListView.builder(
                              itemCount: events.length,
                              itemBuilder: (context, index) {
                                final event = events[index];
                                final overlap = events.any((other) =>
                                    other.id != event.id &&
                                    event.overlaps(other));
                                final start = PlanningTimeZone.inZone(
                                    event.start, widget.options.timeZone);
                                final end = PlanningTimeZone.inZone(
                                    event.end, widget.options.timeZone);
                                String time(DateTime value) =>
                                    MaterialLocalizations.of(context)
                                        .formatTimeOfDay(
                                            TimeOfDay.fromDateTime(value),
                                            alwaysUse24HourFormat:
                                                widget.options.use24HourClock);
                                final module = WorkspaceModule.values
                                    .where((value) =>
                                        value.name == event.workspaceId)
                                    .firstOrNull;
                                final workspace = module == null
                                    ? event.workspaceId
                                    : strings.module(module);
                                return Card(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 4),
                                    child: ListTile(
                                        onTap: () => _edit(event),
                                        title: Text(event.title),
                                        subtitle: Text(
                                            '${strings.number(time(start))}–${strings.number(time(end))} · $workspace${overlap ? '\n${strings.text('Overlaps another event', 'অন্য ইভেন্টের সঙ্গে সময় মিলে গেছে')}' : ''}'),
                                        isThreeLine: overlap,
                                        trailing:
                                            const Icon(Icons.chevron_right)));
                              })),
            ]),
            floatingActionButton: FloatingActionButton.extended(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: Text(strings.text('Add event', 'ইভেন্ট যোগ'))));
      });

  Widget _timelineView(
          List<CalendarEvent> events, List<ProductivityTask> tasks) =>
      CalendarDayTimeline(
          key: ValueKey('$_day-${widget.options.timeZone}'),
          day: _day,
          events: events,
          tasks: tasks,
          options: widget.options,
          now: widget.clock?.call(),
          onOpen: _edit,
          onOpenTask: widget.onOpenTask);
}

class CalendarEventEditorPage extends StatefulWidget {
  const CalendarEventEditorPage(
      {super.key,
      required this.repository,
      required this.options,
      required this.day,
      this.event});
  final CalendarEventRepository repository;
  final ExperienceOptions options;
  final CalendarDay day;
  final CalendarEvent? event;
  @override
  State<CalendarEventEditorPage> createState() => _EventEditorState();
}

class _EventEditorState extends State<CalendarEventEditorPage> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _notes = TextEditingController(text: widget.event?.notes ?? '');
  late DateTime? _start = widget.event?.start;
  late DateTime? _end = widget.event?.end;
  bool _saving = false;
  String? _error;
  ExperienceStrings get strings => ExperienceStrings(widget.options.language);

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _choose(bool start) async {
    final current = start ? _start : _end;
    final local = current == null
        ? null
        : PlanningTimeZone.inZone(current, widget.options.timeZone);
    final day = await showDatePicker(
        context: context,
        initialDate: local == null
            ? widget.day.utc
            : DateTime(local.year, local.month, local.day),
        firstDate: DateTime(1900),
        lastDate: DateTime(9999, 12, 31));
    if (day == null || !mounted) return;
    final time = await showTimePicker(
        context: context,
        initialTime: local == null
            ? TimeOfDay(hour: start ? 9 : 10, minute: 0)
            : TimeOfDay.fromDateTime(local),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(alwaysUse24HourFormat: widget.options.use24HourClock),
            child: child!));
    if (time == null || !mounted) return;
    final candidates = PlanningTimeZone.candidates(CalendarDay.fromDate(day),
        time.hour, time.minute, widget.options.timeZone);
    if (candidates.isEmpty) {
      setState(() => _error = strings.text(
          'This time does not exist because the clocks change.',
          'ঘড়ির সময় বদলের কারণে এই সময়টি নেই।'));
      return;
    }
    final chosen = candidates.singleOrNull ??
        await showDialog<DateTime>(
            context: context,
            builder: (context) => SimpleDialog(
                    title: Text(strings.text('Which occurrence of this time?',
                        'এই সময়টি দুইবার আসে। কোনটি চান?')),
                    children: [
                      for (final candidate in candidates)
                        SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, candidate),
                            child: Text(
                                '${candidate == candidates.first ? strings.text('First', 'প্রথমবার') : strings.text('Second', 'দ্বিতীয়বার')} · ${PlanningTimeZone.inZone(candidate, widget.options.timeZone).timeZoneName}'))
                    ]));
    if (chosen != null && mounted) {
      setState(() {
        if (start) {
          _start = chosen;
        } else {
          _end = chosen;
        }
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_start == null || _end == null) {
      setState(() => _error = strings.text(
          'Choose a start and end time.', 'শুরু ও শেষের সময় বেছে নিন।'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final event = CalendarEvent(
          id: widget.event?.id ?? newRecordId(),
          workspaceId:
              widget.event?.workspaceId ?? widget.options.activeWorkspace,
          title: _title.text,
          start: _start!,
          end: _end!,
          timeZone: widget.event?.timeZone ?? widget.options.timeZone,
          notes: _notes.text);
      if (widget.event == null) {
        await widget.repository.create(event);
      } else {
        final original = widget.event!;
        final patch = <String, Object?>{
          if (event.title != original.title) 'title': event.title,
          if (event.start != original.start)
            'start': event.start.toIso8601String(),
          if (event.end != original.end) 'end': event.end.toIso8601String(),
          if (event.notes != original.notes) 'notes': event.notes,
        };
        if (patch.isNotEmpty) await widget.repository.edit(event.id, patch);
      }
      if (mounted) Navigator.pop(context, true);
    } on FormatException {
      if (mounted) {
        setState(() => _error = strings.text(
            'The end must follow the start. Check event details.',
            'শেষের সময় শুরুর পরে হতে হবে। ইভেন্টের তথ্য দেখুন।'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = strings.text(
            'Could not save the event.', 'ইভেন্ট সংরক্ষণ করা যায়নি।'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String label(DateTime? instant) {
      if (instant == null) return strings.text('Choose', 'বেছে নিন');
      final local = PlanningTimeZone.inZone(instant, widget.options.timeZone);
      final time = MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay.fromDateTime(local),
          alwaysUse24HourFormat: widget.options.use24HourClock);
      return '${strings.number(CalendarDay.fromDate(local).toString())} · ${strings.number(time)}';
    }

    return Scaffold(
        appBar: AppBar(
            title: Text(strings.text(
                widget.event == null ? 'New event' : 'Edit event',
                widget.event == null ? 'নতুন ইভেন্ট' : 'ইভেন্ট সম্পাদনা'))),
        body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              TextFormField(
                  controller: _title,
                  maxLength: 200,
                  decoration: InputDecoration(
                      labelText: strings.text('Title', 'শিরোনাম')),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? strings.text('Enter a title.', 'শিরোনাম লিখুন।')
                      : null),
              ListTile(
                  title: Text(strings.text('Starts', 'শুরু')),
                  subtitle: Text(label(_start)),
                  onTap: () => _choose(true)),
              ListTile(
                  title: Text(strings.text('Ends', 'শেষ')),
                  subtitle: Text(label(_end)),
                  onTap: () => _choose(false)),
              TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  maxLength: 10000,
                  decoration:
                      InputDecoration(labelText: strings.text('Notes', 'নোট'))),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (widget.event != null)
                TextButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                        title: Text(strings.text(
                                            'Delete event?', 'ইভেন্ট মুছবেন?')),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: Text(strings.text(
                                                  'Cancel', 'বাতিল'))),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: Text(strings.text(
                                                  'Delete', 'মুছুন'))),
                                        ]));
                            if (confirmed != true) return;
                            setState(() => _saving = true);
                            try {
                              await widget.repository.delete(widget.event!.id);
                              if (context.mounted) Navigator.pop(context, true);
                            } catch (_) {
                              if (mounted) {
                                setState(() {
                                  _saving = false;
                                  _error = strings.text(
                                      'Could not delete the event.',
                                      'ইভেন্ট মোছা যায়নি।');
                                });
                              }
                            }
                          },
                    child: Text(strings.text('Delete event', 'ইভেন্ট মুছুন'))),
            ])),
        bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(strings.text('Save event', 'ইভেন্ট সংরক্ষণ')))));
  }
}
