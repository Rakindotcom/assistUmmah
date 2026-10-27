/// Applies explicit consent and restores the previous state on storage failure.
class DiagnosticsConsent {
  DiagnosticsConsent(
      {required this.enabled, required this.apply, required this.persist});
  bool enabled;
  final Future<void> Function(bool enabled) apply;
  final Future<void> Function(bool enabled) persist;

  Future<void> setEnabled(bool value) async {
    final previous = enabled;
    try {
      await apply(value);
      await persist(value);
      enabled = value;
    } catch (_) {
      try {
        await apply(previous);
      } catch (_) {/* reporting remains best effort */}
      rethrow;
    }
  }
}
