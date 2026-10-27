import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/diagnostics/diagnostics_consent.dart';

void main() {
  test('reporting remains disabled until explicit opt-in', () async {
    final applied = <bool>[];
    final consent = DiagnosticsConsent(
        enabled: false,
        apply: (value) async => applied.add(value),
        persist: (_) async {});
    expect(consent.enabled, isFalse);
    expect(applied, isEmpty);
    await consent.setEnabled(true);
    expect(consent.enabled, isTrue);
    expect(applied, [true]);
    await consent.setEnabled(false);
    expect(consent.enabled, isFalse);
    expect(applied, [true, false]);
  });
  test('a storage failure rolls reporting back to the previous consent',
      () async {
    final applied = <bool>[];
    final consent = DiagnosticsConsent(
        enabled: false,
        apply: (value) async => applied.add(value),
        persist: (_) async => throw StateError('disk'));
    await expectLater(consent.setEnabled(true), throwsStateError);
    expect(consent.enabled, isFalse);
    expect(applied, [true, false]);
  });
}
