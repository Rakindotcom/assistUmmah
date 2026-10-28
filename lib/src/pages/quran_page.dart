import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_repository.dart';
import '../display_formatters.dart';
import '../app_calendar_delegate.dart';
import '../date_helpers.dart';
import '../quran_reading.dart';
import '../widgets/page_frame.dart';
import '../widgets/responsive_cards.dart';

class QuranPage extends StatefulWidget {
  const QuranPage({
    super.key,
    required this.repository,
    required this.today,
    this.active = true,
  });

  final AppRepository repository;
  final DateTime today;
  final bool active;

  @override
  State<QuranPage> createState() => _QuranPageState();
}

class _QuranPageState extends State<QuranPage> with WidgetsBindingObserver {
  late DateTime _selectedDay = dateOnly(widget.today);
  QuranGoal _goal = QuranGoal.standard;
  QuranReadingDay? _record;
  QuranHistory? _history;
  final Map<String, Map<String, dynamic>> _localDocuments = {};
  QuranGoal _localGoal = QuranGoal.standard;
  bool _loading = true;
  bool _failed = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant QuranPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository.uid != widget.repository.uid) {
      _selectedDay = dateOnly(widget.today);
      _localDocuments.clear();
      _localGoal = QuranGoal.standard;
      _record = null;
      _history = null;
      _load();
    } else if (dateKey(oldWidget.today) != dateKey(widget.today)) {
      _selectedDay = dateOnly(widget.today);
      _load();
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

  @override
  Widget build(BuildContext context) {
    if (_loading && _record == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed && _record == null) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('কুরআন রিডিংয়ের তথ্য লোড করা যায়নি'),
                TextButton(onPressed: _load, child: const Text('রিট্রাই')),
              ],
            ),
          ),
        ),
      );
    }
    final record = _record!;
    final today = dateOnly(widget.today);
    final isToday = dateKey(_selectedDay) == dateKey(today);
    final unit = _unitLabel(record.goal.unit);
    final history = _history!;
    return RefreshIndicator(
      onRefresh: _load,
      child: PageFrame(
        title: 'কুরআন রিডিং',
        subtitle: 'প্রতিদিনের লক্ষ্য, পড়া ও শেষ পড়ার স্থান লিখে রাখুন',
        children: [
          if (!widget.repository.canSync)
            const Card(
              margin: EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                    'প্রিভিউ মোডে হিসাব অ্যাপ বন্ধ করলে সংরক্ষিত থাকবে না।'),
              ),
            ),
          if (_failed)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: const Text('নতুন তথ্য লোড করা যায়নি'),
                trailing:
                    TextButton(onPressed: _load, child: const Text('রিট্রাই')),
              ),
            ),
          Card(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'আগের দিন',
                  onPressed: () => _selectDay(DateTime(
                    _selectedDay.year,
                    _selectedDay.month,
                    _selectedDay.day - 1,
                  )),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _pickDay,
                    child: Text(
                      '${compactDateLabel(_selectedDay)}${isToday ? ' • আজ' : ''}',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'পরের দিন',
                  onPressed: isToday
                      ? null
                      : () => _selectDay(DateTime(
                            _selectedDay.year,
                            _selectedDay.month,
                            _selectedDay.day + 1,
                          )),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ResponsiveCards(children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('দৈনিক লক্ষ্য',
                              style: Theme.of(context).textTheme.titleLarge),
                        ),
                        if (isToday)
                          TextButton(
                            onPressed: _editGoal,
                            child: const Text('পরিবর্তন'),
                          ),
                      ],
                    ),
                    Text('${banglaNumber(record.goal.target)} $unit'),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                        value: record.fraction,
                        borderRadius: BorderRadius.circular(8)),
                    const SizedBox(height: 8),
                    Text(record.logged
                        ? '${banglaNumber(record.completed)} / ${banglaNumber(record.goal.target)} $unit '
                            '${record.goalMet ? '• লক্ষ্য পূরণ' : '• চলমান'}'
                        : 'এই দিনের রিডিং হিসাব লেখা হয়নি'),
                    if (!isToday)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('এই দিনের সংরক্ষিত লক্ষ্য দেখানো হচ্ছে।'),
                      ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('এই দিনের রিডিং',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(record.logged
                        ? '${banglaNumber(record.minutes)} মিনিট • ${banglaNumber(record.pages)} পৃষ্ঠা'
                        : 'এখনো কোনো হিসাব লেখা হয়নি'),
                    if (record.lastRead.isNotEmpty)
                      Text('শেষ পড়া: ${record.lastRead}'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _editReading,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(record.logged
                          ? 'হিসাব সংশোধন করুন'
                          : 'রিডিং হিসাব লিখুন'),
                    ),
                  ],
                ),
              ),
            ),
          ]),
          const SizedBox(height: 28),
          Text('শেষ ৭ দিন', style: Theme.of(context).textTheme.titleLarge),
          Text('${banglaNumber(history.loggedDays)}/৭ দিন লেখা • '
              '${banglaNumber(history.goalsMet)} দিন লক্ষ্য পূরণ • '
              '${banglaNumber(history.totalMinutes)} মিনিট • ${banglaNumber(history.totalPages)} পৃষ্ঠা'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final day in history.days.reversed)
                  ListTile(
                    title: Text(compactDateLabel(DateTime.parse(day.date))),
                    subtitle: Text(day.logged
                        ? '${banglaNumber(day.minutes)} মিনিট • ${banglaNumber(day.pages)} পৃষ্ঠা'
                        : 'হিসাব নেই'),
                    trailing: day.goalMet
                        ? Icon(Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                            semanticLabel: 'দৈনিক লক্ষ্য পূরণ')
                        : null,
                    selected: day.date == record.date,
                    onTap: () => _selectDay(DateTime.parse(day.date)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _unitLabel(QuranGoalUnit unit) =>
      unit == QuranGoalUnit.minutes ? 'মিনিট' : 'পৃষ্ঠা';

  Future<void> _load() async {
    final requestId = ++_requestId;
    if (mounted) setState(() => _loading = true);
    try {
      late final QuranGoal goal;
      late final Map<String, dynamic>? document;
      late final QuranHistory history;
      if (widget.repository.canSync) {
        goal = await widget.repository.loadQuranGoal();
        document =
            await widget.repository.loadQuranDocument(dateKey(_selectedDay));
        history = await widget.repository.loadQuranHistory(
          end: widget.today,
          fallbackGoal: goal,
        );
      } else {
        goal = _localGoal;
        document = _localDocuments[dateKey(_selectedDay)];
        history = QuranHistory.fromDocuments(
          end: widget.today,
          dayCount: 7,
          documents: _localDocuments,
          fallbackGoal: goal,
        );
      }
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _goal = goal;
        _record = QuranReadingDay.fromDocument(
          dateKey(_selectedDay),
          document,
          fallbackGoal: goal,
        );
        _history = history;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _selectDay(DateTime day) {
    final selected = dateOnly(day);
    if (selected.isAfter(dateOnly(widget.today)) ||
        selected.isBefore(DateTime(1900)) ||
        dateKey(selected) == dateKey(_selectedDay)) {
      return;
    }
    setState(() {
      _selectedDay = selected;
      _record = null;
    });
    _load();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      calendarDelegate: AppCalendarDelegate(Localizations.localeOf(context)),
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(1900),
      lastDate: dateOnly(widget.today),
    );
    if (picked != null) _selectDay(picked);
  }

  Future<void> _editGoal() async {
    final updated = await showDialog<QuranGoal>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _QuranGoalEditor(
        initial: _goal,
        onSave: (goal) async {
          if (widget.repository.canSync) {
            await widget.repository.saveQuranGoal(goal, today: widget.today);
          } else {
            _localGoal = goal;
            final todayKey = dateKey(widget.today);
            if (_localDocuments.containsKey(todayKey)) {
              _localDocuments[todayKey] = {
                ..._localDocuments[todayKey]!,
                'goal': goal.toMap(),
              };
            }
          }
        },
      ),
    );
    if (updated != null && mounted) await _load();
  }

  Future<void> _editReading() async {
    final saved = await Navigator.of(context).push<QuranReadingDay>(
      MaterialPageRoute(
        builder: (_) => _QuranLogEditor(
          initial: _record!,
          onSave: (day) async {
            if (widget.repository.canSync) {
              await widget.repository.saveQuranDay(day);
            } else {
              _localDocuments[day.date] = day.toMap();
            }
          },
        ),
      ),
    );
    if (saved != null && mounted) await _load();
  }
}

class _QuranGoalEditor extends StatefulWidget {
  const _QuranGoalEditor({required this.initial, required this.onSave});

  final QuranGoal initial;
  final Future<void> Function(QuranGoal) onSave;

  @override
  State<_QuranGoalEditor> createState() => _QuranGoalEditorState();
}

class _QuranGoalEditorState extends State<_QuranGoalEditor> {
  late QuranGoalUnit _unit = widget.initial.unit;
  late final TextEditingController _target =
      TextEditingController(text: '${widget.initial.target}');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('দৈনিক লক্ষ্য পরিবর্তন'),
        content: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<QuranGoalUnit>(
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'লক্ষ্যের ধরন'),
                  items: const [
                    DropdownMenuItem(
                      value: QuranGoalUnit.minutes,
                      child: Text('মিনিট'),
                    ),
                    DropdownMenuItem(
                      value: QuranGoalUnit.pages,
                      child: Text('পৃষ্ঠা'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _unit = value);
                        },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _target,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText:
                        'প্রতিদিন কত ${_unit == QuranGoalUnit.minutes ? 'মিনিট' : 'পৃষ্ঠা'}',
                    errorText: _error,
                    counterText: '',
                  ),
                ),
              ],
            )),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('সংরক্ষণ'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final goal = QuranGoal(
      unit: _unit,
      target: int.tryParse(_target.text) ?? 0,
    );
    if (!goal.valid) {
      setState(() => _error =
          '১ থেকে ${banglaNumber(goal.maxTarget)} এর মধ্যে লক্ষ্য লিখুন');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(goal);
      if (mounted) Navigator.of(context).pop(goal);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'লক্ষ্য সংরক্ষণ করা যায়নি';
        });
      }
    }
  }
}

