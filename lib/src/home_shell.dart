import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_repository.dart';
import 'pages/contacts_page.dart';
import 'pages/growth_page.dart';
import 'pages/prayer_page.dart';
import 'pages/settings_page.dart';
import 'pages/tasks_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.firebaseReady,
    required this.repository,
    required this.user,
  });

  final bool firebaseReady;
  final AppRepository repository;
  final User? user;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final destinations = const [
      NavigationDestination(
          icon: Icon(Icons.check_circle_outline), label: 'কাজ'),
      NavigationDestination(icon: Icon(Icons.mosque_outlined), label: 'নামাজ'),
      NavigationDestination(icon: Icon(Icons.trending_up), label: 'গ্রোথ'),
      NavigationDestination(
          icon: Icon(Icons.contacts_outlined), label: 'যোগাযোগ'),
      NavigationDestination(
          icon: Icon(Icons.settings_outlined), label: 'সেটিংস'),
    ];

    final pages = [
      TasksPage(repository: widget.repository),
      PrayerPage(repository: widget.repository),
      GrowthPage(repository: widget.repository),
      ContactsPage(repository: widget.repository),
      SettingsPage(
        repository: widget.repository,
        user: widget.user,
        firebaseReady: widget.firebaseReady,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Ummah Assist'),
            actions: [
              if (!widget.firebaseReady)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Chip(
                    avatar: const Icon(Icons.info_outline, size: 18),
                    label: const Text('Offline preview'),
                    side: BorderSide.none,
                    backgroundColor: Colors.amber.shade100,
                  ),
                ),
            ],
          ),
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (value) =>
                      setState(() => _index = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: destinations
                      .map(
                        (destination) => NavigationRailDestination(
                          icon: destination.icon,
                          label: Text(destination.label),
                        ),
                      )
                      .toList(),
                ),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: pages,
                ),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (value) =>
                      setState(() => _index = value),
                  destinations: destinations,
                ),
        );
      },
    );
  }
}
