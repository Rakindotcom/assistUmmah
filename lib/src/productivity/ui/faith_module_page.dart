import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_repository.dart';
import '../../date_helpers.dart';
import '../../pages/dhikr_page.dart';
import '../../pages/dua_library_page.dart';
import '../../pages/growth_page.dart';
import '../../pages/prayer_page.dart';
import '../../pages/quran_page.dart';

/// Presents the existing Faith data without exposing legacy task routes.
/// The universal shell owns the outer app bar and module navigation.
class FaithModulePage extends StatefulWidget {
  const FaithModulePage({
    super.key,
    required this.repository,
    this.clock,
  });

  final AppRepository repository;
  final DateTime Function()? clock;

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
          tabs: const [
            Tab(text: 'নামাজ'),
            Tab(text: 'কুরআন'),
            Tab(text: 'জিকির'),
            Tab(text: 'গ্রোথ'),
            Tab(text: 'দোয়া'),
          ],
        ),
        Expanded(
          child: IndexedStack(index: _selected, children: [
            PrayerPage(
                key: ValueKey('faith-prayer-${dateKey(_day)}'),
                repository: repository,
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
                    key: ValueKey('faith-growth-${dateKey(_day)}'),
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
