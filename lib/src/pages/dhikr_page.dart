import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_repository.dart';
import '../display_formatters.dart';
import '../app_calendar_delegate.dart';
import '../date_helpers.dart';
import '../dhikr_progress.dart';
import '../widgets/tasbih_counter.dart';

class DhikrPage extends StatefulWidget {
  const DhikrPage(
      {super.key,
      required this.repository,
      required this.today,
      this.active = true});

  final AppRepository repository;
  final DateTime today;
  final bool active;

  @override
  State<DhikrPage> createState() => _DhikrPageState();
}

class _CountChange {
  const _CountChange(this.goalId, this.delta);
  final String goalId;
  final int delta;
}

class _DhikrPageState extends State<DhikrPage> with WidgetsBindingObserver {
  late DateTime _selected = dateOnly(widget.today);
  DhikrGoals _goals = DhikrGoals.standard;
  DhikrDay? _confirmed;
  DhikrHistory? _history;
  final _pending = <_CountChange>[];
  final _failedChanges = <_CountChange>[];
  final _localDocuments = <String, Map<String, dynamic>>{};
  DhikrGoals _localGoals = DhikrGoals.standard;
  Future<void> _writes = Future.value();
  bool _loading = true;
  bool _loadFailed = false;
  int _requestId = 0;
  int _accountEpoch = 0;
  DateTime? _rolloverDay;
  String? _selectedGoalId;
  bool _editingDetails = false;

  bool get _canLeaveDay =>
      _pending.isEmpty && _failedChanges.isEmpty && !_editingDetails;

  DhikrDay get _visible {
    var record = _confirmed!;
    for (final change in _pending) {
      if (record.goals.items.any((goal) => goal.id == change.goalId)) {
        record = record.change(
            change.goalId,
            change.delta.clamp(-record.count(change.goalId),
                DhikrDay.maxCount - record.count(change.goalId)));
      }
    }
    return record;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant DhikrPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository.uid != widget.repository.uid) {
      _accountEpoch++;
      _requestId++;
      _pending.clear();
      _failedChanges.clear();
      _localDocuments.clear();
      _localGoals = DhikrGoals.standard;
      _confirmed = null;
      _history = null;
      _writes = Future.value();
      _selected = dateOnly(widget.today);
      _rolloverDay = null;
      _selectedGoalId = null;
      _editingDetails = false;
      _load();
    } else if (dateKey(oldWidget.today) != dateKey(widget.today)) {
      _rolloverDay = dateOnly(widget.today);
      _advanceAfterRollover();
    } else if (!oldWidget.active && widget.active) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (_editingDetails) return;
    final request = ++_requestId;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    await _writes;
    if (!mounted || request != _requestId) return;
    final repository = widget.repository;
    try {
      final goals =
          repository.canSync ? await repository.loadDhikrGoals() : _localGoals;
      final document = repository.canSync
          ? await repository.loadDhikrDocument(dateKey(_selected))
          : _localDocuments[dateKey(_selected)];
      final history = repository.canSync
          ? await repository.loadDhikrHistory(
              end: widget.today, fallback: goals)
          : DhikrHistory(
              end: widget.today, documents: _localDocuments, fallback: goals);
      if (!mounted || request != _requestId) return;
      setState(() {
        _goals = goals;
        _confirmed = DhikrDay.fromDocument(dateKey(_selected), document,
            fallback: goals);
        _history = history;
        _loading = false;
      });
      _advanceAfterRollover();
    } catch (_) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _enqueue(_CountChange change) {
    if (_loading || _editingDetails || _confirmed == null) return;
    // Check the optimistic result before accepting a tap at the count limit.
    try {
      _visible.change(change.goalId, change.delta);
    } on ArgumentError {
      return;
    }
    final repository = widget.repository;
    final epoch = _accountEpoch;
    final date = _confirmed!.date;
    final fallback = _confirmed!.goals;
    setState(() => _pending.add(change));
    _writes = _writes.then((_) async {
      if (epoch != _accountEpoch) return;
      try {
        final record = repository.canSync
            ? await repository.changeDhikrCount(
                date: date,
                goalId: change.goalId,
                delta: change.delta,
                fallback: fallback)
            : DhikrDay.fromDocument(date, _localDocuments[date],
                    fallback: fallback)
                .change(change.goalId, change.delta);
        if (!mounted || epoch != _accountEpoch) return;
        setState(() {
          _pending.remove(change);
          _storeRecord(record);
        });
        _advanceAfterRollover();
      } catch (_) {
        if (!mounted || epoch != _accountEpoch) return;
        setState(() {
          _pending.remove(change);
          _failedChanges.add(change);
        });
      }
    });
  }

