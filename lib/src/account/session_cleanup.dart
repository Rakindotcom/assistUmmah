/// Session termination is critical; optional native cleanup cannot veto it.
class SessionCleanup {
  const SessionCleanup({
    required this.endSession,
    required this.cancelReminders,
    required this.clearGoogleSession,
  });

  final Future<void> Function() endSession;
  final Future<void> Function() cancelReminders;
  final Future<void> Function() clearGoogleSession;

  Future<bool> signOut() async {
    await endSession();
    var cleanupComplete = true;
    for (final cleanup in [cancelReminders, clearGoogleSession]) {
      try {
        await cleanup();
      } catch (_) {
        cleanupComplete = false;
      }
    }
    return cleanupComplete;
  }
}
