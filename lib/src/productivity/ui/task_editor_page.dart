import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/records.dart';
import '../data/task_repository.dart';
import '../domain/calendar_day.dart';
import '../domain/experience_options.dart';
import '../domain/planning_time_zone.dart';
import '../domain/project.dart';
import '../domain/recurrence.dart';
import '../domain/task.dart';
import 'experience_strings.dart';

class ProductivityTaskEditorPage extends StatefulWidget {
  const ProductivityTaskEditorPage(
      {super.key,
      required this.repository,
      required this.workspaceId,
      required this.options,
      this.task,
      this.projects = const [],
      this.tasks = const [],
      this.parentId});
  final TaskRepository repository;
  final String workspaceId;
  final ExperienceOptions options;
  final ProductivityTask? task;
  final String? parentId;
  final List<ProductivityProject> projects;
  final List<ProductivityTask> tasks;
  @override
  State<ProductivityTaskEditorPage> createState() =>
      _ProductivityTaskEditorPageState();
}

class _ProductivityTaskEditorPageState
    extends State<ProductivityTaskEditorPage> {
  final _form = GlobalKey<FormState>();
  final _patch = <String, Object?>{};
  late final ProductivityTask _original;
  bool _saving = false;
  String? _error;
  ExperienceStrings get strings => ExperienceStrings(widget.options.language);
  Widget _counter(BuildContext context,
          {required int currentLength,
          required int? maxLength,
          required bool isFocused}) =>
      Text(
          '${strings.number(currentLength)} / ${strings.number(maxLength ?? 0)}',
          style: Theme.of(context).textTheme.bodySmall);
  Object? _value(String field) =>
      _patch.containsKey(field) ? _patch[field] : _original.toFields()[field];
  @override
  void initState() {
    super.initState();
    _original = widget.task ??
        ProductivityTask(
            id: newRecordId(),
            workspaceId: widget.workspaceId,
            title: 'Untitled',
            parentId: widget.parentId);
    if (widget.task == null) _patch['title'] = '';
  }

  void _change(String key, Object? value) => setState(() {
        _patch[key] = value;
      });

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.task == null) {
        final task = ProductivityTask.fromFields(
            id: _original.id,
            workspaceId: widget.workspaceId,
            fields: {..._original.toFields(), ..._patch});
        await widget.repository.createTask(task);
      } else {
        await widget.repository.editTask(_original.id, _patch);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on TaskEditFailure catch (error) {
      if (mounted) setState(() => _error = strings.taskError(error.code));
    } catch (_) {
      if (mounted) setState(() => _error = strings.taskError('save-failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<CalendarDay?> _chooseDay(CalendarDay? initial) async {
    final today = CalendarDay.fromDate(
        PlanningTimeZone.inZone(DateTime.now(), widget.options.timeZone));
    final day = await showDatePicker(
        context: context,
        initialDate: (initial ?? today).utc,
        firstDate: DateTime(1900),
        lastDate: DateTime(9999, 12, 31));
    return day == null ? null : CalendarDay.fromDate(day);
  }

  Future<void> _date(String key) async {
    final value = _value(key) as String?;
    final day =
        await _chooseDay(value == null ? null : CalendarDay.parse(value));
    if (day != null && mounted) {
      if (key == 'scheduledDay') _patch['scheduledAt'] = null;
      _change(key, day.toString());
    }
  }

  Future<DateTime?> _chooseInstant(String? value) async {
    final initial = value == null
        ? null
        : PlanningTimeZone.inZone(
            DateTime.parse(value), widget.options.timeZone);
    final day = await _chooseDay(
        initial == null ? null : CalendarDay.fromDate(initial));
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
        context: context,
        initialTime: initial == null
            ? const TimeOfDay(hour: 9, minute: 0)
            : TimeOfDay.fromDateTime(initial),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(alwaysUse24HourFormat: widget.options.use24HourClock),
            child: child!));
    if (time == null || !mounted) return null;
    final candidates = PlanningTimeZone.candidates(
        day, time.hour, time.minute, widget.options.timeZone);
    if (candidates.isEmpty) {
      setState(() => _error = strings.text(
          'That local time does not exist because the clocks change. Choose another time.',
          'ঘড়ির সময় বদলের কারণে এই স্থানীয় সময়টি নেই। অন্য সময় বেছে নিন।'));
      return null;
    }
    if (candidates.length == 1) return candidates.single;
    return showDialog<DateTime>(
        context: context,
        builder: (context) => SimpleDialog(
              title: Text(strings.text('This time occurs twice. Which one?',
                  'এই সময়টি দুইবার আসে। কোনটি চান?')),
              children: [
                for (final instant in candidates)
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, instant),
                      child: Text(
                          '${instant == candidates.first ? strings.text('First occurrence', 'প্রথমবার') : strings.text('Second occurrence', 'দ্বিতীয়বার')} · ${PlanningTimeZone.inZone(instant, widget.options.timeZone).timeZoneName}'))
              ],
            ));
  }

  Future<void> _instant(String key) async {
    final instant = await _chooseInstant(_value(key) as String?);
    if (instant != null && mounted) {
      if (key == 'scheduledAt') _patch['scheduledDay'] = null;
      _change(key, instant.toIso8601String());
    }
  }

  Widget _dateTile(String key, String title, {bool instant = false}) {
    final raw = _value(key) as String?;
    final date = raw == null ? null : DateTime.parse(raw);
    final local = date == null
        ? null
        : instant
            ? PlanningTimeZone.inZone(date, widget.options.timeZone)
            : date;
    final label = local == null
        ? strings.text('Not set', 'দেওয়া হয়নি')
        : '${strings.date(local)}${instant ? ' · ${strings.time(local, use24HourClock: widget.options.use24HourClock)}' : ''}';
    return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(label),
        onTap: _saving ? null : () => instant ? _instant(key) : _date(key),
        trailing: raw == null
            ? const Icon(Icons.add)
            : IconButton(
                tooltip: strings.text('Clear $title', '$title সরান'),
                onPressed: _saving ? null : () => _change(key, null),
                icon: const Icon(Icons.close)));
  }

  Future<void> _recurrence() async {
    final original = _value('recurrence');
    final rule = original == null
        ? null
        : RecurrenceRule.fromJson(Map<String, dynamic>.from(original as Map));
    final result = await showModalBottomSheet<Map<String, Object?>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => _RecurrenceSheet(
            strings: strings,
            rule: rule,
            today: CalendarDay.fromDate(PlanningTimeZone.inZone(
                DateTime.now(), widget.options.timeZone))));
    if (result != null && mounted) _change('recurrence', result['rule']);
  }

  @override
  Widget build(BuildContext context) {
    final projectId = _value('projectId') as String?;
    final parentId = _value('parentId') as String?;
    final dependencies =
        List<String>.from(_value('dependencies') as List? ?? []);
    final reminders = List<String>.from(_value('reminders') as List? ?? []);
    return PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(
              title: Text(widget.task == null
                  ? strings.text('New task', 'নতুন কাজ')
                  : strings.text('Edit task', 'কাজ সম্পাদনা'))),
          bottomNavigationBar: SafeArea(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                                onPressed: _saving ? null : _save,
                                child: Text(_saving
                                    ? strings.text('Saving…', 'সংরক্ষণ হচ্ছে…')
                                    : strings.text(
                                        'Save task', 'কাজ সংরক্ষণ করুন'))))),
                  ]))),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
                key: _form,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  TextFormField(
                      initialValue: _value('title') as String?,
                      enabled: !_saving,
                      autofocus: widget.task == null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                          labelText: strings.text('Task name', 'কাজের নাম')),
                      maxLength: 500,
                      buildCounter: _counter,
                      minLines: 1,
                      maxLines: 3,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? strings.text(
                                  'Give this task a name.', 'কাজের নাম লিখুন।')
                              : null,
                      onChanged: (value) => _patch['title'] = value),
                  const SizedBox(height: 12),
                  TextFormField(
                      initialValue: _value('description') as String?,
                      enabled: !_saving,
                      decoration: InputDecoration(
                          labelText:
                              strings.text('Notes and links', 'বিবরণ ও লিংক')),
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 100000,
                      buildCounter: _counter,
                      onChanged: (value) => _patch['description'] = value),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<TaskPriority>(
                      initialValue:
                          TaskPriority.values[_value('priority') as int],
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: strings.text('Priority', 'অগ্রাধিকার')),
                      items: [
                        for (final priority in TaskPriority.values)
                          DropdownMenuItem(
                              value: priority,
                              child: Text(strings.priority(priority)))
                      ],
                      onChanged: _saving
                          ? null
                          : (priority) {
                              if (priority != null) {
                                _change('priority', priority.index);
                              }
                            }),
                  const SizedBox(height: 16),
                  TextFormField(
                      initialValue: strings.number(_value('estimatedMinutes')!),
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp('[0-9০-৯]'))
                      ],
                      decoration: InputDecoration(
                          labelText: strings.text(
                              'Estimate (minutes)', 'সময়ের অনুমান (মিনিট)')),
                      validator: (value) =>
                          (ExperienceStrings.parseInteger(value ?? '') ?? -1) <
                                      0 ||
                                  (ExperienceStrings.parseInteger(
                                              value ?? '') ??
                                          0) >
                                      525600
                              ? strings.text('Enter 0–525600 minutes.',
                                  '০–৫২৫৬০০ মিনিট লিখুন।')
                              : null,
                      onChanged: (value) => _patch['estimatedMinutes'] =
                          ExperienceStrings.parseInteger(value) ?? 0),
                  const SizedBox(height: 16),
                  TextFormField(
                      initialValue: (_value('tags') as List).join(', '),
                      enabled: !_saving,
                      decoration: InputDecoration(
                          labelText: strings.text('Tags, separated by commas',
                              'ট্যাগ, কমা দিয়ে আলাদা করুন')),
                      onChanged: (value) => _patch['tags'] = value
                          .split(RegExp('[,،]'))
                          .map((tag) => tag.trim())
                          .where((tag) => tag.isNotEmpty)
                          .toSet()
                          .toList()),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                      initialValue: projectId,
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: strings.text('Project', 'প্রকল্প')),
                      items: [
                        DropdownMenuItem(
                            value: null,
                            child: Text(
                                strings.text('No project', 'প্রকল্প নেই'))),
                        if (projectId != null &&
                            !widget.projects
                                .any((project) => project.id == projectId))
                          DropdownMenuItem(
                              value: projectId,
                              child: Text(strings.text('Unavailable project',
                                  'প্রকল্প পাওয়া যায়নি'))),
                        for (final project in widget.projects
                            .where((p) => !p.archived || p.id == projectId))
                          DropdownMenuItem(
                              value: project.id,
                              child: Text(project.name,
                                  overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => _change('projectId', value)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                      initialValue: parentId,
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: strings.text('Parent task', 'মূল কাজ')),
                      items: [
                        DropdownMenuItem(
                            value: null,
                            child: Text(strings.text(
                                'Top-level task', 'স্বতন্ত্র কাজ'))),
                        if (parentId != null &&
                            !widget.tasks.any((task) => task.id == parentId))
                          DropdownMenuItem(
                              value: parentId,
                              child: Text(strings.text(
                                  'Unavailable parent task',
                                  'মূল কাজ পাওয়া যায়নি'))),
                        for (final task
                            in widget.tasks.where((t) => t.id != _original.id))
                          DropdownMenuItem(
                              value: task.id,
                              child: Text(task.title,
                                  overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => _change('parentId', value)),
                  const SizedBox(height: 16),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title:
                          Text(strings.text('Keep in Inbox', 'ইনবক্সে রাখুন')),
                      value: _value('inbox') == true,
                      onChanged:
                          _saving ? null : (value) => _change('inbox', value)),
                  ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(strings.text(
                          'Dates and reminders', 'তারিখ ও রিমাইন্ডার')),
                      children: [
                        Text(strings.text(
                            'Times use ${widget.options.timeZone}. A deadline stays fixed when you reschedule.',
                            'সময় দেখানো হচ্ছে ${widget.options.timeZone} অনুযায়ী। সময়সূচি বদলালেও শেষ সময় বদলাবে না।')),
                        _dateTile('startDate',
                            strings.text('Available from', 'শুরু করা যাবে')),
                        _dateTile('scheduledDay',
                            strings.text('Planned day', 'নির্ধারিত দিন')),
                        _dateTile('scheduledAt',
                            strings.text('Scheduled time', 'নির্ধারিত সময়'),
                            instant: true),
                        _dateTile(
                            'deadline',
                            strings.text(
                                'Hard deadline', 'অবশ্যই শেষ করার সময়'),
                            instant: true),
                        for (final reminder in reminders)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(strings.date(PlanningTimeZone.inZone(
                                  DateTime.parse(reminder),
                                  widget.options.timeZone))),
                              subtitle: Text(strings.time(
                                  PlanningTimeZone.inZone(
                                      DateTime.parse(reminder),
                                      widget.options.timeZone),
                                  use24HourClock:
                                      widget.options.use24HourClock)),
                              trailing: IconButton(
                                  tooltip: strings.text(
                                      'Remove reminder', 'রিমাইন্ডার সরান'),
                                  icon: const Icon(Icons.close),
                                  onPressed: _saving
                                      ? null
                                      : () => _change('reminders',
                                          [...reminders]..remove(reminder)))),
                        TextButton.icon(
                            onPressed: _saving || reminders.length >= 20
                                ? null
                                : () async {
                                    final instant = await _chooseInstant(null);
                                    if (instant != null && mounted) {
                                      _change(
                                          'reminders',
                                          {
                                            ...reminders,
                                            instant.toIso8601String()
                                          }.toList()
                                            ..sort());
                                    }
                                  },
                            icon: const Icon(Icons.add_alarm),
                            label: Text(strings.text(
                                'Add reminder', 'রিমাইন্ডার যোগ করুন'))),
                      ]),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('Repeat', 'পুনরাবৃত্তি')),
                      subtitle: Text(_value('recurrence') == null
                          ? strings.text('Does not repeat', 'পুনরাবৃত্তি নেই')
                          : strings.text('Custom schedule', 'নিজের সময়সূচি')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _saving ? null : _recurrence),
                  ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(strings.text(
                          'Prerequisite tasks', 'আগে শেষ করতে হবে')),
                      children: [
                        if (widget.tasks
                            .where((t) => t.id != _original.id)
                            .isEmpty)
                          Text(strings.text(
                              'Create another task to add a dependency.',
                              'নির্ভরশীলতা যোগ করতে আগে আরেকটি কাজ তৈরি করুন।')),
                        for (final task
                            in widget.tasks.where((t) => t.id != _original.id))
                          CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(task.title),
                              value: dependencies.contains(task.id),
                              onChanged: _saving
                                  ? null
                                  : (selected) => _change(
                                      'dependencies',
                                      selected == true
                                          ? {...dependencies, task.id}.toList()
                                          : ([...dependencies]
                                            ..remove(task.id)))),
                      ]),
                  const SizedBox(height: 24),
                ])),
          ))),
        ));
  }
}

