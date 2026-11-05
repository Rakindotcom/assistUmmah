import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_repository.dart';
import '../../date_helpers.dart';
import '../../pages/calendar_page.dart';
import '../../pages/dhikr_page.dart';
import '../../pages/dua_library_page.dart';
import '../../pages/growth_page.dart';
import '../../pages/prayer_page.dart';
import '../../pages/quran_page.dart';
import '../../pages/report_dialog.dart';
import '../../pages/trends_page.dart';
import 'experience_strings.dart';

/// Presents the existing Faith data without exposing legacy task routes.
/// The universal shell owns the outer app bar and module navigation.
class FaithModulePage extends StatefulWidget {
  const FaithModulePage({
    super.key,
    required this.repository,
    this.clock,
    this.enableNotifications = true,
    this.language = 'bn',
  });

  final AppRepository repository;
  final DateTime Function()? clock;
  final bool enableNotifications;
  final String language;

  @override
  State<FaithModulePage> createState() => _FaithModulePageState();
}

class _FaithModulePageState extends State<FaithModulePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs;
  late DateTime _day;
  Timer? _dayTimer;
  final _opened = <int>{0};
  int _selected = 0;
  int _historyRevision = 0;
  bool _openingRoute = false;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _day = dateOnly(_now());
    _tabs = TabController(length: 5, vsync: this);
    _tabs.addListener(_onTabChanged);
    WidgetsBinding.instance.addObserver(this);
    _scheduleDayChange();
  }

  @override
  void didUpdateWidget(FaithModulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository.uid != widget.repository.uid) {
      _selected = 0;
      _tabs.index = 0;
      _opened
        ..clear()
        ..add(0);
      _day = dateOnly(_now());
      _historyRevision = 0;
      _openingRoute = false;
      _scheduleDayChange();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDay();
  }

  void _scheduleDayChange() {
    _dayTimer?.cancel();
    final now = _now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _dayTimer = Timer(next.difference(now), _refreshDay);
  }

  void _refreshDay() {
    if (!mounted) return;
    final today = dateOnly(_now());
    if (dateKey(today) != dateKey(_day)) {
      setState(() => _day = today);
    }
    _scheduleDayChange();
  }

  void _onTabChanged() {
    final index = _tabs.index;
    if (index == _selected) return;
    setState(() {
      _selected = index;
      _opened.add(index);
    });
  }

  Future<void> _openRoute(WidgetBuilder builder) async {
    if (_openingRoute) return;
    final repository = widget.repository;
    setState(() => _openingRoute = true);
    try {
      await Navigator.of(context)
          .push<void>(MaterialPageRoute<void>(builder: builder));
    } finally {
      if (mounted && repository.uid == widget.repository.uid) {
        setState(() {
          _openingRoute = false;
          _historyRevision++;
        });
      }
    }
  }

  Future<void> _openHistory() {
    final repository = widget.repository;
    final day = _day;
    final notifications = widget.enableNotifications;
    final strings = ExperienceStrings(widget.language);
    return _openRoute((_) => Scaffold(
        appBar: AppBar(
            title: Text(strings.text('Faith history', 'আমলের দিনপঞ্জি'))),
        body: CalendarPage(
            repository: repository,
            today: day,
            enableNotifications: notifications)));
  }

  Future<void> _openReports() {
    final repository = widget.repository;
    final day = _day;
    final notifications = widget.enableNotifications;
    final language = widget.language;
    return _openRoute((_) => _FaithReportsPage(
        repository: repository,
        today: day,
        language: language,
        enableNotifications: notifications));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final strings = ExperienceStrings(widget.language);
    return PopScope<void>(
      canPop: _selected == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _tabs.animateTo(0);
      },
      child: Column(children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: strings.text('Prayer', 'নামাজ')),
            Tab(text: strings.text('Quran', 'কুরআন')),
            Tab(text: strings.text('Dhikr', 'জিকির')),
            Tab(text: strings.text('Growth', 'গ্রোথ')),
            Tab(text: strings.text('Duas', 'দোয়া')),
          ],
        ),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, children: [
                  TextButton.icon(
                      onPressed: _openingRoute ? null : _openHistory,
                      icon: const Icon(Icons.history_outlined),
                      label: Text(strings.text('History', 'দিনপঞ্জি'))),
                  TextButton.icon(
                      onPressed: _openingRoute ? null : _openReports,
                      icon: const Icon(Icons.insights_outlined),
                      label: Text(strings.text('Reports', 'রিপোর্ট'))),
                ]))),
        Expanded(
          child: IndexedStack(index: _selected, children: [
            PrayerPage(
                key:
                    ValueKey('faith-prayer-${dateKey(_day)}-$_historyRevision'),
                repository: repository,
                enableNotifications: widget.enableNotifications,
                day: _day,
                active: _selected == 0),
            _opened.contains(1)
                ? QuranPage(
                    key: ValueKey('faith-quran-${dateKey(_day)}'),
                    repository: repository,
                    today: _day,
                    active: _selected == 1)
                : const SizedBox.shrink(),
            _opened.contains(2)
                ? DhikrPage(
                    key: ValueKey('faith-dhikr-${dateKey(_day)}'),
                    repository: repository,
                    today: _day,
                    active: _selected == 2)
                : const SizedBox.shrink(),
            _opened.contains(3)
                ? GrowthPage(
                    key: ValueKey(
                        'faith-growth-${dateKey(_day)}-$_historyRevision'),
                    repository: repository,
                    day: _day,
                    onOpenQuran: () => _tabs.animateTo(1),
                    onOpenDhikr: () => _tabs.animateTo(2))
                : const SizedBox.shrink(),
            _opened.contains(4)
                ? const DuaLibraryPage()
                : const SizedBox.shrink(),
          ]),
        ),
      ]),
    );
  }
}

