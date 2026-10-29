// In-memory, fabricated data for local UI review. Never initializes Firebase.
import 'package:ummah_assist/src/app_repository.dart';
import 'package:ummah_assist/src/date_helpers.dart';
import 'package:ummah_assist/src/dhikr_progress.dart';
import 'package:ummah_assist/src/models.dart';
import 'package:ummah_assist/src/progress_trends.dart';
import 'package:ummah_assist/src/qaza_backlog.dart';
import 'package:ummah_assist/src/quran_reading.dart';

class UiPreviewRepository extends AppRepository {
  UiPreviewRepository({required this.today})
      : super(uid: 'ui-preview', firebaseReady: false) {
    for (var i = 0; i < 30; i++) {
      final date = dateKey(DateTime(today.year, today.month, today.day - i));
      if (i % 9 != 4) {
        prayers[date] = {
          'prayers': {
            for (var p = 0; p < prayerKeys.length; p++)
              prayerKeys[p]: PrayerStatus(
                      state: i == 0 && p > 1
                          ? PrayerState.unlogged
                          : i % 5 == 2 && p == 0
                              ? PrayerState.missed
                              : PrayerState.prayed,
                      jamaat: (p == 0 || p == 1) && !(i % 5 == 2 && p == 0))
                  .toMap(),
          }
        };
        growth[date] = {
          'userType': 'student',
          'growthData': {
            'iman': {
              for (var n = 0; n < imanChecklist.length; n++)
                imanChecklist[n].key: n < (i == 0 ? 3 : 2 + i % 4)
            },
            'life': {
              for (var n = 0; n < lifeChecklists['student']!.length; n++)
                lifeChecklists['student']![n].key: n < (i == 0 ? 2 : 2 + i % 4)
            },
          }
        };
      }
      if (i < 7) {
        quran[date] = QuranReadingDay(
                date: date,
                logged: true,
                minutes: 12 + i,
                pages: 3 + i % 4,
                lastRead: 'সূরা আল-বাকারা • আয়াত ২০',
                goal: quranGoal)
            .toMap();
        dhikr[date] =
            DhikrDay(date: date, logged: true, goals: dhikrGoals, counts: {
          'subhanallah': 33,
          'alhamdulillah': i == 0 ? 20 : 33,
          'allahu_akbar': i == 0 ? 14 : 34
        }).toMap();
      }
    }
    final date = dateKey(today);
    todayTasks['mustDo']!.addAll([
      TaskItem(
          id: 'study',
          text: 'মনোযোগ দিয়ে এক ঘণ্টা পড়াশোনা',
          completed: false,
          createdAt: '',
          dateCreated: date),
      TaskItem(
          id: 'family',
          text: 'বাবা-মায়ের খোঁজ নেওয়া',
          completed: true,
          createdAt: '',
          dateCreated: date),
    ]);
    todayTasks['goodToDo']!.add(TaskItem(
        id: 'walk',
        text: 'বিকেলে একটু হাঁটা',
        completed: false,
        createdAt: '',
        dateCreated: date));
    scheduled.add(TaskItem(
        id: 'review',
        text: 'সপ্তাহের অগ্রগতি পর্যালোচনা',
        completed: false,
        createdAt: '',
        dateCreated: date,
        dueDate: dateKey(DateTime(today.year, today.month, today.day + 2)),
        section: 'mustDo'));
    contacts['message']!.addAll(const [
      ContactItem(id: 'friend', name: 'বন্ধু ও সহপাঠী', createdAt: ''),
      ContactItem(id: 'sister', name: 'বোনের খোঁজ নেওয়া', createdAt: ''),
    ]);
    contacts['call']!
        .add(const ContactItem(id: 'parents', name: 'বাবা-মা', createdAt: ''));
  }

  final DateTime today;
  final prayers = <String, Map<String, dynamic>>{};
  final growth = <String, Map<String, dynamic>>{};
  final quran = <String, Map<String, dynamic>>{};
  final dhikr = <String, Map<String, dynamic>>{};
  final todayTasks = <String, List<TaskItem>>{'mustDo': [], 'goodToDo': []};
  final missedTasks = <String, List<TaskItem>>{'mustDo': [], 'goodToDo': []};
  final scheduled = <TaskItem>[];
  final recurring = <RecurringTask>[];
  final contacts = <String, List<ContactItem>>{'message': [], 'call': []};
  GrowthChecklistConfig checklist = GrowthChecklistConfig.defaults();
  String userType = 'student';
  QuranGoal quranGoal = const QuranGoal(unit: QuranGoalUnit.pages, target: 5);
  DhikrGoals dhikrGoals = DhikrGoals.standard;
  Map<String, Object?> profile = {
    'name': 'নমুনা ব্যবহারকারী',
    'email': 'preview@example.com',
    'userType': 'student'
  };