class _RecurrenceSheet extends StatefulWidget {
  const _RecurrenceSheet(
      {required this.strings, required this.rule, required this.today});
  final ExperienceStrings strings;
  final RecurrenceRule? rule;
  final CalendarDay today;
  @override
  State<_RecurrenceSheet> createState() => _RecurrenceSheetState();
}

class _RecurrenceSheetState extends State<_RecurrenceSheet> {
  late RecurrenceFrequency _frequency;
  late CalendarDay _start;
  CalendarDay? _end, _pauseUntil;
  late final Set<int> _weekdays;
  late final Set<CalendarDay> _excluded;
  late bool _paused;
  late MissingMonthDay _missing;
  late final TextEditingController _interval, _monthDays, _count;
  String? _error;
  @override
  void initState() {
    super.initState();
    _frequency = widget.rule?.frequency ?? RecurrenceFrequency.daily;
    _start = widget.rule?.start ?? widget.today;
    _end = widget.rule?.end;
    _pauseUntil = widget.rule?.pauseUntil;
    _weekdays = {...?widget.rule?.weekdays};
    _excluded = {...?widget.rule?.excludedDates};
    _paused = widget.rule?.paused ?? false;
    _missing = widget.rule?.missingMonthDay ?? MissingMonthDay.skip;
    _interval = TextEditingController(
        text: widget.strings.number(widget.rule?.interval ?? 1));
    _monthDays = TextEditingController(
        text: widget.strings.number(widget.rule?.monthDays.join(', ') ?? ''));
    _count = TextEditingController(
        text: widget.strings.number(widget.rule?.count?.toString() ?? ''));
  }