  void _storeRecord(DhikrDay record) {
    if (!widget.repository.canSync) {
      if (record.logged) {
        _localDocuments[record.date] = record.toMap();
      } else {
        _localDocuments.remove(record.date);
      }
    }
    _confirmed = record;
    _history = DhikrHistory(
      end: widget.today,
      documents: {
        for (final day in _history!.days)
          if (day.logged && day.date != record.date) day.date: day.toMap(),
        if (record.logged) record.date: record.toMap(),
      },
      fallback: _goals,
    );
  }

  Future<void> _chooseGoal() async {
    final epoch = _accountEpoch;
    final record = _visible;
    final selected = await showModalBottomSheet<DhikrGoal>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('যিকিরসমূহ',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('যে যিকিরটি গণনা করতে চান, সেটি বেছে নিন'),
              const SizedBox(height: 16),
              for (final goal in record.goals.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    color: goal.id ==
                            (_selectedGoalId ?? record.goals.items.first.id)
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.pop(context, goal),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          DhikrPhraseText(goal: goal, compact: true),
                          const SizedBox(height: 6),
                          Text(
                              '${banglaNumber(record.count(goal.id))} বার পড়া হয়েছে',
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
      ),
    );
    if (!mounted || epoch != _accountEpoch || selected == null) return;
    setState(() => _selectedGoalId = selected.id);
  }

  Future<void> _editTarget(DhikrGoal goal) async {
    final epoch = _accountEpoch;
    final record = _confirmed!;
    final repository = widget.repository;
    setState(() => _editingDetails = true);
    try {
      final updated = await showDialog<DhikrDay>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DhikrTargetDialog(
          goal: goal,
          onSave: (target) => repository.canSync
              ? repository.setDhikrTarget(
                  date: record.date,
                  goalId: goal.id,
                  target: target,
                  fallback: record.goals)
              : Future.value(record.withTarget(goal.id, target)),
        ),
      );
      if (!mounted || epoch != _accountEpoch || updated == null) return;
      setState(() => _storeRecord(updated));
    } finally {
      if (mounted && epoch == _accountEpoch) {
        setState(() => _editingDetails = false);
        _advanceAfterRollover();
      }
    }
  }

