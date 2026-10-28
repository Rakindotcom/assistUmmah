import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ummah_assist/src/app.dart';
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/home_shell.dart';
import 'package:ummah_assist/src/pages/contacts_page.dart';
import 'package:ummah_assist/src/pages/growth_page.dart';
import 'package:ummah_assist/src/pages/prayer_page.dart';
import 'package:ummah_assist/src/pages/settings_page.dart';
import 'package:ummah_assist/src/pages/tasks_page.dart';

import 'support/native_ui_channels.dart';

void main() {
  testWidgets('opens only Today, then retains visited task state',
      (tester) async {
    configureNativeUiChannels();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _CountingRepository();
    await tester.pumpWidget(UmmahAssistApp(
      firebaseReady: false,
      home: HomeShell(
        firebaseReady: false,
        repository: repository,
        user: null,
      ),
    ));
    await tester.pumpAndSettle();

    expect(repository.taskReads, 1, reason: 'Only the dashboard needs tasks.');
    expect(repository.prayerReads, 1);
    expect(repository.growthReads, 1);
    expect(repository.settingsReads, 0);
    expect(repository.contactReads, 0);
    for (final type in [
      TasksPage,
      PrayerPage,
      GrowthPage,
      SettingsPage,
      ContactsPage
    ]) {
      expect(find.byType(type, skipOffstage: false), findsNothing);
    }

    await tester.tap(find.text('কাজ').last);
    await tester.pumpAndSettle();
    expect(repository.taskReads, 2);
    final tasksState = tester.state(find.byType(TasksPage));
    await tester.tap(find.text('আরও'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('কাজ').last);
    await tester.pumpAndSettle();
    expect(identical(tester.state(find.byType(TasksPage)), tasksState), isTrue);
    expect(repository.taskReads, 2,
        reason: 'Returning must preserve loaded state.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _CountingRepository extends AppRepository {
  _CountingRepository() : super(uid: 'test', firebaseReady: false);
  int taskReads = 0;
  int prayerReads = 0;
  int growthReads = 0;
  int settingsReads = 0;
  int contactReads = 0;
  @override
  Future<Map<String, dynamic>?> loadTasksForDate(String date) async {
    taskReads++;
    return null;
  }

  @override
  Future<Map<String, dynamic>?> loadPrayerDocument(String date) async {
    prayerReads++;
    return null;
  }

  @override
  Future<Map<String, dynamic>?> loadGrowth(String date) async {
    growthReads++;
    return null;
  }

  @override
  Future<Map<String, dynamic>?> loadSettings() async {
    settingsReads++;
    return null;
  }

  @override
  Future<Map<String, dynamic>?> loadContacts() async {
    contactReads++;
    return null;
  }
}
