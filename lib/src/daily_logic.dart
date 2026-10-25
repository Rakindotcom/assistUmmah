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

bool isQazaPending(
  Map<String, dynamic> yesterdayPrayers,
  Map<String, bool> completions,
  String prayerKey,
) {
  return yesterdayPrayers.isNotEmpty &&
      !PrayerStatus.fromMap(yesterdayPrayers[prayerKey]).prayed &&
      completions[prayerKey] != true;
}

int missedPrayerCountForDay(DateTime day, DateTime today, int prayed) {
  if (!dateOnly(day).isBefore(dateOnly(today))) return 0;
  return prayerKeys.length - prayed;
}