  Future<void> _resetCount(DhikrGoal goal) async {
    final epoch = _accountEpoch;
    final record = _confirmed!;
    final repository = widget.repository;
    setState(() => _editingDetails = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('গণনা রিসেট করবেন?'),
          content: Text(
              '${compactDateLabel(DateTime.parse(record.date))} দিনের ${goal.name}-এর গণনা শূন্য হবে।'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('বাতিল')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('রিসেট করুন')),
          ],
        ),
      );
      if (confirmed != true || !mounted || epoch != _accountEpoch) return;
      final updated = repository.canSync
          ? await repository.resetDhikrCount(
              date: record.date, goalId: goal.id, fallback: record.goals)
          : record.reset(goal.id);
      if (!mounted || epoch != _accountEpoch) return;
      setState(() => _storeRecord(updated));
    } catch (_) {
      if (mounted && epoch == _accountEpoch) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('গণনা রিসেট করা যায়নি। আবার চেষ্টা করুন।')));
      }
    } finally {
      if (mounted && epoch == _accountEpoch) {
        setState(() => _editingDetails = false);
        _advanceAfterRollover();
      }
    }
  }

  Future<void> _selectDay(DateTime day) async {
    if (!_canLeaveDay || _loading) return;
    setState(() {
      _selected = dateOnly(day);
      _confirmed = null;
    });
    await _load();
  }

  Future<void> _pickDay() async {
    final selected = await showDatePicker(
        calendarDelegate: AppCalendarDelegate(Localizations.localeOf(context)),
        context: context,
        initialDate: _selected,
        firstDate: DateTime(2000),
        lastDate: dateOnly(widget.today));
    if (selected != null && mounted) await _selectDay(selected);
  }

  void _advanceAfterRollover() {
    final day = _rolloverDay;
    if (day == null || !_canLeaveDay || _loading) return;
    _rolloverDay = null;
    unawaited(_selectDay(day));
  }

  Future<void> _editGoals() async {
    final epoch = _accountEpoch;
    final repository = widget.repository;
    final original = _confirmed!;
    DhikrDay? savedDay;
    setState(() => _editingDetails = true);
    try {
      final result =
          await Navigator.of(context).push<DhikrGoals>(MaterialPageRoute(
        builder: (_) => _DhikrGoalsEditor(
          initial: _goals,
          onSave: (goals) async {
            savedDay = repository.canSync
                ? await repository.saveDhikrGoalsForDay(
                    date: original.date, goals: goals, fallback: original.goals)
                : original.includeGoals(goals);
          },
        ),
      ));
      if (!mounted || epoch != _accountEpoch || result == null) return;
      setState(() {
        _goals = result;
        if (!repository.canSync) _localGoals = result;
        _storeRecord(savedDay!);
      });
    } finally {
      if (mounted && epoch == _accountEpoch) {
        setState(() => _editingDetails = false);
        _advanceAfterRollover();
      }
    }
  }

  Future<void> _addCount(DhikrGoal goal) async {
    final epoch = _accountEpoch;
    final date = dateKey(_selected);
    final amount = await showDialog<int>(
        context: context, builder: (_) => _AddCountDialog(name: goal.name));
    if (!mounted || epoch != _accountEpoch || amount == null) return;
    if (date != dateKey(_selected)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'দিন পরিবর্তিত হয়েছে। নতুন দিনের জন্য আবার সংখ্যা লিখুন।')));
      return;
    }
    if (_visible.count(goal.id) + amount > DhikrDay.maxCount) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('এক দিনে সর্বোচ্চ ১০ লক্ষ গণনা রাখা যায়।')));
      return;
    }
    _enqueue(_CountChange(goal.id, amount));
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmed == null) {
      if (_loadFailed) {
        return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('যিকিরের হিসাব লোড করা যায়নি'),
          TextButton(onPressed: _load, child: const Text('রিট্রাই')),
        ]));
      }
      return const Center(child: CircularProgressIndicator());
    }
    final record = _visible;
    final isToday = record.date == dateKey(widget.today);
    final goal = record.goals.items.firstWhere(
        (goal) => goal.id == _selectedGoalId,
        orElse: () => record.goals.items.first);
    final count = record.count(goal.id);
    final controlsReady = !_loading && !_editingDetails;
    return RefreshIndicator(
        onRefresh: _load,
        child: TasbihFrame(
          children: [
            Row(children: [
              Expanded(
                  child: Semantics(
                      header: true,
                      child: Text('তসবিহ',
                          style: Theme.of(context).textTheme.headlineSmall))),
              IconButton(
                  tooltip: 'লক্ষ্য সম্পাদনা',
                  onPressed: _canLeaveDay && !_loading ? _editGoals : null,
                  icon: const Icon(Icons.tune)),
              IconButton(
                  tooltip: 'গণনা রিসেট করুন',
                  onPressed: _canLeaveDay && !_loading && count > 0
                      ? () => _resetCount(goal)
                      : null,
                  icon: const Icon(Icons.restart_alt)),
            ]),
            const SizedBox(height: 12),
            if (!widget.repository.canSync)
              const Card(
                  margin: EdgeInsets.only(bottom: 12),
                  child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                          'প্রিভিউ মোডে হিসাব অ্যাপ বন্ধ করলে সংরক্ষিত থাকবে না।'))),
            if (_loadFailed)
              Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                      title: const Text('নতুন তথ্য লোড করা যায়নি'),
                      trailing: TextButton(
                          onPressed: _load, child: const Text('রিট্রাই')))),
            if (_failedChanges.isNotEmpty)
              Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${banglaNumber(_failedChanges.length)}টি পরিবর্তন সংরক্ষণ হয়নি। আবার চেষ্টা করুন বা বাদ দিন।'),
                          Wrap(spacing: 8, children: [
                            TextButton(
                                onPressed: _loading
                                    ? null
                                    : () {
                                        final changes = List<_CountChange>.of(
                                            _failedChanges);
                                        setState(_failedChanges.clear);
                                        for (final change in changes) {
                                          _enqueue(change);
                                        }
                                      },
                                child: const Text('আবার সংরক্ষণ')),
                            TextButton(
                                onPressed: () {
                                  setState(_failedChanges.clear);
                                  _advanceAfterRollover();
                                },
                                child: const Text('বাদ দিন')),
                          ]),
                        ],
                      ))),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DhikrPhraseText(goal: goal),
                      const SizedBox(height: 12),
                      Text('${banglaNumber(count)} বার পড়া হয়েছে',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(height: 20),
                      LayoutBuilder(builder: (context, constraints) {
                        final target = OutlinedButton.icon(
                            key: const Key('dhikr-target'),
                            onPressed: _canLeaveDay && !_loading
                                ? () => _editTarget(goal)
                                : null,
                            icon: const Icon(Icons.flag_outlined, size: 18),
                            label: Text('লক্ষ্য ${banglaNumber(goal.target)}'));
                        final choices = FilledButton.icon(
                            onPressed:
                                _canLeaveDay && !_loading ? _chooseGoal : null,
                            icon: const Icon(Icons.format_list_bulleted,
                                size: 18),
                            label: const Text('যিকিরসমূহ'));
                        if (constraints.maxWidth < 300 ||
                            MediaQuery.textScalerOf(context).scale(14) > 20) {
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                target,
                                const SizedBox(height: 10),
                                choices
                              ]);
                        }
                        return Row(children: [
                          Expanded(child: target),
                          const SizedBox(width: 10),
                          Expanded(child: choices)
                        ]);
                      }),
                      const SizedBox(height: 28),
                      TasbihCounter(
                        goal: goal,
                        count: count,
                        onTap: controlsReady && count < DhikrDay.maxCount
                            ? () {
                                unawaited(HapticFeedback.selectionClick());
                                _enqueue(_CountChange(goal.id, 1));
                              }
                            : null,
                      ),
                      const SizedBox(height: 20),
                      Text(
                          '${banglaNumber(count)} / ${banglaNumber(goal.target)}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(
                          count >= goal.target
                              ? 'লক্ষ্য পূরণ হয়েছে'
                              : 'আরও ${banglaNumber(goal.target - count)} বার বাকি',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary)),
                      if (_pending.isNotEmpty || _editingDetails) ...[
                        const SizedBox(height: 8),
                        Text(
                            _editingDetails
                                ? 'পরিবর্তন সংরক্ষণ হচ্ছে…'
                                : 'গণনা সংরক্ষণ হচ্ছে…',
                            textAlign: TextAlign.center),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                                onPressed: controlsReady && count > 0
                                    ? () => _enqueue(_CountChange(goal.id, -1))
                                    : null,
                                icon: const Icon(Icons.remove, size: 18),
                                label: const Text('এক কমান')),
                            TextButton(
                                onPressed: controlsReady
                                    ? () => _addCount(goal)
                                    : null,
                                child: const Text('সংখ্যা যোগ করুন')),
                          ]),
                    ]),
              ),
            ),
            const SizedBox(height: 16),
            Text(
                '${banglaNumber(record.goalsMet)} / ${banglaNumber(record.goals.items.length)} লক্ষ্য পূরণ',
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
                'এগুলো আপনার ব্যক্তিগত লক্ষ্য। লক্ষ্য বাটনে এই দিনের সংখ্যা বদলান। উপরের সেটিংস থেকে নিজের যিকির যোগ করুন।',
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Card(
                child: Row(children: [
              IconButton(
                  tooltip: 'আগের দিন',
                  onPressed: _canLeaveDay &&
                          !_loading &&
                          _selected.isAfter(DateTime(2000))
                      ? () => _selectDay(DateTime(
                          _selected.year, _selected.month, _selected.day - 1))
                      : null,
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                  child: TextButton(
                      onPressed: _canLeaveDay && !_loading ? _pickDay : null,
                      child: Text(
                          '${compactDateLabel(_selected)}${isToday ? ' • আজ' : ''}'))),
              IconButton(
                  tooltip: 'পরের দিন',
                  onPressed: !isToday && _canLeaveDay && !_loading
                      ? () => _selectDay(DateTime(
                          _selected.year, _selected.month, _selected.day + 1))
                      : null,
                  icon: const Icon(Icons.chevron_right)),
            ])),
            const SizedBox(height: 16),
            Text('গত ৭ দিন', style: Theme.of(context).textTheme.titleLarge),
            Text(
                '${banglaNumber(_history!.loggedDays)} দিন হিসাব • মোট ${banglaNumber(_history!.total)} বার'),
            const SizedBox(height: 8),
            Card(
                child: Column(children: [
              for (final day in _history!.days.reversed)
                ListTile(
                    title: Text(compactDateLabel(DateTime.parse(day.date))),
                    subtitle: Text(day.logged
                        ? '${banglaNumber(day.total)} বার • ${banglaNumber(day.goalsMet)}/${banglaNumber(day.goals.items.length)} লক্ষ্য পূরণ'
                        : 'হিসাব লেখা হয়নি'),
                    selected: day.date == record.date,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _canLeaveDay && !_loading
                        ? () => _selectDay(DateTime.parse(day.date))
                        : null),
            ])),
          ],
        ));
  }
}

