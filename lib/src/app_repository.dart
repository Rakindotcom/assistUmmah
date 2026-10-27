import 'package:cloud_firestore/cloud_firestore.dart';

import 'date_helpers.dart';
import 'daily_logic.dart';
import 'dhikr_progress.dart';
import 'growth_progress.dart';
import 'models.dart';
import 'progress_trends.dart';
import 'quran_reading.dart';
import 'qaza_backlog.dart';

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

  CollectionReference<Map<String, dynamic>> get _prayersCollection =>
      _db.collection('userPrayers').doc(uid).collection('dailyPrayers');

  DocumentReference<Map<String, dynamic>> _prayerRef(String date) =>
      _prayersCollection.doc(date);

  DocumentReference<Map<String, dynamic>> _growthRef(String date) =>
      _growthCollection.doc(date);

  CollectionReference<Map<String, dynamic>> get _growthCollection =>
      _db.collection('userGrowth').doc(uid).collection('dailyGrowth');

  CollectionReference<Map<String, dynamic>> get _quranCollection =>
      _db.collection('userQuran').doc(uid).collection('dailyReading');

  DocumentReference<Map<String, dynamic>> _quranRef(String date) =>
      _quranCollection.doc(date);

  CollectionReference<Map<String, dynamic>> get _dhikrCollection =>
      _db.collection('userDhikr').doc(uid).collection('dailyDhikr');

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
      List<RecurringTask> recurring,
      List<TaskItem> scheduled,
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
      List<RecurringTask> recurring,
      List<TaskItem> scheduled,
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
      final recurring = _recurringTasksFromMap(data['recurringTasks']);
      final scheduled = _scheduledTasksFromMap(data['scheduledTasks']);
      final moved = rollOverTaskBuckets(
        today,
        missed,
        date,
        previousDate: data['dateUpdated'] as String?,
      );
      apply?.call(today, missed, recurring, scheduled);
      final promoted = materializeScheduledTasks(today, scheduled, date);
      final generated = materializeRecurringTasks(today, recurring, date,
          scheduled: scheduled);

      final result = <String, dynamic>{
        'todayTasks': _taskBucketsToMap(today),
        'missedTasks': _taskBucketsToMap(missed),
        'recurringTasks': recurring.map((task) => task.toMap()).toList(),
        'scheduledTasks': scheduled.map((task) => task.toMap()).toList(),
        'dateUpdated': date,
      };
      if (date != dateKey()) {
        throw StateError('The task day changed before this update.');
      }
      if (moved || promoted || generated || apply != null) {
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

  Future<void> savePrayerStatus({
    required String date,
    required String prayerKey,
    required PrayerStatus status,
  }) async {
    if (!canSync) {
      return;
    }

    await _prayerRef(date).set({
      'prayers': {prayerKey: status.toMap()},
      'date': date,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<QazaBacklog> loadQazaBacklog({DateTime? today}) async {
    final asOf = today ?? dateOnly();
    if (!canSync) {
      return QazaBacklog.fromDocuments(const {}, today: asOf);
    }

    final snapshots = await Future.wait([
      for (final key in prayerKeys)
        _prayersCollection
            .where('prayers.$key.state', isEqualTo: 'missed')
            .get(),
    ]);
    final documents = <String, Map<String, dynamic>>{};
    for (final snapshot in snapshots) {
      for (final document in snapshot.docs) {
        documents[document.id] = document.data();
      }
    }
    return QazaBacklog.fromDocuments(documents, today: asOf);
  }

  Future<bool> completeQazaIfMissed({
    required String date,
    required String prayerKey,
  }) async {
    if (!canSync) return false;
    if (!prayerKeys.contains(prayerKey)) {
      throw ArgumentError.value(prayerKey, 'prayerKey');
    }

    final reference = _prayerRef(date);
    return _db.runTransaction<bool>((transaction) async {
      final document = await transaction.get(reference);
      final current = prayerStatusesFromDocument(document.data())[prayerKey]!;
      if (current.state != PrayerState.missed) return false;
      transaction.set(
          reference,
          {
            'prayers': {
              prayerKey: const PrayerStatus(state: PrayerState.madeUp).toMap(),
            },
            'date': date,
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      return true;
    });
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

  Future<GrowthChecklistConfig> loadGrowthChecklistConfig() async {
    if (!canSync) return GrowthChecklistConfig.defaults();
    final snap = await _preferencesRef.get();
    return GrowthChecklistConfig.fromMap(snap.data()?['growthChecklist']);
  }

  Future<QuranGoal> loadQuranGoal() async {
    if (!canSync) return QuranGoal.standard;
    final snap = await _preferencesRef.get();
    return QuranGoal.fromMap(snap.data()?['quranGoal']);
  }

  Future<void> saveQuranGoal(QuranGoal goal, {required DateTime today}) async {
    if (!goal.valid) throw ArgumentError.value(goal.target, 'target');
    if (!canSync) return;
    final dayRef = _quranRef(dateKey(today));
    await _db.runTransaction((transaction) async {
      final day = await transaction.get(dayRef);
      transaction.set(
        _preferencesRef,
        {
          'quranGoal': goal.toMap(),
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (day.exists) {
        transaction.set(
          dayRef,
          {
            'goal': goal.toMap(),
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<Map<String, dynamic>?> loadQuranDocument(String date) async {
    if (!canSync) return null;
    final snap = await _quranRef(date).get();
    return snap.data();
  }

  Future<void> saveQuranDay(QuranReadingDay day) async {
    final parsed = DateTime.tryParse(day.date);
    if (!day.logged ||
        parsed == null ||
        dateKey(parsed) != day.date ||
        day.date.compareTo(dateKey()) > 0 ||
        day.minutes < 0 ||
        day.minutes > 1440 ||
        day.pages < 0 ||
        day.pages > 1000 ||
        day.lastRead.length > 120 ||
        !day.goal.valid) {
      throw ArgumentError.value(day, 'day');
    }
    if (!canSync) return;
    await _quranRef(day.date).set({
      ...day.toMap(),
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<QuranHistory> loadQuranHistory({
    required DateTime end,
    required QuranGoal fallbackGoal,
    int dayCount = 7,
  }) async {
    if (dayCount < 1 || dayCount > 366) {
      throw ArgumentError.value(dayCount, 'dayCount');
    }
    final last = dateOnly(end);
    if (!canSync) {
      return QuranHistory.fromDocuments(
        end: last,
        dayCount: dayCount,
        documents: const {},
        fallbackGoal: fallbackGoal,
      );
    }
    final first = DateTime(last.year, last.month, last.day - dayCount + 1);
    final snapshot = await _quranCollection
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: dateKey(first))
        .where(FieldPath.documentId, isLessThanOrEqualTo: dateKey(last))
        .get();
    return QuranHistory.fromDocuments(
      end: last,
      dayCount: dayCount,
      documents: {
        for (final document in snapshot.docs) document.id: document.data(),
      },
      fallbackGoal: fallbackGoal,
    );
  }

  Future<DhikrGoals> loadDhikrGoals() async {
    if (!canSync) return DhikrGoals.standard;
    final snapshot = await _preferencesRef.get();
    return DhikrGoals.fromList(snapshot.data()?['dhikrGoals']);
  }

  Future<void> saveDhikrGoals(DhikrGoals goals) async {
    if (!goals.valid) throw ArgumentError.value(goals, 'goals');
    if (!canSync) return;
    await _preferencesRef.set({
      'dhikrGoals': goals.toList(),
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> loadDhikrDocument(String date) async {
    if (!canSync) return null;
    return (await _dhikrCollection.doc(date).get()).data();
  }

  /// Apply a relative change so another device's increments are preserved.
  /// The first count saves the goal snapshot for this date.
  Future<DhikrDay> changeDhikrCount({
    required String date,
    required String goalId,
    required int delta,
    required DhikrGoals fallback,
  }) async {
    final parsed = DateTime.tryParse(date);
    if (parsed == null ||
        dateKey(parsed) != date ||
        date.compareTo(dateKey()) > 0 ||
        !fallback.valid ||
        delta == 0 ||
        delta.abs() > 100000) {
      throw ArgumentError('Invalid dhikr count change');
    }
    if (!canSync) {
      return DhikrDay.fromDocument(date, null, fallback: fallback)
          .change(goalId, delta);
    }
    final ref = _dhikrCollection.doc(date);
    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final day =
          DhikrDay.fromDocument(date, snapshot.data(), fallback: fallback)
              .change(goalId, delta);
      transaction.set(
          ref,
          {
            ...day.toMap(),
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      return day;
    });
  }

  Future<DhikrHistory> loadDhikrHistory({
    required DateTime end,
    required DhikrGoals fallback,
    int dayCount = 7,
  }) async {
    if (dayCount < 1 || dayCount > 366) {
      throw ArgumentError.value(dayCount, 'dayCount');
    }
    final last = dateOnly(end);
    final first = DateTime(last.year, last.month, last.day - dayCount + 1);
    final documents = <String, Map<String, dynamic>>{};
    if (canSync) {
      final snapshot = await _dhikrCollection
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: dateKey(first))
          .where(FieldPath.documentId, isLessThanOrEqualTo: dateKey(last))
          .get();
      documents
          .addEntries(snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())));
    }
    return DhikrHistory(
        end: last,
        documents: documents,
        fallback: fallback,
        dayCount: dayCount);
  }

  Future<void> saveGrowth({
    required String date,
    required String userType,
    required Map<String, bool> iman,
    required Map<String, bool> life,
    bool updatePreferredType = true,
    GrowthChecklistSnapshot? checklistSnapshot,
    GrowthChecklistConfig? checklistConfig,
    bool prayerLinked = false,
  }) async {
    if (!canSync) {
      return;
    }

    final batch = _db.batch();
    batch.set(_growthRef(date), {
      'growthData': {'iman': iman, 'life': life},
      'checklistItems': (checklistSnapshot ??
              GrowthChecklistSnapshot(
                iman: imanChecklist,
                life: lifeChecklists[userType] ?? lifeChecklists['student']!,
              ))
          .toMap(),
      'prayerLinked': prayerLinked,
      'userType': userType,
      'date': date,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    if (updatePreferredType || checklistConfig != null) {
      batch.set(
          _preferencesRef,
          {
            if (updatePreferredType) 'userType': userType,
            if (checklistConfig != null)
              'growthChecklist': checklistConfig.toMap(),
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }
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
    var totalMadeUp = 0;
    var totalUnlogged = 0;
    final imanScores = <int>[];
    final lifeScores = <int>[];
    final overallScores = <int>[];

    for (final date in datesBetween(start, end)) {
      days++;
      final key = dateKey(date);

      final prayerSnap = await _prayerRef(key).get();
      final prayerDoc = prayerSnap.data();
      final prayerSummary = PrayerSummary.fromDocument(prayerDoc);
      if (prayerSummary.anyLogged) {
        prayerLoggedDays++;
        totalPrayed += prayerSummary.prayed;
        totalJamaat += prayerSummary.jamaat;
        totalMissed += prayerSummary.missed;
        totalMadeUp += prayerSummary.madeUp;
        totalUnlogged += prayerSummary.unlogged;
      }

      final growthSnap = await _growthRef(key).get();
      final growthDoc = growthSnap.data();
      final growthData = asStringMap(growthDoc?['growthData']);
      if (growthData.isNotEmpty) {
        final iman = imanValuesForDocuments(growthDoc, prayerDoc);
        final life = parseBoolMap(growthData['life']);
        final snapshot = GrowthChecklistSnapshot.fromDocument(growthDoc);
        final imanScore = checklistScore(iman, snapshot.iman);
        final lifeScore = checklistScore(life, snapshot.life);
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
      totalMadeUp: totalMadeUp,
      totalUnlogged: totalUnlogged,
      growthLoggedDays: overallScores.length,
      averageIman: _average(imanScores),
      averageLife: _average(lifeScores),
      averageOverall: _average(overallScores),
    );
  }

  Future<ProgressTrends> loadProgressTrends({
    required DateTime end,
    int dayCount = 30,
  }) async {
    if (dayCount < 1 || dayCount > 366) {
      throw ArgumentError.value(dayCount, 'dayCount');
    }
    final last = dateOnly(end);
    final first = DateTime(last.year, last.month, last.day - dayCount + 1);
    if (!canSync) {
      return ProgressTrends.fromDocuments(
        end: last,
        dayCount: dayCount,
        prayers: const {},
        growth: const {},
      );
    }

    final firstKey = dateKey(first);
    final lastKey = dateKey(last);
    final snapshots = await Future.wait([
      _prayersCollection
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: firstKey)
          .where(FieldPath.documentId, isLessThanOrEqualTo: lastKey)
          .get(),
      _growthCollection
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: firstKey)
          .where(FieldPath.documentId, isLessThanOrEqualTo: lastKey)
          .get(),
    ]);
    final prayers = {
      for (final document in snapshots[0].docs) document.id: document.data(),
    };
    final growth = {
      for (final document in snapshots[1].docs) document.id: document.data(),
    };
    return ProgressTrends.fromDocuments(
      end: last,
      dayCount: dayCount,
      prayers: prayers,
      growth: growth,
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

  List<RecurringTask> _recurringTasksFromMap(Object? raw) {
    if (raw is! Iterable) return [];
    return raw
        .where((value) =>
            asStringMap(value)['repeat'] == 'daily' ||
            asStringMap(value)['repeat'] == 'weekly')
        .map(RecurringTask.fromMap)
        .where((task) =>
            task.id.isNotEmpty &&
            task.text.trim().isNotEmpty &&
            (task.section == 'mustDo' || task.section == 'goodToDo'))
        .toList();
  }

  List<TaskItem> _scheduledTasksFromMap(Object? raw) {
    if (raw is! Iterable) return [];
    return raw
        .map(TaskItem.fromMap)
        .where((task) =>
            task.id.isNotEmpty &&
            task.text.trim().isNotEmpty &&
            (task.section == 'mustDo' || task.section == 'goodToDo') &&
            DateTime.tryParse(task.dueDate) != null &&
            dateKey(DateTime.parse(task.dueDate)) == task.dueDate)
        .toList();
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
