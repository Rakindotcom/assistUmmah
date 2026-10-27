import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../display_formatters.dart';
import '../app_calendar_delegate.dart';
import '../growth_progress.dart';
import '../date_helpers.dart';
import '../models.dart';
import '../widgets/page_frame.dart';
import 'growth_page.dart';
import 'prayer_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.repository,
    required this.today,
    this.refreshToken = 0,
    this.initialDay,
  });

  final AppRepository repository;
  final DateTime today;
  final int refreshToken;
  final DateTime? initialDay;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _selectedDay;
  Map<String, dynamic>? _prayerDocument;
  Map<String, dynamic>? _growthDocument;
  bool _loading = true;
  bool _loadFailed = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    final requested = dateOnly(widget.initialDay ?? widget.today);
    _selectedDay = requested.isAfter(dateOnly(widget.today))
        ? dateOnly(widget.today)
        : requested.isBefore(DateTime(1900))
            ? DateTime(1900)
            : requested;
    _load();
  }

  @override
  void didUpdateWidget(covariant CalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository.uid != widget.repository.uid) {
      _selectedDay = dateOnly(widget.today);
      _prayerDocument = null;
      _growthDocument = null;
      _load();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    } else if (_selectedDay.isAfter(dateOnly(widget.today))) {
      _selectDay(widget.today);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(widget.today);
    final isToday = dateKey(_selectedDay) == dateKey(today);
    final prayerSummary = PrayerSummary.fromDocument(_prayerDocument);
    final growth = asStringMap(_growthDocument?['growthData']);
    final growthItems = GrowthChecklistSnapshot.fromDocument(_growthDocument);
    final imanScore = checklistScore(
      imanValuesForDocuments(_growthDocument, _prayerDocument),
      growthItems.iman,
    );
    final lifeScore = checklistScore(
      parseBoolMap(growth['life']),
      growthItems.life,
    );

    final navigation = Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            IconButton(
                key: const Key('calendar_previous_day'),
                tooltip: 'আগের দিন',
                onPressed: () => _selectDay(DateTime(_selectedDay.year,
                    _selectedDay.month, _selectedDay.day - 1)),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
                child: Text(
                    '${compactDateLabel(_selectedDay)}${isToday ? ' • আজ' : ''}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
                tooltip: 'পরের দিন',
                onPressed: isToday
                    ? null
                    : () => _selectDay(DateTime(_selectedDay.year,
                        _selectedDay.month, _selectedDay.day + 1)),
                icon: const Icon(Icons.chevron_right)),
          ])),
    );
    final records =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      navigation,
      const SizedBox(height: 16),
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (_loadFailed)
        Card(
            child: ListTile(
                leading: const Icon(Icons.sync_problem_outlined),
                title: const Text('এই দিনের হিসাব লোড করা যায়নি'),
                trailing:
                    TextButton(onPressed: _load, child: const Text('রিট্রাই'))))
      else ...[
        Card(
            child: ListTile(
                leading: const Icon(Icons.mosque_outlined),
                title: const Text('নামাজের হিসাব'),
                subtitle: Text(!prayerSummary.anyLogged
                    ? 'এই দিনে কোনো নামাজের হিসাব লেখা হয়নি'
                    : '${banglaNumber(prayerSummary.prayed)} পড়া • ${banglaNumber(prayerSummary.missed)} মিস • '
                        '${banglaNumber(prayerSummary.madeUp)} কাযা • ${banglaNumber(prayerSummary.unlogged)} হিসাব নেই'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _editPrayer)),
        const SizedBox(height: 12),
        Card(
            child: ListTile(
                leading: const Icon(Icons.trending_up),
                title: const Text('গ্রোথ চেকলিস্ট'),
                subtitle: Text(growth.isEmpty
                    ? 'এই দিনে কোনো গ্রোথ হিসাব লেখা হয়নি'
                    : 'ইমান ${banglaNumber(imanScore)}% • লাইফ ${banglaNumber(lifeScore)}%'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _editGrowth)),
      ],
    ]);
    final picker = Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('দিন নির্বাচন করুন',
                          style: Theme.of(context).textTheme.titleSmall))),
              Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: CalendarDatePicker(
                          calendarDelegate: AppCalendarDelegate(
                              Localizations.localeOf(context)),
                          key: ValueKey(dateKey(_selectedDay)),
                          initialDate: _selectedDay,
                          firstDate: DateTime(1900),
                          lastDate: today,
                          currentDate: today,
                          onDateChanged: _selectDay))),
            ])));
    return PageFrame(
      title: 'দিনপঞ্জি',
      subtitle: 'আগের দিনের নামাজ ও গ্রোথের হিসাব দেখুন এবং সংশোধন করুন',
      children: [
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= 760) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: picker),
              const SizedBox(width: 24),
              Expanded(child: records),
            ]);
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                records,
                const SizedBox(height: 16),
                picker,
              ]);
        })
      ],
    );
  }

  void _selectDay(DateTime day) {
    final selected = dateOnly(day);
    if (selected.isAfter(dateOnly(widget.today)) ||
        selected.isBefore(DateTime(1900))) {
      return;
    }
    if (dateKey(selected) == dateKey(_selectedDay)) return;
    setState(() => _selectedDay = selected);
    _load();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    final dayKey = dateKey(_selectedDay);
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final documents = await Future.wait([
        widget.repository.loadPrayerDocument(dayKey),
        widget.repository.loadGrowth(dayKey),
      ]);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _prayerDocument = documents[0];
        _growthDocument = documents[1];
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _prayerDocument = null;
        _growthDocument = null;
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _editPrayer() async {
    final day = _selectedDay;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(compactDateLabel(day))),
          body: PrayerPage(
            repository: widget.repository,
            day: day,
            historical: dateKey(day) != dateKey(widget.today),
            onSaved: () {
              if (mounted && dateKey(_selectedDay) == dateKey(day)) _load();
            },
            onSaveError: (message) => _showSaveError(day, message),
          ),
        ),
      ),
    );
    if (mounted && dateKey(_selectedDay) == dateKey(day)) await _load();
  }

  Future<void> _editGrowth() async {
    final day = _selectedDay;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(compactDateLabel(day))),
          body: GrowthPage(
            repository: widget.repository,
            day: day,
            historical: dateKey(day) != dateKey(widget.today),
            onSaved: () {
              if (mounted && dateKey(_selectedDay) == dateKey(day)) _load();
            },
            onSaveError: (message) => _showSaveError(day, message),
          ),
        ),
      ),
    );
    if (mounted && dateKey(_selectedDay) == dateKey(day)) await _load();
  }

  void _showSaveError(DateTime day, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${compactDateLabel(day)}: $message')),
    );
  }
}