class _DhikrTargetDialog extends StatefulWidget {
  const _DhikrTargetDialog({required this.goal, required this.onSave});
  final DhikrGoal goal;
  final Future<DhikrDay> Function(int) onSave;

  @override
  State<_DhikrTargetDialog> createState() => _DhikrTargetDialogState();
}

class _DhikrTargetDialogState extends State<_DhikrTargetDialog> {
  late final _target = TextEditingController(text: '${widget.goal.target}');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final target = int.tryParse(_target.text) ?? 0;
    if (target < 1 || target > 100000) {
      setState(() => _error = '১ থেকে ১০০০০০ এর মধ্যে লক্ষ্য লিখুন');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final record = await widget.onSave(target);
      if (mounted) Navigator.pop(context, record);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'লক্ষ্য সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: const Text('লক্ষ্য নির্ধারণ'),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.goal.name),
                  const SizedBox(height: 8),
                  const Text(
                      'এই দিনের ব্যক্তিগত লক্ষ্য ঠিক করুন। আগের গণনা ঠিক থাকবে।'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _target,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 6,
                    decoration: InputDecoration(
                        labelText: 'কতবার পড়বেন?',
                        errorText: _error,
                        counterText: ''),
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final value in [33, 34, 100, 1000])
                      OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  _target.text = '$value';
                                },
                          child: Text(banglaNumber(value))),
                  ]),
                ]),
          ),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('বাতিল')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'সংরক্ষণ হচ্ছে…' : 'সংরক্ষণ')),
          ],
        ),
      );
}

