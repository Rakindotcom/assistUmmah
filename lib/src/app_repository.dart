import 'package:cloud_firestore/cloud_firestore.dart';

import 'date_helpers.dart';
import 'daily_logic.dart';
import 'models.dart';

class AppRepository {
  const AppRepository({required this.uid, required this.firebaseReady});

  final String uid;
  final bool firebaseReady;

  bool get canSync => firebaseReady && uid != 'demo';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _tasksRef {
    return _db.collection('userTasks').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> get _contactsRef {
    return _db.collection('userContacts').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> get _settingsRef {
    return _db.collection('userSettings').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> get _preferencesRef {
    return _db.collection('userPreferences').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _prayerRef(String date) {
    return _db
        .collection('userPrayers')
        .doc(uid)
        .collection('dailyPrayers')
        .doc(date);
  }

  DocumentReference<Map<String, dynamic>> _growthRef(String date) {
    return _db
        .collection('userGrowth')
        .doc(uid)
        .collection('dailyGrowth')
        .doc(date);
  }

  Future<void> ensureUserDocument({String? email, String? displayName}) async {
    if (!canSync) {
      return;
    }

    await _db.collection('users').doc(uid).set({
      'email': email ?? '',
      'displayName': displayName ?? '',
      'lastLogin': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> loadTasksForDate(String date) async {
    if (!canSync) {
      return null;
    }
    return _changeTasks(date: date);
  }

  Future<Map<String, dynamic>?> changeTasks({
    required String date,
    required void Function(
      Map<String, List<TaskItem>> today,
      Map<String, List<TaskItem>> missed,
    ) apply,
  }) async {
    if (!canSync) {
      return null;
    }
    return _changeTasks(date: date, apply: apply);
  }

  Future<Map<String, dynamic>> _changeTasks({
    required String date,
    void Function(
      Map<String, List<TaskItem>> today,
      Map<String, List<TaskItem>> missed,
    )? apply,
  }) {
    return _db.runTransaction((transaction) async {
      if (date != dateKey()) {
        throw StateError('The task day changed before this update.');
      }
      final snap = await transaction.get(_tasksRef);
      if (date != dateKey()) {
        throw StateError('The task day changed before this update.');
      }
      final data = snap.data() ?? <String, dynamic>{};
      final today = _taskBucketsFromMap(data['todayTasks']);
      final missed = _taskBucketsFromMap(data['missedTasks']);
      final moved = rollOverTaskBuckets(
        today,
        missed,
        date,
        previousDate: data['dateUpdated'] as String?,
      );
      apply?.call(today, missed);

      final result = <String, dynamic>{
        'todayTasks': _taskBucketsToMap(today),
        'missedTasks': _taskBucketsToMap(missed),
        'dateUpdated': date,
      };
      if (date != dateKey()) {
        throw StateError('The task day changed before this update.');
      }
      if (moved || apply != null) {
        transaction.set(_tasksRef, {
          ...result,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
      return result;
    });
  }

  Future<Map<String, dynamic>?> loadPrayerDocument(String date) async {
    if (!canSync) {
      return null;
    }
    final snap = await _prayerRef(date).get();
    return snap.data();
  }

  Future<void> savePrayer({
    required String date,
    required Map<String, PrayerStatus> prayers,
  }) async {
    if (!canSync) {
      return;
    }

    await _prayerRef(date).set({
      'prayers': prayers.map((key, value) => MapEntry(key, value.toMap())),
      'date': date,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> completeQaza({
    required String date,
    required String prayerKey,
  }) async {
    if (!canSync) {
      return;
    }

    await _prayerRef(date).set({
      'qazaCompletions': {prayerKey: true},
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> loadGrowth(String date) async {
    if (!canSync) {
      return null;
    }
    final snap = await _growthRef(date).get();
    return snap.data();
  }

  Future<String?> loadUserType() async {
    if (!canSync) {
      return null;
    }
    final snap = await _preferencesRef.get();
    return snap.data()?['userType'] as String?;
  }

  Future<void> saveGrowth({
    required String date,
    required String userType,
    required Map<String, bool> iman,
    required Map<String, bool> life,
  }) async {
    if (!canSync) {
      return;
    }

    final batch = _db.batch();
    batch.set(_growthRef(date), {
      'growthData': {'iman': iman, 'life': life},
      'userType': userType,
      'date': date,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    batch.set(_preferencesRef, {
      'userType': userType,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<Map<String, dynamic>?> loadContacts() async {
    if (!canSync) {
      return null;
    }
    final snap = await _contactsRef.get();
    return snap.data();
  }

  Future<Map<String, dynamic>?> changeContacts(
    void Function(Map<String, List<ContactItem>> contacts) apply,
  ) async {
    if (!canSync) {
      return null;
    }
    return _db.runTransaction((transaction) async {
      final snap = await transaction.get(_contactsRef);
      final contacts = _contactsFromMap(snap.data()?['contacts']);
      apply(contacts);
      final result = <String, dynamic>{
        'contacts': contacts.map(
          (key, value) =>
              MapEntry(key, value.map((item) => item.toMap()).toList()),
        ),
      };
      transaction.set(_contactsRef, {
        ...result,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      return result;
    });
  }

  Future<Map<String, dynamic>?> loadSettings() async {
    if (!canSync) {
      return null;
    }
    final snap = await _settingsRef.get();
    return snap.data();
  }

  Future<void> saveProfile(Map<String, Object?> profile) async {
    if (!canSync) {
      return;
    }

    await _settingsRef.set({
      'profile': profile,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveNotificationSettings(Map<String, bool> notifications) async {
    if (!canSync) {
      return;
    }

    await _settingsRef.set({
      'notifications': notifications,
      'remindersConfigured': true,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<ReportSummary> buildReport({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!canSync) {
      return ReportSummary.empty;
    }

    var days = 0;
    var prayerLoggedDays = 0;
    var totalPrayed = 0;
    var totalJamaat = 0;
    var totalMissed = 0;
    final today = dateOnly();
    final imanScores = <int>[];
    final lifeScores = <int>[];
    final overallScores = <int>[];

    for (final date in datesBetween(start, end)) {
      days++;
      final key = dateKey(date);

      final prayerSnap = await _prayerRef(key).get();
      final prayerDoc = prayerSnap.data();
      final prayers = asStringMap(prayerDoc?['prayers']);
      if (prayers.isNotEmpty) {
        prayerLoggedDays++;
        final statuses = prayerKeys.map(
          (key) => PrayerStatus.fromMap(prayers[key]),
        );
        final prayed = statuses.where((status) => status.prayed).length;
        final jamaat = statuses.where((status) => status.jamaat).length;
        totalPrayed += prayed;
        totalJamaat += jamaat;
        totalMissed += missedPrayerCountForDay(date, today, prayed);
      }

      final growthSnap = await _growthRef(key).get();
      final growthDoc = growthSnap.data();
      final growthData = asStringMap(growthDoc?['growthData']);
      if (growthData.isNotEmpty) {
        final userType = '${growthDoc?['userType'] ?? 'student'}';
        final iman = parseBoolMap(growthData['iman']);
        final life = parseBoolMap(growthData['life']);
        final lifeItems =
            lifeChecklists[userType] ?? lifeChecklists['student']!;
        final imanScore = checklistScore(iman, imanChecklist);
        final lifeScore = checklistScore(life, lifeItems);
        imanScores.add(imanScore);
        lifeScores.add(lifeScore);
        overallScores.add(((imanScore + lifeScore) / 2).round());
      }
    }

    return ReportSummary(
      days: days,
      prayerLoggedDays: prayerLoggedDays,
      totalPrayed: totalPrayed,
      totalJamaat: totalJamaat,
      totalMissed: totalMissed,
      growthLoggedDays: overallScores.length,
      averageIman: _average(imanScores),
      averageLife: _average(lifeScores),
      averageOverall: _average(overallScores),
    );
  }

  Map<String, Object?> _taskBucketsToMap(Map<String, List<TaskItem>> buckets) {
    return {
      'mustDo': buckets['mustDo']?.map((task) => task.toMap()).toList() ?? [],
      'goodToDo':
          buckets['goodToDo']?.map((task) => task.toMap()).toList() ?? [],
    };
  }

  Map<String, List<TaskItem>> _taskBucketsFromMap(Object? raw) {
    final map = asStringMap(raw);
    List<TaskItem> parse(Object? value) {
      if (value is! Iterable) return [];
      return value
          .map(TaskItem.fromMap)
          .where((task) => task.text.isNotEmpty)
          .toList();
    }

    return {'mustDo': parse(map['mustDo']), 'goodToDo': parse(map['goodToDo'])};
  }

  Map<String, List<ContactItem>> _contactsFromMap(Object? raw) {
    final map = asStringMap(raw);
    List<ContactItem> parse(Object? value) {
      if (value is! Iterable) return [];
      return value
          .map(ContactItem.fromMap)
          .where((item) => item.name.isNotEmpty)
          .toList();
    }

    return {'message': parse(map['message']), 'call': parse(map['call'])};
  }

  int _average(List<int> values) {
    if (values.isEmpty) {
      return 0;
    }
    return (values.reduce((a, b) => a + b) / values.length).round();
  }
}