  @override
  bool get canSync => true;
  @override
  Future<void> ensureUserDocument({String? email, String? displayName}) async {}

  Map<String, dynamic> _tasks() => {
        'todayTasks': todayTasks.map((key, value) =>
            MapEntry(key, value.map((item) => item.toMap()).toList())),
        'missedTasks': missedTasks.map((key, value) =>
            MapEntry(key, value.map((item) => item.toMap()).toList())),
        'scheduledTasks': scheduled.map((item) => item.toMap()).toList(),
        'recurringTasks': recurring.map((item) => item.toMap()).toList(),
      };
  @override
  Future<Map<String, dynamic>?> loadTasksForDate(String date) async => _tasks();
  @override
  Future<Map<String, dynamic>?> changeTasks(
      {required String date,
      required void Function(Map<String, List<TaskItem>>,
              Map<String, List<TaskItem>>, List<RecurringTask>, List<TaskItem>)
          apply}) async {
    apply(todayTasks, missedTasks, recurring, scheduled);
    return _tasks();
  }

  @override
  Future<Map<String, dynamic>?> loadPrayerDocument(String date) async =>
      prayers[date];
  @override
  Future<void> savePrayerStatus(
      {required String date,
      required String prayerKey,
      required PrayerStatus status}) async {
    prayers[date] = {
      'prayers': {
        ...asStringMap(prayers[date]?['prayers']),
        prayerKey: status.toMap()
      }
    };
  }

  @override
  Future<QazaBacklog> loadQazaBacklog({DateTime? today}) async =>
      QazaBacklog.fromDocuments(prayers, today: today ?? this.today);
  @override
  Future<bool> completeQazaIfMissed(
      {required String date, required String prayerKey}) async {
    if (prayerStatusesFromDocument(prayers[date])[prayerKey]?.state !=
        PrayerState.missed) {
      return false;
    }
    await savePrayerStatus(
        date: date,
        prayerKey: prayerKey,
        status: const PrayerStatus(state: PrayerState.madeUp));
    return true;
  }

  @override
  Future<Map<String, dynamic>?> loadGrowth(String date) async => growth[date];
  @override
  Future<String?> loadUserType() async => userType;
  @override
  Future<GrowthChecklistConfig> loadGrowthChecklistConfig() async => checklist;
  @override
  Future<void> saveGrowth(
      {required String date,
      required String userType,
      required Map<String, bool> iman,
      required Map<String, bool> life,
      bool updatePreferredType = true,
      GrowthChecklistSnapshot? checklistSnapshot,
      GrowthChecklistConfig? checklistConfig,
      bool prayerLinked = false}) async {
    if (updatePreferredType) this.userType = userType;
    if (checklistConfig != null) checklist = checklistConfig;
    growth[date] = {
      'userType': userType,
      'prayerLinked': prayerLinked,
      if (checklistSnapshot != null)
        'checklistItems': checklistSnapshot.toMap(),
      'growthData': {'iman': iman, 'life': life}
    };
  }

  @override
  Future<QuranGoal> loadQuranGoal() async => quranGoal;
  @override
  Future<void> saveQuranGoal(QuranGoal goal, {required DateTime today}) async {
    quranGoal = goal;
    final date = dateKey(today);
    if (quran[date] case final document?) {
      quran[date] = {...document, 'goal': goal.toMap()};
    }
  }

  @override
  Future<Map<String, dynamic>?> loadQuranDocument(String date) async =>
      quran[date];
  @override
  Future<void> saveQuranDay(QuranReadingDay day) async {
    quran[day.date] = day.toMap();
  }

  @override
  Future<QuranHistory> loadQuranHistory(
          {required DateTime end,
          required QuranGoal fallbackGoal,
          int dayCount = 7}) async =>
      QuranHistory.fromDocuments(
          end: end,
          dayCount: dayCount,
          documents: quran,
          fallbackGoal: fallbackGoal);
  @override
  Future<DhikrGoals> loadDhikrGoals() async => dhikrGoals;
  @override
  Future<void> saveDhikrGoals(DhikrGoals goals) async {
    dhikrGoals = goals;
  }