class _AddCountDialog extends StatefulWidget {
  const _AddCountDialog({required this.name});
  final String name;
  @override
  State<_AddCountDialog> createState() => _AddCountDialogState();
}

class _AddCountDialogState extends State<_AddCountDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.name),
        content: Form(
            key: _form,
            child: TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'কতবার যোগ করবেন?'),
              validator: (text) {
                final value = int.tryParse(text ?? '');
                return value == null || value < 1 || value > 100000
                    ? '১ থেকে ১০০০০০ লিখুন'
                    : null;
              },
            )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('বাতিল')),
          FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, int.parse(_amount.text));
                }
              },
              child: const Text('যোগ করুন')),
        ],
      );
}

class _GoalDraft {
  _GoalDraft(DhikrGoal goal)
      : id = goal.id,
        name = TextEditingController(text: goal.name),
        target = TextEditingController(text: '${goal.target}');
  final String id;
  final TextEditingController name;
  final TextEditingController target;
  void dispose() {
    name.dispose();
    target.dispose();
  }
}

class _DhikrGoalsEditor extends StatefulWidget {
  const _DhikrGoalsEditor({required this.initial, required this.onSave});
  final DhikrGoals initial;
  final Future<void> Function(DhikrGoals) onSave;
  @override
  State<_DhikrGoalsEditor> createState() => _DhikrGoalsEditorState();
}

