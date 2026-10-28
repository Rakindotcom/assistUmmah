import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/auth/account_navigation_boundary.dart';

void main() {
  testWidgets('sign-out removes pushed private routes and open dialogs',
      (tester) async {
    final sessions = StreamController<String?>();
    addTearDown(sessions.close);
    await tester.pumpWidget(AccountNavigationBoundary(
      sessionIds: sessions.stream,
      initialSessionId: 'first-user',
      child: const MaterialApp(home: _Home()),
    ));
    await tester.tap(find.text('Open history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();
    expect(find.text('Private report'), findsOneWidget);
    sessions.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Private report', skipOffstage: false), findsNothing);
    expect(find.text('Private history', skipOffstage: false), findsNothing);
    expect(find.text('Open history'), findsOneWidget);
    expect(Navigator.of(tester.element(find.text('Open history'))).canPop(),
        isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'token refresh preserves state, direct account switch discards it',
      (tester) async {
    final sessions = StreamController<String?>();
    addTearDown(sessions.close);
    await tester.pumpWidget(AccountNavigationBoundary(
      sessionIds: sessions.stream,
      initialSessionId: 'first-user',
      child: const MaterialApp(home: _Home()),
    ));
    await tester.tap(find.text('Open history'));
    await tester.pumpAndSettle();
    sessions.add('first-user');
    await tester.pumpAndSettle();
    expect(find.text('Private history'), findsOneWidget);
    sessions.add('second-user');
    await tester.pumpAndSettle();
    expect(find.text('Private history', skipOffstage: false), findsNothing);
    expect(find.text('Open history'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(
          body: TextButton(
        child: const Text('Open history'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (context) => Scaffold(
              body: Column(children: [
            const Text('Private history'),
            TextButton(
                child: const Text('Open report'),
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        const AlertDialog(content: Text('Private report')))),
          ])),
        )),
      ));
}
