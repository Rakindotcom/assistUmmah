import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/auth/account_access_guard.dart';

void main() {
  for (final listenerFails in [false, true]) {
    testWidgets(
        'revocation removes private routes and dialogs (error=$listenerFails)',
        (tester) async {
      final markers = StreamController<bool>();
      addTearDown(markers.close);
      var cancellations = 0;
      await tester.pumpWidget(MaterialApp(
        home: AccountAccessGuard(
          blockedStates: markers.stream,
          onAccessRevoked: () async {
            cancellations++;
            throw StateError('native plugin unavailable');
          },
          allowedBuilder: (_) => const _PrivateHome(),
          blockedBuilder: (_, failed) => Scaffold(
              body: Text(failed ? 'Retry access check' : 'Resume deletion')),
        ),
      ));
      markers.add(false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      expect(find.text('Private report'), findsOneWidget);
      if (listenerFails) {
        markers.addError(StateError('permission denied'));
      } else {
        markers.add(true);
      }
      await tester.pumpAndSettle();
      expect(find.text('Private report', skipOffstage: false), findsNothing);
      expect(find.text('Report', skipOffstage: false), findsNothing);
      expect(find.text('History', skipOffstage: false), findsNothing);
      expect(
          find.text(listenerFails ? 'Retry access check' : 'Resume deletion'),
          findsOneWidget);
      expect(cancellations, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'an active deletion can finish, Back cannot reopen private history',
      (tester) async {
    final markers = StreamController<bool>();
    addTearDown(markers.close);
    await tester.pumpWidget(MaterialApp(
      home: AccountAccessGuard(
        blockedStates: markers.stream,
        onAccessRevoked: () async {},
        allowedBuilder: (_) => const _PrivateHome(),
        blockedBuilder: (_, failed) =>
            const Scaffold(body: Text('Resume deletion')),
      ),
    ));
    markers.add(false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    markers.add(true);
    await tester.pumpAndSettle();
    expect(find.text('Deletion in progress'), findsOneWidget);
    final navigator =
        Navigator.of(tester.element(find.text('Deletion in progress')));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Resume deletion'), findsOneWidget);
    expect(find.text('History', skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _PrivateHome extends StatelessWidget {
  const _PrivateHome();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          const AlertDialog(content: Text('Private report'))),
                  child: const Text('Report'),
                ),
              ),
            )),
            child: const Text('History'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                settings:
                    const RouteSettings(name: AccountAccessGuard.deletionRoute),
                builder: (_) =>
                    const Scaffold(body: Text('Deletion in progress')))),
            child: const Text('Delete'),
          ),
        ]),
      );
}
