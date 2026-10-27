import 'date_helpers.dart';
import 'models.dart';

bool rollOverTaskBuckets(
  Map<String, List<TaskItem>> today,
  Map<String, List<TaskItem>> missed,
  String date, {
  String? previousDate,
}) {
  var moved = false;
  for (final section in ['mustDo', 'goodToDo']) {
    final retained = <TaskItem>[];
    final missedItems = missed[section]!;
    for (final task in today[section]!) {
      final taskDate =
          task.dateCreated.isEmpty ? previousDate : task.dateCreated;
      if (taskDate == null || taskDate == date) {
        retained.add(task);
      } else {
        if (!task.completed) missedItems.add(task);
        moved = true;
      }
    }
    today[section] = retained;
  }
  return moved;
}

bool materializeRecurringTasks(Map<String, List<TaskItem>> today,
    List<RecurringTask> recurring, String date,
    {List<TaskItem> scheduled = const []}) {
  final day = DateTime.tryParse(date);
  if (day == null || dateKey(day) != date) return false;
  var added = false;
  for (final template in recurring) {
    if (template.id.isEmpty ||
        template.text.trim().isEmpty ||
        !today.containsKey(template.section)) {
      continue;
    }
    final start = DateTime.tryParse(template.startDate);
    if (start == null ||
        dateKey(start) != template.startDate ||
        template.startDate.compareTo(date) > 0) {
      continue;
    }
    if (template.repeat == TaskRepeat.weekly && start.weekday != day.weekday) {
      continue;
    }
    final tasks = today[template.section]!;
    if (scheduled.any((task) => task.id == '${template.id}:$date')) {
      continue;
    }
    if (tasks.any((task) => task.id == '${template.id}:$date')) continue;
    tasks.add(TaskItem(
      id: '${template.id}:$date',
      text: template.text,
      completed: false,
      createdAt: DateTime(day.year, day.month, day.day).toIso8601String(),
      dateCreated: date,
      recurrenceId: template.id,
      dueDate: date,
      section: template.section,
    ));
    added = true;
  }
  return added;
}

bool materializeScheduledTasks(
  Map<String, List<TaskItem>> today,
  List<TaskItem> scheduled,
  String date,
) {
  var moved = false;
  final remaining = <TaskItem>[];
  for (final task in scheduled) {
    final due = DateTime.tryParse(task.dueDate);
    if (due != null &&
        dateKey(due) == task.dueDate &&
        task.dueDate.compareTo(date) <= 0 &&
        today.containsKey(task.section)) {
      final bucket = today[task.section]!;
      if (!bucket.any((item) => item.id == task.id)) {
        bucket.add(task.copyWith(dateCreated: date));
      }
      moved = true;
    } else {
      remaining.add(task);
    }
  }
  if (moved) {
    scheduled
      ..clear()
      ..addAll(remaining);
  }
  return moved;
}