class _QuranLogEditor extends StatefulWidget {
  const _QuranLogEditor({required this.initial, required this.onSave});

  final QuranReadingDay initial;
  final Future<void> Function(QuranReadingDay) onSave;

  @override
  State<_QuranLogEditor> createState() => _QuranLogEditorState();
}

class _QuranLogEditorState extends State<_QuranLogEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _minutes =
      TextEditingController(text: '${widget.initial.minutes}');
  late final TextEditingController _pages =
      TextEditingController(text: '${widget.initial.pages}');
  late final TextEditingController _lastRead =
      TextEditingController(text: widget.initial.lastRead);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    _pages.dispose();
    _lastRead.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
            title: Text(compactDateLabel(DateTime.parse(widget.initial.date))),
            automaticallyImplyLeading: !_saving),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('এই দিনের কুরআন রিডিং',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _minutes,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 4,
                      decoration: const InputDecoration(
                          labelText: 'মিনিট', counterText: ''),
                      validator: (value) => _validateCount(value, 1440),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pages,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 4,
                      decoration: const InputDecoration(
                          labelText: 'পৃষ্ঠা', counterText: ''),
                      validator: (value) => _validateCount(value, 1000),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _lastRead,
                      enabled: !_saving,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'শেষ পড়া স্থান (ঐচ্ছিক)',
                        hintText: 'যেমন: সূরা বাকারা, আয়াত ২০',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('হিসাব সংরক্ষণ'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _validateCount(String? value, int max) {
    final parsed = int.tryParse(value ?? '');
    return parsed == null || parsed < 0 || parsed > max
        ? '০ থেকে ${banglaNumber(max)} এর মধ্যে লিখুন'
        : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final day = QuranReadingDay(
      date: widget.initial.date,
      logged: true,
      minutes: int.parse(_minutes.text),
      pages: int.parse(_pages.text),
      lastRead: _lastRead.text.trim(),
      goal: widget.initial.goal,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(day);
      if (mounted) Navigator.of(context).pop(day);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'রিডিং হিসাব সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।';
        });
      }
    }
  }
}
