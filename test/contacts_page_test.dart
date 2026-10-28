import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/pages/contacts_page.dart';

void main() {
  testWidgets('returning to Contacts fetches another device change',
      (tester) async {
    final repository = _ContactsRepository();
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    expect(find.text('New contact'), findsNothing);

    await tester.pumpWidget(_page(repository, active: false));
    repository.contacts['message']!
        .add(const ContactItem(id: 'new', name: 'New contact', createdAt: ''));
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    expect(find.text('New contact'), findsOneWidget);
  });

  testWidgets('active Contacts refreshes after app resume', (tester) async {
    final repository = _ContactsRepository();
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    repository.contacts['message']!.add(const ContactItem(
        id: 'resume', name: 'Resumed contact', createdAt: ''));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Resumed contact'), findsOneWidget);
  });

  testWidgets('phone pull-to-refresh fetches contacts without leaving page',
      (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _ContactsRepository();
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    expect(repository.reads, 1);
    repository.contacts['message']!.add(
        const ContactItem(id: 'pull', name: 'Pulled contact', createdAt: ''));
    await tester.drag(find.byType(ListView), const Offset(0, 360));
    await tester.pumpAndSettle();
    expect(repository.reads, 2);
    expect(find.text('Pulled contact'), findsOneWidget);
  });

  testWidgets('preview contacts survive a phone refresh', (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _PreviewContactsRepository();
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    await tester.tap(find.text('যোগাযোগ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Local contact');
    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();
    expect(find.text('Local contact'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 360));
    await tester.pumpAndSettle();
    expect(find.text('Local contact'), findsOneWidget);
  });

  testWidgets('late Contacts refresh cannot replace a newer response',
      (tester) async {
    final repository = _DeferredContactsRepository();
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    await tester.pumpWidget(_page(repository, active: false));
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pumpWidget(_page(repository, active: false));
    await tester.pumpWidget(_page(repository, active: true));
    expect(repository.refreshes, hasLength(2));

    repository.refreshes[1].complete(_snapshotFor('new', 'New contact'));
    await tester.pump();
    expect(find.text('New contact'), findsOneWidget);
    repository.refreshes[0].complete(_snapshotFor('old', 'Old contact'));
    await tester.pump();
    expect(find.text('New contact'), findsOneWidget);
    expect(find.text('Old contact'), findsNothing);
  });

  testWidgets('a late refresh cannot erase a newly saved contact',
      (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _DeferredContactsRepository();
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    await tester.pumpWidget(_page(repository, active: false));
    await tester.pumpWidget(_page(repository, active: true));
    expect(repository.refreshes, hasLength(1));

    await tester.tap(find.text('যোগাযোগ'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'New contact');
    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();
    expect(find.text('New contact'), findsOneWidget);

    repository.refreshes.single.complete(_snapshotFor('old', 'Old contact'));
    await tester.pump();
    expect(find.text('New contact'), findsOneWidget);
    expect(find.text('Old contact'), findsNothing);
  });

  testWidgets('failed Contacts refresh keeps loaded data and retry',
      (tester) async {
    final repository = _DeferredContactsRepository();
    repository.contacts['message']!.add(
        const ContactItem(id: 'saved', name: 'Saved contact', createdAt: ''));
    await tester.pumpWidget(_page(repository, active: true));
    await tester.pump();
    await tester.pumpWidget(_page(repository, active: false));
    await tester.pumpWidget(_page(repository, active: true));
    expect(find.text('Saved contact'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    repository.refreshes.single.completeError(StateError('network'));
    await tester.pump();
    expect(find.text('Saved contact'), findsOneWidget);
    expect(find.text('সর্বশেষ যোগাযোগ আনা যায়নি'), findsOneWidget);
    expect(find.text('রিট্রাই'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _page(AppRepository repository, {required bool active}) => MaterialApp(
      home:
          Scaffold(body: ContactsPage(repository: repository, active: active)),
    );

Map<String, dynamic> _snapshotFor(String id, String name) => {
      'contacts': {
        'message': [
          ContactItem(id: id, name: name, createdAt: '').toMap(),
        ],
        'call': <Map<String, dynamic>>[],
      },
    };

class _ContactsRepository extends AppRepository {
  _ContactsRepository() : super(uid: 'contact-test', firebaseReady: false);

  final contacts = <String, List<ContactItem>>{'message': [], 'call': []};
  int reads = 0;

  @override
  bool get canSync => true;

  @override
  Future<Map<String, dynamic>?> loadContacts() async {
    reads++;
    return _snapshot();
  }

  @override
  Future<Map<String, dynamic>?> changeContacts(
      void Function(Map<String, List<ContactItem>> contacts) apply) async {
    apply(contacts);
    return _snapshot();
  }

  Map<String, dynamic> _snapshot() => {
        'contacts': {
          for (final section in ['message', 'call'])
            section: contacts[section]!.map((item) => item.toMap()).toList(),
        },
      };
}

class _DeferredContactsRepository extends _ContactsRepository {
  int loads = 0;
  final refreshes = <Completer<Map<String, dynamic>?>>[];

  @override
  Future<Map<String, dynamic>?> loadContacts() {
    loads++;
    if (loads == 1) return super.loadContacts();
    final refresh = Completer<Map<String, dynamic>?>();
    refreshes.add(refresh);
    return refresh.future;
  }
}

class _PreviewContactsRepository extends AppRepository {
  _PreviewContactsRepository() : super(uid: 'preview', firebaseReady: false);
}
