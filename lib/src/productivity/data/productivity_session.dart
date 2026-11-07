import 'productivity_database.dart';
import 'productivity_remote.dart';
import 'sync_coordinator.dart';

/// Account lifecycle owner. A sign-out retains offline work; deletion freezes
/// writes before stopping sync and erases the file only after server deletion.
class ProductivitySession {
  ProductivitySession._(this.database, this.sync);
  final ProductivityDatabase database;
  final SyncCoordinator? sync;
  Future<void>? _closing;
  static final _active = <String, ProductivitySession>{};
  static final _opening = <String, Future<ProductivitySession>>{};

  static Future<ProductivitySession> open(
      {required String uid,
      ProductivityRemote? remote,
      Future<ProductivityDatabase> Function()? openDatabase}) async {
    final existing = _active[uid];
    if (existing != null) {
      if (existing._closing == null) {
        throw StateError('Account session is already open.');
      }
      await existing._closing;
    }
    if (_opening.containsKey(uid)) {
      throw StateError('Account session is already opening.');
    }
    final pending = () async {
      final database =
          await (openDatabase?.call() ?? ProductivityDatabase.open(uid: uid));
      if (database.uid != uid) {
        await database.close();
        throw StateError('Wrong account database.');
      }
      final session = ProductivitySession._(
          database,
          remote == null
              ? null
              : SyncCoordinator(database: database, remote: remote));
      _active[uid] = session;
      return session;
    }();
    _opening[uid] = pending;
    try {
      return await pending;
    } finally {
      _opening.remove(uid);
    }
  }

  static Future<void> freezeAccount(String uid) async {
    final opening = _opening[uid];
    if (opening != null) await opening;
    final session = _active[uid];
    if (session == null || session._closing != null) return;
    session.sync?.stop();
    await session.database.freeze();
    await session.sync?.drain();
  }

  static Future<void> closeAccount(String uid) async {
    final opening = _opening[uid];
    if (opening != null) await opening;
    await _active[uid]?.close();
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    sync?.stop();
    try {
      await sync?.drain();
      await database.close();
    } finally {
      sync?.dispose();
      if (identical(_active[database.uid], this)) _active.remove(database.uid);
    }
  }
}
