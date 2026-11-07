import '../core/records.dart';
import 'planning_time_zone.dart';

enum WorkspaceModule { personal, work, study, wellness, faith }

enum ExperienceTheme { system, light, dark }

class ExperienceOptions {
  ExperienceOptions({
    required this.language,
    required this.timeZone,
    Iterable<WorkspaceModule> modules = const [WorkspaceModule.personal],
    this.theme = ExperienceTheme.system,
    this.weekStartsOn = 1,
    this.use24HourClock = false,
    this.workdayStartsAt = 9 * 60,
    this.workdayEndsAt = 17 * 60,
    Iterable<int> workingDays = const [1, 2, 3, 4, 5],
    this.dailyCapacityMinutes = 360,
    this.completedOnboarding = false,
    this.activeWorkspace = 'personal',
  })  : modules = Set.unmodifiable(modules),
        workingDays = Set.unmodifiable(workingDays) {
    if (!['bn', 'en'].contains(language) ||
        timeZone.trim().isEmpty ||
        timeZone.length > 100 ||
        this.modules.isEmpty ||
        this.modules.every((value) => value == WorkspaceModule.faith) ||
        weekStartsOn < 1 ||
        weekStartsOn > 7 ||
        workdayStartsAt < 0 ||
        workdayStartsAt >= workdayEndsAt ||
        workdayEndsAt > 1440 ||
        this.workingDays.isEmpty ||
        this.workingDays.any((day) => day < 1 || day > 7) ||
        dailyCapacityMinutes < 0 ||
        dailyCapacityMinutes > 1440 ||
        !this.modules.any((module) =>
            module != WorkspaceModule.faith &&
            module.name == activeWorkspace)) {
      throw const FormatException('Invalid workspace preferences.');
    }
    try {
      PlanningTimeZone.location(timeZone);
    } catch (_) {
      throw const FormatException('Unknown time zone.');
    }
  }
  final String language, timeZone, activeWorkspace;
  final Set<WorkspaceModule> modules;
  final Set<int> workingDays;
  final ExperienceTheme theme;
  final int weekStartsOn, workdayStartsAt, workdayEndsAt, dailyCapacityMinutes;
  final bool use24HourClock, completedOnboarding;
  bool get faithEnabled => modules.contains(WorkspaceModule.faith);

  Map<String, Object?> toFields() => {
        'workspaceId': 'system',
        'type': 'experienceOptions',
        'language': language,
        'timeZone': timeZone,
        'modules': modules.map((module) => module.name).toList()..sort(),
        'theme': theme.name,
        'weekStartsOn': weekStartsOn,
        'use24HourClock': use24HourClock,
        'workdayStartsAt': workdayStartsAt,
        'workdayEndsAt': workdayEndsAt,
        'workingDays': workingDays.toList()..sort(),
        'dailyCapacityMinutes': dailyCapacityMinutes,
        'completedOnboarding': completedOnboarding,
        'activeWorkspace': activeWorkspace,
      };
  factory ExperienceOptions.fromRecord(WorkspaceRecord record) {
    if (record.kind != RecordKind.workspace ||
        record.fields['type'] != 'experienceOptions') {
      throw const FormatException('Not workspace preferences.');
    }
    final data = record.fields;
    return ExperienceOptions(
        language: data['language'] as String,
        timeZone: data['timeZone'] as String,
        modules: (data['modules'] as List)
            .map((value) => WorkspaceModule.values.byName(value as String)),
        theme:
            ExperienceTheme.values.byName(data['theme'] as String? ?? 'system'),
        weekStartsOn: data['weekStartsOn'] as int? ?? 1,
        use24HourClock: data['use24HourClock'] == true,
        workdayStartsAt: data['workdayStartsAt'] as int? ?? 540,
        workdayEndsAt: data['workdayEndsAt'] as int? ?? 1020,
        workingDays:
            List<int>.from(data['workingDays'] as List? ?? [1, 2, 3, 4, 5]),
        dailyCapacityMinutes: data['dailyCapacityMinutes'] as int? ?? 360,
        completedOnboarding: data['completedOnboarding'] == true,
        activeWorkspace: data['activeWorkspace'] as String? ?? 'personal');
  }
}
