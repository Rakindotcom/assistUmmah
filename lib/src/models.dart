class TaskItem {
  const TaskItem({
    required this.id,
    required this.text,
    required this.completed,
    required this.createdAt,
    required this.dateCreated,
    this.recurrenceId = '',
    this.dueDate = '',
    this.section = '',
  });

  final String id;
  final String text;
  final bool completed;
  final String createdAt;
  final String dateCreated;
  final String recurrenceId;
  final String dueDate;
  final String section;

  TaskItem copyWith(
      {bool? completed,
      String? dateCreated,
      String? dueDate,
      String? section}) {
    return TaskItem(
      id: id,
      text: text,
      completed: completed ?? this.completed,
      createdAt: createdAt,
      dateCreated: dateCreated ?? this.dateCreated,
      recurrenceId: recurrenceId,
      dueDate: dueDate ?? this.dueDate,
      section: section ?? this.section,
    );
  }

  factory TaskItem.fromMap(Object? raw) {
    final map = asStringMap(raw);
    return TaskItem(
      id: '${map['id'] ?? DateTime.now().microsecondsSinceEpoch}',
      text: '${map['text'] ?? ''}',
      completed: map['completed'] == true,
      createdAt: '${map['createdAt'] ?? ''}',
      dateCreated: '${map['dateCreated'] ?? ''}',
      recurrenceId: '${map['recurrenceId'] ?? ''}',
      dueDate: '${map['dueDate'] ?? ''}',
      section: '${map['section'] ?? ''}',
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'text': text,
      'completed': completed,
      'createdAt': createdAt,
      'dateCreated': dateCreated,
      if (recurrenceId.isNotEmpty) 'recurrenceId': recurrenceId,
      if (dueDate.isNotEmpty) 'dueDate': dueDate,
      if (section.isNotEmpty) 'section': section,
    };
  }
}

enum TaskRepeat { daily, weekly }

class RecurringTask {
  const RecurringTask({
    required this.id,
    required this.text,
    required this.section,
    required this.repeat,
    required this.startDate,
  });

  final String id;
  final String text;
  final String section;
  final TaskRepeat repeat;
  final String startDate;

  factory RecurringTask.fromMap(Object? raw) {
    final map = asStringMap(raw);
    return RecurringTask(
      id: '${map['id'] ?? ''}',
      text: '${map['text'] ?? ''}',
      section: '${map['section'] ?? ''}',
      repeat: TaskRepeat.values.firstWhere(
        (value) => value.name == map['repeat'],
        orElse: () => TaskRepeat.daily,
      ),
      startDate: '${map['startDate'] ?? ''}',
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'text': text,
        'section': section,
        'repeat': repeat.name,
        'startDate': startDate,
      };
}

enum PrayerState { unlogged, prayed, missed, madeUp }

const prayerStateLabels = {
  PrayerState.unlogged: 'হিসাব নেই',
  PrayerState.prayed: 'পড়া হয়েছে',
  PrayerState.missed: 'মিস হয়েছে',
  PrayerState.madeUp: 'কাযা আদায়',
};

class PrayerStatus {
  const PrayerStatus({required this.state, this.jamaat = false})
      : assert(state == PrayerState.prayed || !jamaat);

  final PrayerState state;
  final bool jamaat;

  bool get prayed => state == PrayerState.prayed;
  bool get logged => state != PrayerState.unlogged;

  PrayerStatus copyWith({PrayerState? state, bool? jamaat}) {
    final nextState = state ?? this.state;
    return PrayerStatus(
      state: nextState,
      jamaat: nextState == PrayerState.prayed ? jamaat ?? this.jamaat : false,
    );
  }

  factory PrayerStatus.fromMap(
    Object? raw, {
    bool legacyQazaCompleted = false,
  }) {
    final map = asStringMap(raw);
    final rawState = map['state'];
    PrayerState? state;
    for (final candidate in PrayerState.values) {
      if (candidate.name == rawState) {
        state = candidate;
        break;
      }
    }
    state ??= map['prayed'] == true
        ? PrayerState.prayed
        : legacyQazaCompleted && map.isNotEmpty
            ? PrayerState.madeUp
            : PrayerState.unlogged;
    return PrayerStatus(
      state: state,
      jamaat: state == PrayerState.prayed &&
          (map['jamat'] == true || map['jamaat'] == true),
    );
  }

  Map<String, Object?> toMap() => {
        'state': state.name,
        'prayed': prayed,
        'jamat': jamaat,
      };
}

Map<String, PrayerStatus> prayerStatusesFromDocument(
  Map<String, dynamic>? document,
) {
  final prayers = asStringMap(document?['prayers']);
  final completions = parseBoolMap(document?['qazaCompletions']);
  return {
    for (final key in prayerKeys)
      key: PrayerStatus.fromMap(
        prayers[key],
        legacyQazaCompleted: completions[key] == true,
      ),
  };
}

class PrayerSummary {
  const PrayerSummary({
    required this.prayed,
    required this.missed,
    required this.madeUp,
    required this.unlogged,
    required this.jamaat,
  });

