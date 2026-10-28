import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app_repository.dart';
import '../display_formatters.dart';
import '../app_theme.dart';
import '../date_helpers.dart';
import '../models.dart';
import '../prayer_alerts.dart';
import '../prayer_times_service.dart';
import '../reminder_service.dart';
import '../widgets/page_frame.dart';
import '../widgets/load_failure_state.dart';
import 'prayer_alert_card.dart';
import 'prayer_time_settings_sheet.dart';
import 'qaza_page.dart';

class PrayerPage extends StatefulWidget {
  const PrayerPage({
    super.key,
    required this.repository,
    required this.day,
    this.active = true,
    this.historical = false,
    this.onSaved,
    this.onSaveError,
  });

  final AppRepository repository;
  final DateTime day;
  final bool active;
  final bool historical;
  final VoidCallback? onSaved;
  final ValueChanged<String>? onSaveError;

  @override
  State<PrayerPage> createState() => _PrayerPageState();
}

class _PrayerPageState extends State<PrayerPage> with WidgetsBindingObserver {
  Map<String, PrayerStatus> _prayers = defaultPrayerMap();
  Map<String, PrayerStatus> _confirmedPrayers = defaultPrayerMap();
  bool _loading = true;
  bool _hasLoaded = false;
  bool _loadFailed = false;
  bool _refreshing = false;
  bool _refreshFailed = false;
  int _pendingSaves = 0;
  bool _openingQaza = false;
  PrayerTimeConfig? _timeConfig;
  PrayerSchedule? _schedule;
  Timer? _scheduleTimer;
  PrayerAlertSettings _alertSettings = PrayerAlertSettings();
  bool _alertBusy = false;
  bool _alertsLoaded = false;
  bool _alertPermissionGranted = true;
  bool _alertExact = true;
  int _scheduledAlertCount = 0;
  Future<void> _writeQueue = Future<void>.value();
  int _statusRequestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant PrayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contextChanged = oldWidget.repository.uid != widget.repository.uid ||
        dateKey(oldWidget.day) != dateKey(widget.day) ||
        oldWidget.historical != widget.historical;
    if (contextChanged) {
      _hasLoaded = false;
      _writeQueue = Future<void>.value();
      _prayers = defaultPrayerMap();
      _confirmedPrayers = defaultPrayerMap();
      _pendingSaves = 0;
      _scheduleTimer?.cancel();
      _timeConfig = null;
      _schedule = null;
      _alertSettings = PrayerAlertSettings();
      _alertsLoaded = false;
      _load();
    } else if (!identical(oldWidget.repository, widget.repository)) {
      _load();
    } else if (!oldWidget.active &&
        widget.active &&
        widget.repository.canSync) {
      _refreshPrayerStatuses();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduleTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.active &&
        widget.repository.canSync) {
      unawaited(_refreshPrayerStatuses());
    }
    if (!widget.historical &&
        state == AppLifecycleState.resumed &&
        _timeConfig != null) {
      setState(() => _updateSchedule(_timeConfig!));
      unawaited(_refreshPrayerAlerts());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed) {
      return LoadFailureState(
          title: 'নামাজের হিসাব লোড করা যায়নি', onRetry: _load);
    }

    final summary = PrayerSummary.fromStatuses(_prayers.values);

