import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../app_identity.dart';
import '../../app_localization.dart';
import '../../app_theme.dart';
import '../../widgets/app_brand.dart';
import '../core/records.dart';
import '../data/experience_repository.dart';
import '../data/legacy_task_migration.dart';
import '../data/productivity_database.dart';
import '../data/productivity_remote.dart';
import '../data/productivity_session.dart';
import '../data/task_repository.dart';
import '../data/workspace_backup.dart';
import '../domain/experience_options.dart';
import 'experience_strings.dart';
import 'onboarding_page.dart';
import 'productivity_settings_page.dart';
import 'task_workspace_page.dart';

/// The universal root is enabled only after route cutover and deployment gates
/// pass. Keeping the legacy entry untouched prevents a half-migrated account.
class ProductivityRoot extends StatefulWidget {
  const ProductivityRoot(
      {super.key,
      required this.uid,
      required this.faithBuilder,
      required this.accountBuilder,
      this.remote,
      this.prepareLegacyMigration,
      this.openDatabase,
      this.detectTimeZone,
      this.initialLanguage = 'bn'});
  final String uid, initialLanguage;
  final ProductivityRemote? remote;
  final Future<LegacyTaskMigration> Function()? prepareLegacyMigration;
  final Future<ProductivityDatabase> Function()? openDatabase;
  final Future<String> Function()? detectTimeZone;
  final WidgetBuilder faithBuilder, accountBuilder;
  @override
  State<ProductivityRoot> createState() => _ProductivityRootState();
}

class _ProductivityRootState extends State<ProductivityRoot>
    with WidgetsBindingObserver {
  late Future<ProductivitySession> _opening;
  ProductivitySession? _session;
  bool _disposed = false;
  int _epoch = 0;
  String _zone = 'UTC';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _opening = _open();
  }

  Future<ProductivitySession> _open() async {
    final epoch = ++_epoch;
    final uid = widget.uid,
        remote = widget.remote,
        opener = widget.openDatabase;
    final prepare = widget.prepareLegacyMigration,
        detector = widget.detectTimeZone;
    bool current() => !_disposed && epoch == _epoch;
    final session = await ProductivitySession.open(
        uid: uid, remote: remote, openDatabase: opener);
    try {
      if (!current()) throw StateError('Workspace session ended.');
      _session = session;
      var zone = 'UTC';
      try {
        zone = await (detector?.call() ??
            FlutterTimezone.getLocalTimezone()
                .then((value) => value.identifier));
      } catch (_) {
        zone = 'UTC';
      }
      if (!current()) throw StateError('Workspace session ended.');
      _zone = zone;
      if (await session.database.frozen) {
        throw StateError('Account deletion is pending.');
      }
      if (prepare != null &&
          await session.database.get(
                  RecordKind.workspace, LegacyTaskMigration.checkpointId) ==
              null) {
        if (!current()) throw StateError('Workspace session ended.');
        await (await prepare()).apply(session.database);
      }
      if (!current()) throw StateError('Workspace session ended.');
      session.sync?.start();
      return session;
    } catch (_) {
      await session.close();
      if (identical(_session, session)) _session = null;
      rethrow;
    }
  }

  @override
  void didUpdateWidget(ProductivityRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid == widget.uid) return;
    final epoch = ++_epoch;
    final previous = _session;
    _session = null;
    _opening = () async {
      await previous?.close();
      if (_disposed || epoch != _epoch) {
        throw StateError('Workspace session ended.');
      }
      return _open();
    }();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _session?.sync?.setActive(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final session = _session;
    if (session != null) {
      unawaited(session.close().catchError((Object _) {
        FlutterError.reportError(FlutterErrorDetails(
            exception: StateError('Workspace storage cleanup failed.'),
            library: 'workspace lifecycle'));
      }));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ProductivitySession>(
      future: _opening,
      builder: (context, snapshot) {
        final strings = ExperienceStrings(widget.initialLanguage);
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
              body: SafeArea(
                  child: Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.storage_outlined, size: 48),
                            const SizedBox(height: 16),
                            Text(
                                strings.text(
                                    'Could not prepare your workspace.',
                                    'আপনার কর্মপরিসর তৈরি করা যায়নি।'),
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Text(
                                strings.text(
                                    'Your saved data is kept. Connect to the internet for the first migration, then try again.',
                                    'সংরক্ষিত তথ্য রাখা আছে। প্রথমবার তথ্য আনার জন্য ইন্টারনেটে যুক্ত হয়ে আবার চেষ্টা করুন।'),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton(
                                onPressed: () =>
                                    setState(() => _opening = _open()),
                                child: Text(strings.text(
                                    'Try again', 'আবার চেষ্টা করুন'))),
                            TextButton(
                                onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                        builder: widget.accountBuilder)),
                                child: Text(strings.text('Account and privacy',
                                    'অ্যাকাউন্ট ও গোপনীয়তা'))),
                          ])))));
        }
        final session = snapshot.data;
        if (session == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return _Experience(
            session: session,
            zone: _zone,
            initialLanguage: widget.initialLanguage,
            faithBuilder: widget.faithBuilder,
            accountBuilder: widget.accountBuilder);
      });
}

