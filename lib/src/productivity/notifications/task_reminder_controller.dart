import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../reminder_service.dart';
import '../core/records.dart';
import '../data/productivity_database.dart';
import '../domain/experience_options.dart';
import '../domain/task_reminder_plan.dart';
import 'task_reminder_store.dart';

/// A foreground owner of the account's device notification plan. Native alarms
/// remain scheduled while paused; only foreground refilling uses Dart timers.
class TaskReminderController extends ChangeNotifier {
  TaskReminderController(
      {required this.database,
      required ExperienceOptions options,
      TaskReminderStore? store,
      ReminderService? service,
      DateTime Function()? clock})
      : _options = options,
        _store = store ?? TaskReminderStore(database.uid),
        _service = service ?? ReminderService.instance,
        _clock = clock ?? DateTime.now {
    if (_store.uid != database.uid) {
      throw StateError('Wrong notification settings account.');
    }
    _scope = _service.claimTaskReminderScope(database.uid);
    _service.taskDelivery.addListener(_deliveryChanged);
  }
  final ProductivityDatabase database;
  final TaskReminderStore _store;
  final ReminderService _service;
  final DateTime Function() _clock;
  late final int _scope;
  ExperienceOptions _options;
  StreamSubscription<List<WorkspaceRecord>>? _recordsSubscription;
  StreamSubscription<bool>? _freezeSubscription;
  List<WorkspaceRecord>? _records;
  Timer? _debounce, _wake;
  bool _started = false, _closed = false, _frozen = true, _active = true;
  int _request = 0;
  String? _fingerprint;
  Future<void>? _closing;

  bool ready = false, enabled = false, working = false;
  bool permissionDenied = false;
  String? error;
  TaskAlertScheduleResult? delivery;

  Future<void> start() async {
    if (_started || _closed) return;
    _started = true;
    try {
      final saved = await _store.load();
      if (_closed) return;
      enabled = saved;
      ready = true;
      error = null;
      _recordsSubscription = database
          .watchKinds({RecordKind.task, RecordKind.taskOccurrence}).listen(
              (records) {
        if (_closed) return;
        _records = records;
        _queue();
      }, onError: (Object _) => _fail('storage'));
      _freezeSubscription = database.watchFrozen().listen((frozen) {
        if (_closed) return;
        _frozen = frozen;
        _queue(force: true);
      }, onError: (Object _) => _fail('storage'));
      notifyListeners();
    } catch (_) {
      if (_closed) return;
      _fail('storage');
    }
  }

  void updateOptions(ExperienceOptions options) {
    _options = options;
    _queue();
  }

  void setActive(bool active) {
    if (_closed) return;
    _active = active;
    if (active) {
      unawaited(refresh());
    } else {
      _wake?.cancel();
    }
  }

  void _queue({bool force = false}) {
    if (_closed) return;
    _debounce?.cancel();
    if (!enabled || _frozen) {
      unawaited(_refresh(force: force));
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200),
        () => unawaited(_refresh(force: force)));
  }

  void _deliveryChanged() {
    final update = _service.taskDelivery.value;
    if (_closed || update == null || update.scope != _scope) return;
    delivery = update.result;
    if (enabled) permissionDenied = !update.result.permissionGranted;
    notifyListeners();
  }

  void _fail(String code) {
    if (_closed) return;
    _request++;
    error = code;
    _fingerprint = null;
    _wake?.cancel();
    if (code == 'storage') {
      _records = null;
      _frozen = true;
      ready = false;
      _started = false;
      unawaited(_recordsSubscription?.cancel());
      unawaited(_freezeSubscription?.cancel());
      _recordsSubscription = null;
      _freezeSubscription = null;
    }
    // Invalid local data must not leave an old, misleading native plan active.
    unawaited(
        _service.syncTaskAlerts(_scope, null).catchError((Object _) => null));
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!_started) await start();
    _debounce?.cancel();
    await _refresh(force: true);
  }

  Future<void> _refresh({required bool force}) async {
    if (_closed || !ready || _records == null) return;
    var request = _request;
    try {
      final now = _clock().toUtc();
      final plan = !enabled || _frozen
          ? null
          : planTaskReminders(
              uid: database.uid,
              records: _records!,
              options: _options,
              now: now);
      final signature = plan?.fingerprint ?? 'disabled';
      if (!force && _fingerprint == signature) return;
      request = ++_request;
      _fingerprint = signature;
      final result = await _service.syncTaskAlerts(_scope, plan);
      if (_closed || request != _request) return;
      delivery = result;
      if (enabled) permissionDenied = result?.permissionGranted == false;
      error = null;
      _wake?.cancel();
      if (_active &&
          result != null &&
          plan != null &&
          plan.reminders.isNotEmpty) {
        final next = plan.reminders.first.time.difference(now) +
            const Duration(seconds: 1);
        final interval = result.deferredCount > 0
            ? const Duration(minutes: 1)
            : const Duration(days: 1);
        final delay = next > interval ? interval : next;
        _wake = Timer(delay, () => unawaited(refresh()));
      }
      notifyListeners();
    } catch (_) {
      if (!_closed && request == _request) _fail('delivery');
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_closed || !ready || working) return;
    working = true;
    error = null;
    notifyListeners();
    try {
      if (value) {
        final allowed = await _service.requestTaskReminderPermission(_scope);
        if (_closed) return;
        if (!allowed) {
          permissionDenied = true;
          return;
        }
      }
      if (_closed) return;
      await _store.save(value);
      if (_closed) return;
      enabled = value;
      permissionDenied = false;
      await refresh();
    } catch (_) {
      if (!_closed) error = 'settings';
    } finally {
      if (!_closed) {
        working = false;
        notifyListeners();
      }
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _request++;
    _debounce?.cancel();
    _wake?.cancel();
    _service.taskDelivery.removeListener(_deliveryChanged);
    final releasing = _service.releaseTaskReminderScope(_scope);
    await _recordsSubscription?.cancel();
    await _freezeSubscription?.cancel();
    await releasing;
  }

  @override
  void dispose() {
    unawaited(close().catchError((Object _) {
      FlutterError.reportError(FlutterErrorDetails(
          exception: StateError('Task notification cleanup failed.'),
          library: 'workspace notifications'));
    }));
    super.dispose();
  }
}