    return RefreshIndicator(
      onRefresh: _refreshPrayerStatuses,
      child: PageFrame(
        title: widget.historical ? 'নামাজের হিসাব' : 'নামাজ ট্র্যাকিং',
        subtitle: widget.historical
            ? '${compactDateLabel(widget.day)} দিনের হিসাব সংশোধন করুন'
            : 'আজকের পাঁচ ওয়াক্ত নামাজ ও জামাতে পড়া ট্র্যাক করুন',
        children: [
          if (_refreshing) const LinearProgressIndicator(),
          if (_pendingSaves > 0)
            Semantics(
              liveRegion: true,
              child: const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('নামাজের হিসাব সংরক্ষণ হচ্ছে…'),
              ),
            ),
          if (_refreshFailed)
            Card(
              child: ListTile(
                leading: const Icon(Icons.sync_problem_outlined),
                title: const Text('সর্বশেষ নামাজের হিসাব আনা যায়নি'),
                trailing: TextButton(
                  onPressed: _refreshPrayerStatuses,
                  child: const Text('রিট্রাই'),
                ),
              ),
            ),
          if (!widget.historical) ...[
            _PrayerTimesCard(
              config: _timeConfig,
              schedule: _schedule,
              onConfigure: _configurePrayerTimes,
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  _StatTile(
                    label: 'পড়া',
                    value: summary.prayed,
                    color: AppColors.success,
                  ),
                  _StatTile(
                      label: 'মিস',
                      value: summary.missed,
                      color: AppColors.danger),
                  _StatTile(
                      label: 'কাযা',
                      value: summary.madeUp,
                      color: AppColors.information),
                  _StatTile(
                    label: 'হিসাব নেই',
                    value: summary.unlogged,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
          if (summary.jamaat > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  '${banglaNumber(summary.jamaat)} ওয়াক্ত জামাতে পড়া হয়েছে'),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.historical ? 'এই দিনের নামাজ' : 'আজকের নামাজ',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  ...prayerKeys.map((key) {
                    final status = _prayers[key] ??
                        const PrayerStatus(state: PrayerState.unlogged);
                    return _PrayerTile(
                      prayerKey: key,
                      label: prayerLabels[key] ?? key,
                      status: status,
                      onStateChanged: (state) =>
                          _updatePrayer(key, status.copyWith(state: state)),
                      onJamaatChanged: status.prayed
                          ? (value) =>
                              _updatePrayer(key, status.copyWith(jamaat: value))
                          : null,
                    );
                  }),
                ],
              ),
            ),
          ),
          if (!widget.historical) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text('সব দিনের কাযা'),
                subtitle: const Text('মিসড নামাজ দেখুন ও কাযা সম্পন্ন করুন'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openingQaza ? null : _openQazaBacklog,
              ),
            ),
          ],
          if (!widget.historical && ReminderService.supported) ...[
            const SizedBox(height: 16),
            PrayerAlertCard(
              settings: _alertSettings,
              locationReady: _timeConfig != null,
              busy: _alertBusy || !_alertsLoaded,
              permissionGranted: _alertPermissionGranted,
              exact: _alertExact,
              scheduledCount: _scheduledAlertCount,
              onChanged: (next, requestPermission) => _changeAlertSettings(
                next,
                requestPermission: requestPermission,
              ),
              onConfigureLocation: _configurePrayerTimes,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _load() async {
    final requestId = ++_statusRequestId;
    final repository = widget.repository;
    final day = dateKey(widget.day);
    setState(() {
      _loading = true;
      _loadFailed = false;
      _refreshing = false;
      _refreshFailed = false;
    });
    if (!widget.historical) {
      try {
        final config = await PrayerTimeStore(repository.uid).load();
        if (!mounted || requestId != _statusRequestId) return;
        if (config != null) {
          _timeConfig = config;
          _updateSchedule(config);
        }
      } catch (_) {
        _showMessage('নামাজের সময় লোড করতে সমস্যা হয়েছে');
      }
      if (ReminderService.supported &&
          mounted &&
          requestId == _statusRequestId) {
        unawaited(_loadAlertSettings());
      }
    }
    try {
      await _writeQueue;
      if (!mounted || requestId != _statusRequestId) return;
      final todayDoc = await repository.loadPrayerDocument(day);
      if (!mounted ||
          requestId != _statusRequestId ||
          !identical(repository, widget.repository) ||
          day != dateKey(widget.day)) {
        return;
      }
      _prayers = prayerStatusesFromDocument(todayDoc);
      _confirmedPrayers = Map<String, PrayerStatus>.of(_prayers);
      _hasLoaded = true;
    } catch (_) {
      if (!mounted || requestId != _statusRequestId) return;
      _loadFailed = true;
    } finally {
      if (mounted && requestId == _statusRequestId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshPrayerStatuses() async {
    if (!widget.repository.canSync) return;
    if (!_hasLoaded) {
      await _load();
      return;
    }
    final requestId = ++_statusRequestId;
    final repository = widget.repository;
    final day = dateKey(widget.day);
    setState(() {
      _refreshing = true;
      _refreshFailed = false;
    });
    try {
      await _writeQueue;
      if (!mounted || requestId != _statusRequestId) return;
      final document = await repository.loadPrayerDocument(day);
      if (!mounted ||
          requestId != _statusRequestId ||
          !identical(repository, widget.repository) ||
          day != dateKey(widget.day)) {
        return;
      }
      setState(() {
        _prayers = prayerStatusesFromDocument(document);
        _confirmedPrayers = Map<String, PrayerStatus>.of(_prayers);
      });
    } catch (_) {
      if (mounted && requestId == _statusRequestId) {
        setState(() => _refreshFailed = true);
      }
    } finally {
      if (mounted && requestId == _statusRequestId) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _loadAlertSettings() async {
    try {
      final settings = await PrayerAlertStore(widget.repository.uid).load();
      if (!mounted) return;
      setState(() => _alertSettings = settings);
      await _refreshPrayerAlerts();
    } catch (_) {
      _showMessage('নামাজের অ্যালার্ট লোড করতে সমস্যা হয়েছে');
    } finally {
      if (mounted) setState(() => _alertsLoaded = true);
    }
  }

  Future<void> _configurePrayerTimes() async {
    final config = await showModalBottomSheet<PrayerTimeConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PrayerTimeSettingsSheet(initial: _timeConfig),
    );
    if (config == null || !mounted) return;
    try {
      PrayerTimeService.forDay(config, widget.day);
      await PrayerTimeStore(widget.repository.uid).save(config);
      if (mounted) {
        setState(() {
          _timeConfig = config;
          _updateSchedule(config);
        });
        await _refreshPrayerAlerts();
      }
    } catch (_) {
      _showMessage('নামাজের সময় সংরক্ষণ করা যায়নি');
    }
  }

  Future<void> _refreshPrayerAlerts() async {
    if (!ReminderService.supported || _alertBusy) return;
    try {
      final result = await ReminderService.instance.syncPrayerAlerts(
        config: _timeConfig,
        settings: _alertSettings,
      );
      if (!mounted) return;
      setState(() {
        _alertPermissionGranted = result.permissionGranted;
        _alertExact = result.exact;
        _scheduledAlertCount = result.scheduledCount;
      });
    } catch (_) {
      _showMessage('নামাজের অ্যালার্ট আপডেট করা যায়নি');
    }
  }

  Future<void> _changeAlertSettings(
    PrayerAlertSettings next, {
    required bool requestPermission,
  }) async {
    if (_alertBusy || !_alertsLoaded) return;
    setState(() => _alertBusy = true);
    try {
      final result = await ReminderService.instance.syncPrayerAlerts(
        config: _timeConfig,
        settings: next,
        requestPermission: requestPermission,
      );
      if (!result.permissionGranted && next.enabled) {
        _showMessage('অ্যালার্ট চালু করতে নোটিফিকেশন অনুমতি দিন।');
        return;
      }
      await PrayerAlertStore(widget.repository.uid).save(next);
      if (!mounted) return;
      setState(() {
        _alertSettings = next;
        _alertPermissionGranted = result.permissionGranted;
        _alertExact = result.exact;
        _scheduledAlertCount = result.scheduledCount;
      });
    } catch (_) {
      try {
        await ReminderService.instance.syncPrayerAlerts(
          config: _timeConfig,
          settings: _alertSettings,
        );
      } catch (_) {
        // The next app launch will retry the persisted settings.
      }
      _showMessage('নামাজের অ্যালার্ট সংরক্ষণ করা যায়নি');
    } finally {
      if (mounted) setState(() => _alertBusy = false);
    }
  }

  void _updateSchedule(PrayerTimeConfig config) {
    final zone = PrayerTimeService.location(config.timeZoneId);
    final now = tz.TZDateTime.from(DateTime.now(), zone);
    _schedule = PrayerTimeService.forDay(config, now);
    _scheduleTimer?.cancel();
    final midnight = tz.TZDateTime(zone, now.year, now.month, now.day + 1);
    final delay =
        midnight.difference(DateTime.now()) + const Duration(seconds: 1);
    if (delay > Duration.zero) {
      _scheduleTimer = Timer(delay, () {
        if (mounted) setState(() => _updateSchedule(config));
      });
    }
  }

  Future<void> _updatePrayer(String key, PrayerStatus status) async {
    final repository = widget.repository;
    final day = dateKey(widget.day);
    final onSaved = widget.onSaved;
    final onSaveError = widget.onSaveError;
    ++_statusRequestId;
    setState(() {
      _prayers[key] = status;
      _pendingSaves++;
      _refreshing = false;
      _refreshFailed = false;
    });
    final operation = _writeQueue.then((_) => repository.savePrayerStatus(
          date: day,
          prayerKey: key,
          status: status,
        ));
    _writeQueue = operation.then((_) {
      if (mounted &&
          identical(repository, widget.repository) &&
          day == dateKey(widget.day)) {
        _confirmedPrayers[key] = status;
        setState(() => _pendingSaves--);
      }
      onSaved?.call();
    }).catchError((Object _) {
      final current = mounted &&
          identical(repository, widget.repository) &&
          day == dateKey(widget.day);
      if (current) {
        setState(() {
          _pendingSaves--;
          if (identical(_prayers[key], status)) {
            _prayers[key] = _confirmedPrayers[key]!;
          }
        });
      }
      const message = 'নামাজের ডেটা সিঙ্ক করতে সমস্যা হয়েছে';
      if (onSaveError != null) {
        onSaveError(message);
      } else if (current) {
        _showMessage(message);
      }
    });
    await _writeQueue;
  }

  Future<void> _openQazaBacklog() async {
    if (_openingQaza) return;
    setState(() => _openingQaza = true);
    try {
      await _writeQueue;
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('নামাজ')),
            body: QazaPage(repository: widget.repository),
          ),
        ),
      );
      if (!mounted) return;
      final requestId = ++_statusRequestId;
      setState(() {
        _refreshing = false;
        _refreshFailed = false;
      });
      final repository = widget.repository;
      final day = dateKey(widget.day);
      final document = await repository.loadPrayerDocument(day);
      if (!mounted) return;
      if (requestId != _statusRequestId ||
          !identical(repository, widget.repository) ||
          day != dateKey(widget.day)) {
        return;
      }
      setState(() {
        _prayers = prayerStatusesFromDocument(document);
        _confirmedPrayers = Map<String, PrayerStatus>.of(_prayers);
      });
    } catch (_) {
      _showMessage('নামাজের হিসাব রিফ্রেশ করা যায়নি');
    } finally {
      if (mounted) setState(() => _openingQaza = false);
    }
  }

  void _showMessage(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    });
  }
}

