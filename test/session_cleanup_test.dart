import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/account/session_cleanup.dart';

void main() {
  test('notification failure cannot prevent sign-out or Google cleanup',
      () async {
    final calls = <String>[];
    final cleanup = SessionCleanup(
      endSession: () async => calls.add('auth'),
      cancelReminders: () async {
        calls.add('notifications');
        throw Exception('native failure');
      },
      clearGoogleSession: () async => calls.add('google'),
    );
    expect(await cleanup.signOut(), isFalse);
    expect(calls, ['auth', 'notifications', 'google']);
  });
  test('Google cleanup failure leaves Firebase signed out', () async {
    var ended = false;
    final cleanup = SessionCleanup(
      endSession: () async => ended = true,
      cancelReminders: () async {},
      clearGoogleSession: () async => throw Exception('cancelled'),
    );
    expect(await cleanup.signOut(), isFalse);
    expect(ended, isTrue);
  });
  test('successful cleanup reports completion', () async {
    final cleanup = SessionCleanup(
        endSession: () async {},
        cancelReminders: () async {},
        clearGoogleSession: () async {});
    expect(await cleanup.signOut(), isTrue);
  });
  test('authentication sign-out failure is surfaced', () async {
    final cleanup = SessionCleanup(
        endSession: () async => throw StateError('auth failed'),
        cancelReminders: () async {},
        clearGoogleSession: () async {});
    expect(cleanup.signOut(), throwsStateError);
  });
}