class _DhikrGoalsEditorState extends State<_DhikrGoalsEditor> {
  final _form = GlobalKey<FormState>();
  late final _drafts = widget.initial.items.map(_GoalDraft.new).toList();
  final _removed = <_GoalDraft>[];
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    for (final draft in [..._drafts, ..._removed]) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final goals = DhikrGoals(_drafts.map((draft) => DhikrGoal(
        id: draft.id,
        name: draft.name.text.trim(),
        target: int.parse(draft.target.text))));
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSave(goals);
      if (mounted) Navigator.pop(context, goals);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('যিকিরের লক্ষ্য সম্পাদনা'),
            automaticallyImplyLeading: !_saving),
        body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              const Text(
                  '১ থেকে ২০টি ব্যক্তিগত লক্ষ্য রাখুন। নতুন যিকির আজই গণনা করতে পারবেন। আগে গণনা করা যিকিরের লক্ষ্য ঠিক থাকবে।'),
              const SizedBox(height: 12),
              for (final draft in _drafts)
                Card(
                    key: ValueKey(draft.id),
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(children: [
                          TextFormField(
                              controller: draft.name,
                              enabled: !_saving,
                              maxLength: 60,
                              decoration: const InputDecoration(
                                  labelText: 'যিকিরের নাম'),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? 'নাম লিখুন'
                                      : null),
                          TextFormField(
                              controller: draft.target,
                              enabled: !_saving,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: const InputDecoration(
                                  labelText: 'দৈনিক লক্ষ্য'),
                              validator: (value) {
                                final target = int.tryParse(value ?? '');
                                return target == null ||
                                        target < 1 ||
                                        target > 100000
                                    ? '১ থেকে ১০০০০০ লিখুন'
                                    : null;
                              }),
                          Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                  onPressed: _saving || _drafts.length == 1
                                      ? null
                                      : () {
                                          setState(() {
                                            _drafts.remove(draft);
                                            _removed.add(draft);
                                          });
                                        },
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('সরিয়ে দিন'))),
                        ]))),
              TextButton.icon(
                  onPressed: _saving || _drafts.length >= 20
                      ? null
                      : () {
                          setState(() => _drafts.add(_GoalDraft(DhikrGoal(
                              id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
                              name: '',
                              target: 100))));
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('নতুন লক্ষ্য')),
              if (_failed)
                const Text('লক্ষ্য সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'সংরক্ষণ হচ্ছে…' : 'লক্ষ্য সংরক্ষণ')),
              const SizedBox(height: 40),
            ])),
      ));
}