class _PrayerTimesCard extends StatelessWidget {
  const _PrayerTimesCard({
    required this.config,
    required this.schedule,
    required this.onConfigure,
  });

  final PrayerTimeConfig? config;
  final PrayerSchedule? schedule;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'নামাজের সময়',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: onConfigure,
                  child: Text(config == null ? 'সেট করুন' : 'পরিবর্তন'),
                ),
              ],
            ),
            if (config == null || schedule == null)
              const Text(
                  'স্থান নির্বাচন করলে আপনার এলাকার সময় এখানে দেখা যাবে।')
            else ...[
              Text(
                '${config!.placeName} • ${prayerCalculationMethods[config!.method]} • '
                '${compactDateLabel(schedule!.entries.first.time)}',
              ),
              const SizedBox(height: 8),
              for (final entry in schedule!.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(prayerLabels[entry.key] ?? entry.key)),
                      Text(
                        formatPrayerTime(entry.time),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'সময় অঞ্চল: ${config!.timeZoneId} • স্থানীয় মসজিদের সময় যাচাই করুন',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            banglaNumber(value),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _PrayerTile extends StatelessWidget {
  const _PrayerTile({
    required this.prayerKey,
    required this.label,
    required this.status,
    required this.onStateChanged,
    required this.onJamaatChanged,
  });

  final String prayerKey;
  final String label;
  final PrayerStatus status;
  final ValueChanged<PrayerState> onStateChanged;
  final ValueChanged<bool>? onJamaatChanged;

  @override
  Widget build(BuildContext context) {
    final color = switch (status.state) {
      PrayerState.prayed => AppColors.success,
      PrayerState.missed => AppColors.danger,
      PrayerState.madeUp => AppColors.information,
      PrayerState.unlogged => AppColors.muted,
    };
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 600 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final selector = SizedBox(
          width: 150,
          child: Semantics(
            label: '$label: নামাজের অবস্থা',
            child: DropdownButton<PrayerState>(
              key: ValueKey('prayer_state_$prayerKey'),
              isExpanded: true,
              value: status.state,
              onChanged: (value) {
                if (value != null && value != status.state) {
                  onStateChanged(value);
                }
              },
              items: [
                for (final state in PrayerState.values)
                  DropdownMenuItem(
                      value: state, child: Text(prayerStateLabels[state]!))
              ],
            ),
          ));
      final heading = Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
        selector,
        if (!compact) ...[
          const SizedBox(width: 24),
          SizedBox(
              width: 128,
              child: status.prayed
                  ? Row(children: [
                      Semantics(
                          label: '$label জামাতে পড়া হয়েছে',
                          child: Switch(
                              value: status.jamaat,
                              onChanged: onJamaatChanged)),
                      const SizedBox(width: 6),
                      const Flexible(child: Text('জামাত')),
                    ])
                  : const SizedBox.shrink()),
        ],
      ]);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Material(
          color: Theme.of(context)
              .colorScheme
              .secondaryContainer
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                heading,
                if (compact && status.prayed)
                  Semantics(
                      label: label,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('জামাতে পড়া হয়েছে'),
                        value: status.jamaat,
                        onChanged: onJamaatChanged,
                      )),
              ],
            ),
          ),
        ),
      );
    });
  }
}