class _FaithReportsPage extends StatelessWidget {
  const _FaithReportsPage(
      {required this.repository,
      required this.today,
      required this.language,
      required this.enableNotifications});
  final AppRepository repository;
  final DateTime today;
  final String language;
  final bool enableNotifications;

  Future<void> _report(BuildContext context, String title, DateTime start) =>
      showDialog<void>(
          context: context,
          builder: (_) => ReportDialog(
              repository: repository, title: title, start: start, end: today));

  @override
  Widget build(BuildContext context) {
    final strings = ExperienceStrings(language);
    final daily = strings.text('Daily report', 'দৈনিক রিপোর্ট');
    final weekly = strings.text('Weekly report', 'সাপ্তাহিক রিপোর্ট');
    final monthly = strings.text('Monthly report', 'মাসিক রিপোর্ট');
    return Scaffold(
        appBar:
            AppBar(title: Text(strings.text('Faith reports', 'আমলের রিপোর্ট'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
              strings.text('Review your prayer and growth records.',
                  'নামাজ ও গ্রোথের সংরক্ষিত হিসাব পর্যালোচনা করুন।'),
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          Card(
              child: Column(children: [
            ListTile(
                leading: const Icon(Icons.today_outlined),
                title: Text(daily),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _report(context, daily, today)),
            const Divider(height: 1),
            ListTile(
                leading: const Icon(Icons.calendar_view_week_outlined),
                title: Text(weekly),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _report(context, weekly,
                    DateTime(today.year, today.month, today.day - 6))),
            const Divider(height: 1),
            ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: Text(monthly),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _report(
                    context, monthly, DateTime(today.year, today.month))),
            const Divider(height: 1),
            ListTile(
                leading: const Icon(Icons.show_chart_outlined),
                title:
                    Text(strings.text('Progress trends', 'অগ্রগতির ট্রেন্ড')),
                subtitle:
                    Text(strings.text('Last 7 and 30 days', 'শেষ ৭ ও ৩০ দিন')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                            appBar: AppBar(
                                title: Text(strings.text(
                                    'Progress trends', 'অগ্রগতির ট্রেন্ড'))),
                            body: TrendsPage(
                                repository: repository,
                                today: today,
                                enableNotifications: enableNotifications))))),
          ])),
        ]));
  }
}
