import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/records.dart';
import 'productivity_database.dart';
import 'productivity_remote.dart';

/// Own one coordinator per signed-in database. Its stop method invalidates
/// in-flight responses before account-scoped state can be disposed or reused.
class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator(
      {required this.database,
      required this.remote,
      this.requestTimeout = const Duration(seconds: 20),
      this.interval = const Duration(seconds: 30)});
  final ProductivityDatabase database;
  final ProductivityRemote remote;
  final Duration interval;
  final Duration requestTimeout;
  Timer? _timer, _debounce;
  StreamSubscription<SyncSnapshot>? _subscription;
  Future<void>? _running;
  bool _stopped = false, _active = false;
  int _observedPending = 0;
  bool _resyncRequested = false;
  int _generation = 0;
  bool busy = false;
  String? errorCode;

  void start() {
    if (_stopped || _active) return;
    _active = true;
    _subscription = database.watchSync().listen((state) {
      final added = state.pending > _observedPending;
      _observedPending = state.pending;
      if (_stopped || !_active || !added) return;
      if (busy) {
        _resyncRequested = true;
        return;
      }
      _debounce?.cancel();
      _debounce =
          Timer(const Duration(milliseconds: 400), () => unawaited(sync()));
    }, onError: (Object _) {
      if (!_stopped) {
        errorCode = 'local-storage';
        notifyListeners();
      }
    });
    _timer = Timer.periodic(interval, (_) => unawaited(sync()));
    unawaited(sync());
  }

  void setActive(bool active) {
    if (_stopped || _active == active) return;
    if (active) {
      _active = false;
      start();
    } else {
      _active = false;
      _generation++;
      _timer?.cancel();
      _debounce?.cancel();
      unawaited(_subscription?.cancel());
      _subscription = null;
    }
  }

  Future<void> sync({bool force = false}) {
    if (_stopped) return Future.value();
    return _running ??= _sync(force: force).whenComplete(() => _running = null);
  }

  Future<void> _sync({required bool force}) async {
    final generation = _generation;
    bool current() => !_stopped && generation == _generation;
    busy = true;
    errorCode = null;
    notifyListeners();
    try {
      if (await database.frozen || !current()) return;
      // Bounded batches yield to later timer cycles instead of monopolizing the
      // foreground when a device reconnects with a very large pending queue.
      for (var batch = 0; batch < 4 && current(); batch++) {
        final pending = await database.pending(includeDelayed: force);
        if (pending.isEmpty) break;
        for (final operation in pending) {
          if (!current()) return;
          try {
            final acknowledgement =
                await remote.apply(operation).timeout(requestTimeout);
            if (!current()) return;
            await database.acknowledge(operation, acknowledgement.record,
                rejectedFields: acknowledgement.rejectedFields);
          } catch (error) {
            if (!current()) return;
            final failure = _failure(error);
            errorCode = failure.code;
            await database.recordFailure(operation, failure.code,
                permanent: failure.permanent);
            if (failure.code == 'account-deleting') await database.freeze();
            // Stop a failed network/auth batch rather than making one request
            // for each remaining operation against an unavailable backend.
            return;
          }
        }
      }
      var cursor = await database.cursor;
      for (var batch = 0; batch < 10 && current(); batch++) {
        final page = await remote.pull(cursor).timeout(requestTimeout);
        if (!current()) return;
        await database.acceptPage(page.records, page.cursor);
        cursor = page.cursor;
        if (!page.hasMore) break;
      }
      if (current()) await database.recordSyncSuccess();
    } catch (error) {
      if (current()) errorCode = _failure(error).code;
    } finally {
      if (!_stopped) {
        busy = false;
        notifyListeners();
        final resync = _active &&
            ((_resyncRequested && errorCode == null) ||
                generation != _generation);
        _resyncRequested = false;
        if (resync) {
          _debounce?.cancel();
          _debounce =
              Timer(const Duration(milliseconds: 400), () => unawaited(sync()));
        }
      }
    }
  }

  SyncFailure _failure(Object error) {
    if (error is SyncFailure) return error;
    if (error is FirebaseException) {
      final permanent = [
        'permission-denied',
        'unauthenticated',
        'invalid-argument',
        'failed-precondition'
      ].contains(error.code);
      return SyncFailure(error.code, permanent: permanent);
    }
    if (error is FormatException || error is ArgumentError) {
      return const SyncFailure('invalid-data', permanent: true);
    }
    return const SyncFailure('unavailable');
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _active = false;
    _generation++;
    _timer?.cancel();
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  Future<void> drain() async {
    await _running;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