  @override
  Future<Map<String, dynamic>?> loadDhikrDocument(String date) async =>
      dhikr[date];
  @override
  Future<DhikrDay> saveDhikrGoalsForDay(
      {required String date,
      required DhikrGoals goals,
      required DhikrGoals fallback}) async {
    dhikrGoals = goals;
    final day = DhikrDay.fromDocument(date, dhikr[date], fallback: fallback)
        .includeGoals(goals);
    if (day.logged) dhikr[date] = day.toMap();
    return day;
  }

  @override
  Future<DhikrDay> setDhikrTarget(
      {required String date,
      required String goalId,
      required int target,
      required DhikrGoals fallback}) async {
    final day = DhikrDay.fromDocument(date, dhikr[date], fallback: fallback)
        .withTarget(goalId, target);
    dhikr[date] = day.toMap();
    return day;
  }

  @override
  Future<DhikrDay> resetDhikrCount(
      {required String date,
      required String goalId,
      required DhikrGoals fallback}) async {
    final day = DhikrDay.fromDocument(date, dhikr[date], fallback: fallback)
        .reset(goalId);
    dhikr[date] = day.toMap();
    return day;
  }

  @override
  Future<DhikrDay> changeDhikrCount(
      {required String date,
      required String goalId,
      required int delta,
      required DhikrGoals fallback}) async {
    final day = DhikrDay.fromDocument(date, dhikr[date], fallback: fallback)
        .change(goalId, delta);
    dhikr[date] = day.toMap();
    return day;
  }

  @override
  Future<DhikrHistory> loadDhikrHistory(
          {required DateTime end,
          required DhikrGoals fallback,
          int dayCount = 7}) async =>
      DhikrHistory(
          end: end, documents: dhikr, fallback: fallback, dayCount: dayCount);
  @override
  Future<ProgressTrends> loadProgressTrends(
          {required DateTime end, int dayCount = 30}) async =>
      ProgressTrends.fromDocuments(
          end: end, dayCount: dayCount, prayers: prayers, growth: growth);
  @override
  Future<Map<String, dynamic>?> loadContacts() async => {
        'contacts': contacts.map((key, value) =>
            MapEntry(key, value.map((item) => item.toMap()).toList()))
      };
  @override
  Future<Map<String, dynamic>?> changeContacts(
      void Function(Map<String, List<ContactItem>>) apply) async {
    apply(contacts);
    return loadContacts();
  }

  @override
  Future<Map<String, dynamic>?> loadSettings() async => {'profile': profile};
  @override
  Future<void> saveProfile(Map<String, Object?> profile) async {
    this.profile = profile;
  }

  @override
  Future<void> saveNotificationSettings(
      Map<String, bool> notifications) async {}
  @override
  Future<ReportSummary> buildReport(
      {required DateTime start, required DateTime end}) async {
    final range = datesBetween(start, end).toList();
    final trends = ProgressTrends.fromDocuments(
        end: end, dayCount: range.length, prayers: prayers, growth: growth);
    final days = trends.days;
    int mean(Iterable<int?> values) {
      final present = values.whereType<int>().toList();
      return present.isEmpty
          ? 0
          : (present.reduce((a, b) => a + b) / present.length).round();
    }

    return ReportSummary(
        days: days.length,
        prayerLoggedDays: days.where((day) => day.prayerLogged).length,
        totalPrayed: days.fold(0, (sum, day) => sum + day.prayer.prayed),
        totalJamaat: days.fold(0, (sum, day) => sum + day.prayer.jamaat),
        totalMissed: days.fold(0, (sum, day) => sum + day.prayer.missed),
        totalMadeUp: days.fold(0, (sum, day) => sum + day.prayer.madeUp),
        totalUnlogged: days.fold(0, (sum, day) => sum + day.prayer.unlogged),
        growthLoggedDays: days.where((day) => day.growthLogged).length,
        averageIman: mean(days.map((day) => day.imanScore)),
        averageLife: mean(days.map((day) => day.lifeScore)),
        averageOverall: mean(days.map((day) => day.overallScore)));
  }
}