  final int prayed;
  final int missed;
  final int madeUp;
  final int unlogged;
  final int jamaat;

  bool get anyLogged => unlogged < prayerKeys.length;

  factory PrayerSummary.fromStatuses(Iterable<PrayerStatus> statuses) {
    final values = statuses.toList();
    return PrayerSummary(
      prayed:
          values.where((status) => status.state == PrayerState.prayed).length,
      missed:
          values.where((status) => status.state == PrayerState.missed).length,
      madeUp:
          values.where((status) => status.state == PrayerState.madeUp).length,
      unlogged:
          values.where((status) => status.state == PrayerState.unlogged).length,
      jamaat: values.where((status) => status.jamaat).length,
    );
  }

  factory PrayerSummary.fromDocument(Map<String, dynamic>? document) =>
      PrayerSummary.fromStatuses(prayerStatusesFromDocument(document).values);
}

class ContactItem {
  const ContactItem({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String createdAt;

  factory ContactItem.fromMap(Object? raw) {
    final map = asStringMap(raw);
    return ContactItem(
      id: '${map['id'] ?? DateTime.now().microsecondsSinceEpoch}',
      name: '${map['name'] ?? ''}',
      createdAt: '${map['createdAt'] ?? ''}',
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt,
    };
  }
}

class ChecklistItem {
  const ChecklistItem(this.key, this.label);

  final String key;
  final String label;

  Map<String, String> toMap() => {'key': key, 'label': label};
}

List<ChecklistItem> parseChecklistItems(Object? raw) {
  if (raw is! Iterable) return [];
  final seen = <String>{};
  final items = <ChecklistItem>[];
  final safeKey = RegExp(r'^[a-zA-Z0-9_-]{1,80}$');
  for (final value in raw) {
    final map = asStringMap(value);
    final key = map['key'];
    final label = map['label'];
    if (key is! String ||
        label is! String ||
        !safeKey.hasMatch(key) ||
        label.trim().isEmpty ||
        label.length > 160 ||
        !seen.add(key)) {
      continue;
    }
    items.add(ChecklistItem(key, label.trim()));
  }
  return items;
}

class GrowthChecklistConfig {
  const GrowthChecklistConfig({required this.iman, required this.life});

  final List<ChecklistItem> iman;
  final Map<String, List<ChecklistItem>> life;

  factory GrowthChecklistConfig.defaults() => const GrowthChecklistConfig(
        iman: imanChecklist,
        life: lifeChecklists,
      );

  factory GrowthChecklistConfig.fromMap(Object? raw) {
    final map = asStringMap(raw);
    final rawLife = asStringMap(map['life']);
    return GrowthChecklistConfig(
      iman: map['iman'] is Iterable
          ? parseChecklistItems(map['iman'])
          : imanChecklist,
      life: {
        for (final type in userTypeLabels.keys)
          type: rawLife[type] is Iterable
              ? parseChecklistItems(rawLife[type])
              : lifeChecklists[type]!,
      },
    );
  }

  List<ChecklistItem> lifeFor(String userType) =>
      life[userType] ?? life['student'] ?? lifeChecklists['student']!;

  GrowthChecklistConfig withItems(
    String category,
    String userType,
    List<ChecklistItem> items,
  ) =>
      category == 'iman'
          ? GrowthChecklistConfig(iman: List.of(items), life: life)
          : GrowthChecklistConfig(
              iman: iman,
              life: {...life, userType: List.of(items)},
            );

  Map<String, Object?> toMap() => {
        'iman': iman.map((item) => item.toMap()).toList(),
        'life': {
          for (final entry in life.entries)
            entry.key: entry.value.map((item) => item.toMap()).toList(),
        },
      };
}

class GrowthChecklistSnapshot {
  const GrowthChecklistSnapshot({required this.iman, required this.life});

  final List<ChecklistItem> iman;
  final List<ChecklistItem> life;

  factory GrowthChecklistSnapshot.fromDocument(Map<String, dynamic>? doc) {
    final userType = '${doc?['userType'] ?? 'student'}';
    final raw = asStringMap(doc?['checklistItems']);
    return GrowthChecklistSnapshot(
      iman: raw['iman'] is Iterable
          ? parseChecklistItems(raw['iman'])
          : imanChecklist,
      life: raw['life'] is Iterable
          ? parseChecklistItems(raw['life'])
          : lifeChecklists[userType] ?? lifeChecklists['student']!,
    );
  }

  Map<String, Object?> toMap() => {
        'iman': iman.map((item) => item.toMap()).toList(),
        'life': life.map((item) => item.toMap()).toList(),
      };
}

class ReportSummary {
  const ReportSummary({
    required this.days,
    required this.prayerLoggedDays,
    required this.totalPrayed,
    required this.totalJamaat,
    required this.totalMissed,
    required this.totalMadeUp,
    required this.totalUnlogged,
    required this.growthLoggedDays,
    required this.averageIman,
    required this.averageLife,
    required this.averageOverall,
  });

  final int days;
  final int prayerLoggedDays;
  final int totalPrayed;
  final int totalJamaat;
  final int totalMissed;
  final int totalMadeUp;
  final int totalUnlogged;
  final int growthLoggedDays;
  final int averageIman;
  final int averageLife;
  final int averageOverall;

  static const empty = ReportSummary(
    days: 0,
    prayerLoggedDays: 0,
    totalPrayed: 0,
    totalJamaat: 0,
    totalMissed: 0,
    totalMadeUp: 0,
    totalUnlogged: 0,
    growthLoggedDays: 0,
    averageIman: 0,
    averageLife: 0,
    averageOverall: 0,
  );
}

const prayerKeys = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

const prayerLabels = {
  'fajr': 'ফজর',
  'dhuhr': 'যুহর',
  'asr': 'আসর',
  'maghrib': 'মাগরিব',
  'isha': 'ইশা',
};

const imanChecklist = [
  ChecklistItem('istigfar', 'ইস্তিগফার ও মাইন্ডফুল জিকির করেছি'),
  ChecklistItem('prayer', '৫ ওয়াক্ত নামাজ পড়েছি'),
  ChecklistItem('quran', 'কমপক্ষে ১০ মিনিট অর্থসহ কুরআন পড়েছি'),
  ChecklistItem('islamicLecture', 'ইসলামিক লেকচার শুনেছি/সীরাত পড়েছি'),
  ChecklistItem('protection', 'চোখ ও মুখের হেফাজত করেছি'),
];

const userTypeLabels = {
  'student': 'স্টুডেন্ট',
  'professional': 'চাকুরিজীবি/ব্যবসায়ী',
  'homemaker': 'হোমমেকার',
};

const lifeChecklists = {
  'student': [
    ChecklistItem('deepStudy', 'কমপক্ষে ২ ঘণ্টা ডিপ স্ট্যাডি করেছি'),
    ChecklistItem('careerDev', 'ক্যারিয়ার ডেভেলপমেন্টে সময় দিয়েছি'),
    ChecklistItem('family', 'পরিবারকে সময় দিয়েছি/খোঁজখবর নিয়েছি'),
    ChecklistItem('exercise', 'অন্তত ১৫ মিনিট হাঁটা/ব্যায়াম করেছি'),
    ChecklistItem('sleep', 'রাত ১১ টার মধ্যে ঘুমাতে এসেছি'),
  ],
  'professional': [
    ChecklistItem('deepWork', 'কমপক্ষে ৩ ঘণ্টা ডিপ ওয়ার্ক করেছি'),
    ChecklistItem(
        'professionalDev', 'প্রফেশনাল লাইফ ডেভেলপমেন্টে সময় দিয়েছি'),
    ChecklistItem('family', 'পরিবার ও আত্মীয়স্বজনকে সময় দিয়েছি'),
    ChecklistItem('exercise', 'অন্তত ১৫ মিনিট হাঁটা/ব্যায়াম করেছি'),
    ChecklistItem('sleep', 'রাত ১১ টার মধ্যে ঘুমাতে এসেছি'),
  ],
  'homemaker': [
    ChecklistItem('hobby', 'শখের কোনো কাজে সময় দিয়েছি'),
    ChecklistItem('journaling', 'মনের কথাগুলো জার্নালিং করেছি'),
    ChecklistItem('selfCare', 'নিজের যত্নে হাঁটা/ব্যায়াম/পড়াশোনা করেছি'),
    ChecklistItem('communication', 'পরিবার ও আত্মীয়দের সাথে যোগাযোগ করেছি'),
    ChecklistItem('sleep', 'রাত ১১ টার মধ্যে ঘুমাতে এসেছি'),
  ],
};

Map<String, dynamic> asStringMap(Object? raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is Map) {
    return raw.map((key, value) => MapEntry('$key', value));
  }
  return <String, dynamic>{};
}

Map<String, bool> parseBoolMap(Object? raw) {
  final map = asStringMap(raw);
  return map.map((key, value) => MapEntry(key, value == true));
}

int checklistScore(Map<String, bool> values, List<ChecklistItem> items) {
  if (items.isEmpty) {
    return 0;
  }
  final completed = items.where((item) => values[item.key] == true).length;
  return ((completed / items.length) * 100).round();
}

Map<String, PrayerStatus> defaultPrayerMap() {
  return {
    for (final key in prayerKeys)
      key: const PrayerStatus(state: PrayerState.unlogged),
  };
}

Map<String, bool> defaultChecklistMap(List<ChecklistItem> items) {
  return {for (final item in items) item.key: false};
}