class _Experience extends StatefulWidget {
  const _Experience(
      {required this.session,
      required this.zone,
      required this.initialLanguage,
      required this.faithBuilder,
      required this.accountBuilder});
  final ProductivitySession session;
  final String zone, initialLanguage;
  final WidgetBuilder faithBuilder, accountBuilder;
  @override
  State<_Experience> createState() => _ExperienceState();
}

class _ExperienceState extends State<_Experience> {
  late final _repository = ExperienceRepository(widget.session.database);
  late final _options = _repository.watchOptions();
  @override
  Widget build(BuildContext context) => StreamBuilder<ExperienceOptions?>(
      stream: _options,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
              body: Center(
                  child: Text(ExperienceStrings(widget.initialLanguage).text(
                      'Could not load preferences. Your workspace data is kept.',
                      'পছন্দগুলো খোলা যায়নি। কর্মপরিসরের তথ্য রাখা আছে।'))));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final options = snapshot.data;
        final language = options?.language ?? widget.initialLanguage;
        final dark = ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            colorSchemeSeed: AppColors.brand,
            fontFamily: 'AnekBangla');
        return MaterialApp(
            title: AppIdentity.name,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: dark,
            themeMode: switch (options?.theme ?? ExperienceTheme.system) {
              ExperienceTheme.system => ThemeMode.system,
              ExperienceTheme.light => ThemeMode.light,
              ExperienceTheme.dark => ThemeMode.dark,
            },
            locale: Locale(language),
            supportedLocales: AppLocalization.supportedLocales,
            localizationsDelegates: AppLocalization.delegates,
            home: options == null || !options.completedOnboarding
                ? ProductivityOnboardingPage(
                    timeZone: widget.zone,
                    initialLanguage: language,
                    onComplete: _repository.completeOnboarding)
                : _WorkspaceHome(
                    session: widget.session,
                    options: options,
                    repository: _repository,
                    faithBuilder: widget.faithBuilder,
                    accountBuilder: widget.accountBuilder));
      });
}

class _WorkspaceHome extends StatefulWidget {
  const _WorkspaceHome(
      {required this.session,
      required this.options,
      required this.repository,
      required this.faithBuilder,
      required this.accountBuilder});
  final ProductivitySession session;
  final ExperienceOptions options;
  final ExperienceRepository repository;
  final WidgetBuilder faithBuilder, accountBuilder;
  @override
  State<_WorkspaceHome> createState() => _WorkspaceHomeState();
}

class _WorkspaceHomeState extends State<_WorkspaceHome> {
  String _page = 'tasks';
  late final _tasks = TaskRepository(widget.session.database);
  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final strings = ExperienceStrings(options.language);
    final pages = ['tasks', if (options.faithEnabled) 'faith', 'settings'];
    final page = pages.contains(_page) ? _page : 'tasks';
    return Scaffold(
      appBar: page == 'settings'
          ? null
          : AppBar(title: const AppBrand(compact: true), actions: [
              if (widget.session.sync != null)
                IconButton(
                    tooltip:
                        strings.text('Sync workspace', 'কর্মপরিসর সিঙ্ক করুন'),
                    onPressed: () => widget.session.sync!.sync(force: true),
                    icon: const Icon(Icons.sync))
            ]),
      body: switch (page) {
        'settings' => ProductivitySettingsPage(
            repository: widget.repository,
            options: options,
            backup: WorkspaceBackup(widget.session.database),
            onOpenAccount: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: widget.accountBuilder))),
        'faith' => widget.faithBuilder(context),
        _ => Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: MergeSemantics(
                    child: DropdownButtonFormField<String>(
                        initialValue: options.activeWorkspace,
                        isExpanded: true,
                        decoration: InputDecoration(
                            labelText: strings.text('Workspace', 'কর্মপরিসর')),
                        items: [
                          for (final module in options.modules)
                            if (module != WorkspaceModule.faith)
                              DropdownMenuItem(
                                  value: module.name,
                                  child: Text(strings.module(module)))
                        ],
                        onChanged: (value) async {
                          if (value == null) return;
                          try {
                            await widget.repository
                                .updateOptions({'activeWorkspace': value});
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          strings.taskError('save-failed'))));
                            }
                          }
                        }))),
            Expanded(
                child: TaskWorkspacePage(
                    key: ValueKey(options.activeWorkspace),
                    repository: _tasks,
                    options: options,
                    workspaceId: options.activeWorkspace)),
          ]),
      },
      bottomNavigationBar: NavigationBar(
          selectedIndex: pages.indexOf(page),
          onDestinationSelected: (index) =>
              setState(() => _page = pages[index]),
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.checklist),
                label: strings.text('Tasks', 'কাজ')),
            if (options.faithEnabled)
              NavigationDestination(
                  icon: const Icon(Icons.mosque_outlined),
                  label: strings.text('Faith', 'আমল')),
            NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                label: strings.text('Settings', 'সেটিংস'))
          ]),
    );
  }
}