  @override
  void dispose() {
    _interval.dispose();
    _monthDays.dispose();
    _count.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final rule = RecurrenceRule(
          start: _start,
          frequency: _frequency,
          interval: int.parse(ExperienceStrings.asciiDigits(_interval.text)),
          paused: _paused,
          missingMonthDay: _missing,
          count: _count.text.trim().isEmpty
              ? null
              : int.parse(ExperienceStrings.asciiDigits(_count.text.trim())),
          monthDays: _monthDays.text.trim().isEmpty
              ? []
              : _monthDays.text.split(',').map((value) =>
                  int.parse(ExperienceStrings.asciiDigits(value.trim()))),
          weekdays: _weekdays,
          end: _end,
          pauseUntil: _pauseUntil,
          excludedDates: _excluded);
      Navigator.of(context).pop({'rule': rule.toJson()});
    } catch (_) {
      setState(() => _error = widget.strings.text(
          'Check the dates, interval, count and month days.',
          'তারিখ, বিরতি, সংখ্যা ও মাসের দিনগুলো ঠিক করে লিখুন।'));
    }
  }

  Future<CalendarDay?> _pickDay(CalendarDay? initial) async {
    final value = await showDatePicker(
        context: context,
        initialDate: (initial ?? _start).utc,
        firstDate: DateTime(1900),
        lastDate: DateTime(9999, 12, 31));
    return value == null ? null : CalendarDay.fromDate(value);
  }

  Widget _optionalDay(String title, CalendarDay? value,
          void Function(CalendarDay?) change) =>
      ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(value == null
              ? widget.strings.text('Not set', 'দেওয়া হয়নি')
              : widget.strings.date(value.utc)),
          onTap: () async {
            final selected = await _pickDay(value);
            if (selected != null && mounted) setState(() => change(selected));
          },
          trailing: value == null
              ? const Icon(Icons.add)
              : IconButton(
                  tooltip: widget.strings.text('Clear $title', '$title সরান'),
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => change(null))));

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: FractionallySizedBox(
            heightFactor: 0.88,
            child: ListView(padding: const EdgeInsets.all(24), children: [
              Text(s.text('Recurring schedule', 'পুনরাবৃত্ত সময়সূচি'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<RecurrenceFrequency>(
                  initialValue: _frequency,
                  isExpanded: true,
                  items: [
                    for (final frequency in RecurrenceFrequency.values)
                      DropdownMenuItem(
                          value: frequency,
                          child: Text(switch (frequency) {
                            RecurrenceFrequency.daily =>
                              s.text('Daily', 'প্রতিদিন'),
                            RecurrenceFrequency.weekly =>
                              s.text('Weekly', 'প্রতি সপ্তাহে'),
                            RecurrenceFrequency.monthly =>
                              s.text('Monthly', 'প্রতি মাসে'),
                            RecurrenceFrequency.yearly =>
                              s.text('Yearly', 'প্রতি বছরে'),
                          }))
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _frequency = value);
                  }),
              const SizedBox(height: 16),
              TextField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9০-৯]'))
                  ],
                  decoration: InputDecoration(
                      labelText: s.text(
                          'Repeat every (1–365)', 'কত বিরতিতে (১–৩৬৫)'))),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.text('First day', 'প্রথম দিন')),
                  subtitle: Text(s.date(_start.utc)),
                  onTap: () async {
                    final value = await showDatePicker(
                        context: context,
                        initialDate: _start.utc,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(9999, 12, 31));
                    if (value != null && mounted) {
                      setState(() => _start = CalendarDay.fromDate(value));
                    }
                  }),
              if (_frequency == RecurrenceFrequency.monthly ||
                  _frequency == RecurrenceFrequency.yearly) ...[
                TextField(
                    controller: _monthDays,
                    decoration: InputDecoration(
                        labelText: s.text('Month days (e.g. 1, 15, -1)',
                            'মাসের দিন (যেমন ১, ১৫, -১)'))),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text('Use the last day for shorter months',
                        'ছোট মাসে শেষ দিন ব্যবহার করুন')),
                    value: _missing == MissingMonthDay.lastDay,
                    onChanged: (value) => setState(() => _missing = value
                        ? MissingMonthDay.lastDay
                        : MissingMonthDay.skip)),
              ],
              const SizedBox(height: 16),
              Text(s.text('Only on these weekdays (optional)',
                  'শুধু এই বারগুলোতে (ঐচ্ছিক)')),
              Wrap(spacing: 8, children: [
                for (var day = 1; day <= 7; day++)
                  FilterChip(
                      label: Text(s.text(
                          [
                            'Mon',
                            'Tue',
                            'Wed',
                            'Thu',
                            'Fri',
                            'Sat',
                            'Sun'
                          ][day - 1],
                          [
                            'সোম',
                            'মঙ্গল',
                            'বুধ',
                            'বৃহস্পতি',
                            'শুক্র',
                            'শনি',
                            'রবি'
                          ][day - 1])),
                      selected: _weekdays.contains(day),
                      onSelected: (selected) => setState(() {
                            selected
                                ? _weekdays.add(day)
                                : _weekdays.remove(day);
                          }))
              ]),
              _optionalDay(
                  s.text('End date', 'শেষ দিন'), _end, (value) => _end = value),
              TextField(
                  controller: _count,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9০-৯]'))
                  ],
                  decoration: InputDecoration(
                      labelText: s.text(
                          'End after this many occurrences (optional)',
                          'কতবারের পরে শেষ হবে (ঐচ্ছিক)'))),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      s.text('Pause this series', 'পুনরাবৃত্তি বন্ধ রাখুন')),
                  value: _paused,
                  onChanged: (value) => setState(() => _paused = value)),
              _optionalDay(s.text('Pause through', 'এই দিন পর্যন্ত বন্ধ'),
                  _pauseUntil, (value) => _pauseUntil = value),
              const SizedBox(height: 12),
              Text(s.text('Skip specific dates', 'নির্দিষ্ট দিন বাদ দিন')),
              Wrap(spacing: 8, children: [
                for (final day in (_excluded.toList()..sort()))
                  InputChip(
                      label: Text(s.date(day.utc)),
                      onDeleted: () => setState(() => _excluded.remove(day)))
              ]),
              TextButton.icon(
                  onPressed: () async {
                    final day = await _pickDay(null);
                    if (day != null && mounted) {
                      setState(() => _excluded.add(day));
                    }
                  },
                  icon: const Icon(Icons.event_busy),
                  label: Text(
                      s.text('Add skipped date', 'বাদ দেওয়ার দিন যোগ করুন'))),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _save,
                  child:
                      Text(s.text('Apply schedule', 'সময়সূচি ব্যবহার করুন'))),
              TextButton(
                  onPressed: () => Navigator.of(context)
                      .pop(<String, Object?>{'rule': null}),
                  child: Text(s.text('Does not repeat', 'পুনরাবৃত্তি নেই'))),
            ])));
  }
}
