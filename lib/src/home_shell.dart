import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_repository.dart';
import 'date_helpers.dart';
import 'reminder_session.dart';
import 'pages/contacts_page.dart';
import 'pages/calendar_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/dhikr_page.dart';
import 'pages/growth_page.dart';
import 'pages/more_page.dart';
import 'pages/prayer_page.dart';
import 'pages/quran_page.dart';
import 'pages/settings_page.dart';
import 'pages/tasks_page.dart';
import 'widgets/app_brand.dart';
import 'widgets/status_badge.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.firebaseReady,
    required this.repository,
    required this.user,
    this.clock,
  });

  final bool firebaseReady;
  final AppRepository repository;
  final User? user;
  final DateTime Function()? clock;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  int _dashboardRefreshToken = 0;
  int _growthRefreshToken = 0;
  int _calendarRefreshToken = 0;
  int _detailReturnIndex = 4;
  final Set<int> _openedPages = {0};
  late ReminderSession _reminders;
  late DateTime _day;
  Timer? _dayTimer;

  @override
  void initState() {
    super.initState();
    _day = dateOnly(_now());
    WidgetsBinding.instance.addObserver(this);
    _scheduleDayChange();
    _reminders = ReminderSession(repository: widget.repository);
    unawaited(_refreshReminders());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayTimer?.cancel();
    _reminders.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDay();
      unawaited(_refreshReminders());
      if (_index == 0 && mounted) {
        setState(() => _dashboardRefreshToken++);
      } else if (_index == 3 && mounted) {
        setState(() => _growthRefreshToken++);
      }
    }
  }

  Future<void> _refreshReminders() async {
    final refreshed = await _reminders.refresh();
    if (!mounted || refreshed) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('রিমাইন্ডার রিফ্রেশ করা যায়নি।'),
      action: SnackBarAction(
        label: 'আবার চেষ্টা',
        onPressed: () => unawaited(_refreshReminders()),
      ),
    ));
  }

  void _selectPage(int index) {
    setState(() {
      if (index >= 5) _detailReturnIndex = _index.clamp(0, 4);
      _index = index;
      _openedPages.add(index);
      if (index == 0) _dashboardRefreshToken++;
      if (index == 3) _growthRefreshToken++;
      if (index == 5) {
        _calendarRefreshToken++;
      }
    });
  }

  void _scheduleDayChange() {
    _dayTimer?.cancel();
    final now = _now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _dayTimer = Timer(nextDay.difference(now), _refreshDay);
  }

  void _refreshDay() {
    final today = dateOnly(_now());
    if (mounted && dateKey(today) != dateKey(_day)) {
      setState(() => _day = today);
    }
    _scheduleDayChange();
  }

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final destinations = const [
      NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'আজ'),
      NavigationDestination(
        icon: Icon(Icons.check_circle_outline),
        selectedIcon: Icon(Icons.check_circle),
        label: 'কাজ',
      ),
      NavigationDestination(
          icon: Icon(Icons.mosque_outlined),
          selectedIcon: Icon(Icons.mosque),
          label: 'নামাজ'),
      NavigationDestination(icon: Icon(Icons.trending_up), label: 'গ্রোথ'),
      NavigationDestination(
        icon: Icon(Icons.more_horiz),
        label: 'আরও',
      ),
    ];

    final pages = [
      DashboardPage(
        key: ValueKey('dashboard-${dateKey(_day)}'),
        repository: widget.repository,
        day: _day,
        refreshToken: _dashboardRefreshToken,
        onOpenTasks: () => _selectPage(1),
        onOpenPrayer: () => _selectPage(2),
        onOpenGrowth: () => _selectPage(3),
      ),
      TasksPage(
        key: ValueKey('tasks-${dateKey(_day)}'),
        repository: widget.repository,
        day: _day,
        active: _index == 1,
      ),
      PrayerPage(
        key: ValueKey('prayer-${dateKey(_day)}'),
        repository: widget.repository,
        day: _day,
      ),
      GrowthPage(
        key: ValueKey('growth-${dateKey(_day)}'),
        repository: widget.repository,
        day: _day,
        refreshToken: _growthRefreshToken,
        onOpenQuran: () => _selectPage(8),
        onOpenDhikr: () => _selectPage(9),
      ),
      MorePage(
        onOpenCalendar: () => _selectPage(5),
        onOpenQuran: () => _selectPage(8),
        onOpenDhikr: () => _selectPage(9),
        onOpenContacts: () => _selectPage(6),
        onOpenSettings: () => _selectPage(7),
      ),
      _openedPages.contains(5)
          ? CalendarPage(
              key: ValueKey('calendar-${dateKey(_day)}'),
              repository: widget.repository,
              today: _day,
              refreshToken: _calendarRefreshToken,
            )
          : const SizedBox.shrink(),
      ContactsPage(repository: widget.repository),
      SettingsPage(
        repository: widget.repository,
        user: widget.user,
        firebaseReady: widget.firebaseReady,
      ),
      _openedPages.contains(8)
          ? QuranPage(
              key: ValueKey('quran-${dateKey(_day)}'),
              repository: widget.repository,
              today: _day,
              active: _index == 8,
            )
          : const SizedBox.shrink(),
      _openedPages.contains(9)
          ? DhikrPage(
              key: const ValueKey('dhikr'),
              repository: widget.repository,
              today: _day,
              active: _index == 9,
            )
          : const SizedBox.shrink(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        return PopScope<void>(
          canPop: _index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              _selectPage(_index >= 5 ? _detailReturnIndex : 0);
            }
          },
          child: Scaffold(
            appBar: AppBar(
              excludeHeaderSemantics: true,
              leading: _index >= 5
                  ? IconButton(
                      tooltip: _detailReturnIndex == 3
                          ? 'গ্রোথ পৃষ্ঠায় ফিরুন'
                          : 'আরও পৃষ্ঠায় ফিরুন',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => _selectPage(_detailReturnIndex),
                    )
                  : null,
              title: const AppBrand(compact: true),
              actions: [
                if (!widget.firebaseReady)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: StatusBadge(
                      icon: Icons.info_outline,
                      label: constraints.maxWidth < 400
                          ? 'প্রিভিউ'
                          : 'Offline preview',
                    ),
                  ),
              ],
            ),
            body: Row(
              children: [
                if (wide)
                  _DesktopNavigation(
                      selectedIndex: _index.clamp(0, 4),
                      onSelected: _selectPage,
                      extended: constraints.maxWidth >= 1100,
                      destinations: destinations),
                if (wide) const VerticalDivider(width: 1),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: List.generate(
                      pages.length,
                      (index) => TickerMode(
                        enabled: index == _index,
                        child: HeroMode(
                          enabled: index == _index,
                          child: _openedPages.contains(index)
                              ? pages[index]
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : DecoratedBox(
                    decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant))),
                    child: NavigationBar(
                      height: MediaQuery.textScalerOf(context).scale(14) > 20
                          ? 96
                          : 80,
                      selectedIndex: _index.clamp(0, 4),
                      onDestinationSelected: _selectPage,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      destinations: destinations,
                    )),
          ),
        );
      },
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation(
      {required this.selectedIndex,
      required this.onSelected,
      required this.extended,
      required this.destinations});
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool extended;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: extended ? 224 : 96,
        child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
                  child: SizedBox(
                    height: constraints.maxHeight < 460
                        ? 460
                        : constraints.maxHeight,
                    child: extended
                        ? NavigationDrawer(
                            backgroundColor: Colors.white,
                            surfaceTintColor: Colors.transparent,
                            elevation: 0,
                            selectedIndex: selectedIndex,
                            onDestinationSelected: onSelected,
                            indicatorColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            indicatorShape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            children: [
                              Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(28, 24, 20, 16),
                                  child: Text('প্রতিদিনের হিসাব',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant))),
                              ...destinations.map((destination) =>
                                  NavigationDrawerDestination(
                                      icon: destination.icon,
                                      selectedIcon: destination.selectedIcon,
                                      label: Text(destination.label))),
                            ],
                          )
                        : NavigationRail(
                            extended: extended,
                            minWidth: 96,
                            minExtendedWidth: 224,
                            selectedIndex: selectedIndex,
                            onDestinationSelected: onSelected,
                            labelType: extended
                                ? NavigationRailLabelType.none
                                : NavigationRailLabelType.all,
                            leading: const SizedBox(height: 24),
                            groupAlignment: -1,
                            destinations: destinations
                                .map((destination) => NavigationRailDestination(
                                    icon: destination.icon,
                                    selectedIcon: destination.selectedIcon,
                                    label: Text(destination.label)))
                                .toList(),
                          ),
                  ),
                )),
      );
}
