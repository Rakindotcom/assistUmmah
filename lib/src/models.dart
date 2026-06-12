class TaskItem {
  const TaskItem({
    required this.id,
    required this.text,
    required this.completed,
    required this.createdAt,
    required this.dateCreated,
  });

  final String id;
  final String text;
  final bool completed;
  final String createdAt;
  final String dateCreated;

  TaskItem copyWith({bool? completed}) {
    return TaskItem(
      id: id,
      text: text,
      completed: completed ?? this.completed,
      createdAt: createdAt,
      dateCreated: dateCreated,
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
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'text': text,
      'completed': completed,
      'createdAt': createdAt,
      'dateCreated': dateCreated,
    };
  }
}

class PrayerStatus {
  const PrayerStatus({required this.prayed, required this.jamaat});

  final bool prayed;
  final bool jamaat;

  PrayerStatus copyWith({bool? prayed, bool? jamaat}) {
    return PrayerStatus(
      prayed: prayed ?? this.prayed,
      jamaat: jamaat ?? this.jamaat,
    );
  }

  factory PrayerStatus.fromMap(Object? raw) {
    final map = asStringMap(raw);
    return PrayerStatus(
      prayed: map['prayed'] == true,
      jamaat: map['jamat'] == true || map['jamaat'] == true,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'prayed': prayed,
      'jamat': jamaat,
    };
  }
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
}

class ReportSummary {
  const ReportSummary({
    required this.days,
    required this.prayerLoggedDays,
    required this.totalPrayed,
    required this.totalJamaat,
    required this.totalMissed,
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
      key: const PrayerStatus(prayed: false, jamaat: false),
  };
}

Map<String, bool> defaultChecklistMap(List<ChecklistItem> items) {
  return {for (final item in items) item.key: false};
}
