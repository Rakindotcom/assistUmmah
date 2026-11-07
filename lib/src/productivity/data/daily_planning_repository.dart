import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/records.dart';
import '../domain/calendar_day.dart';
import '../domain/calendar_event.dart';
import '../domain/daily_task_planner.dart';
import '../domain/experience_options.dart';
import '../domain/task.dart';
import 'experience_repository.dart';
import 'productivity_database.dart';
import 'task_repository.dart';

class DailyPlanningFailure implements Exception {
  const DailyPlanningFailure(this.code);
  final String code;
}

/// A proposal tied to the account and exact local data the owner reviewed.
class DailyPlanReview {
  DailyPlanReview._(this.ownerId, this.day, this.options, this.plan,
      this.preparedAt, this._fingerprint, Iterable<ProductivityTask> tasks)
      : tasksById = Map.unmodifiable({for (final task in tasks) task.id: task});
  final String ownerId;
  final CalendarDay day;
  final ExperienceOptions options;
  final DailyTaskPlan plan;
  final DateTime preparedAt;
  final Map<String, ProductivityTask> tasksById;
  final String _fingerprint;
}

class DailyPlanningRepository {
  DailyPlanningRepository(this.database, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final ProductivityDatabase database;
  final DateTime Function() _clock;
  static const _kinds = {
    RecordKind.task,
    RecordKind.taskOccurrence,
    RecordKind.calendarEvent,
    RecordKind.workspace,
    RecordKind.project,
    RecordKind.goal,
    RecordKind.milestone,
  };

  Future<DailyPlanReview> preview(CalendarDay day) async {
    final now = _clock().toUtc();
    late DailyPlanReview review;
    await database.changeRecords(
        kinds: _kinds,
        plan: (records) {
          final optionsRecord = records
              .where((record) =>
                  record.kind == RecordKind.workspace &&
                  record.id == ExperienceRepository.optionsId &&
                  !record.deleted)
              .firstOrNull;
          if (optionsRecord == null) {
            throw const DailyPlanningFailure('setup-incomplete');
          }
          final options = ExperienceOptions.fromRecord(optionsRecord);
          final tasks = records
              .where(
                  (record) => record.kind == RecordKind.task && !record.deleted)
              .map(ProductivityTask.fromRecord)
              .toList(growable: false);
          final events = records
              .where((record) =>
                  record.kind == RecordKind.calendarEvent && !record.deleted)
              .map(CalendarEvent.fromRecord);
          final completedOccurrences = records
              .where((record) =>
                  record.kind == RecordKind.taskOccurrence &&
                  !record.deleted &&
                  record.fields['status'] == TaskStatus.completed.name)
              .map((record) => record.id)
              .toSet();
          // Leave time to review before the first proposed slot starts.
          final plan = DailyTaskPlanner.plan(
              tasks: tasks,
              events: events,
              options: options,
              day: day,
              isCompleted: (task) =>
                  task.recurrence != null &&
                  completedOccurrences
                      .contains(TaskRepository.occurrenceId(task.id, day)),
              now: now.add(const Duration(minutes: 5)));
          review = DailyPlanReview._(database.uid, day, options, plan, now,
              _fingerprint(records), tasks);
          return [];
        });
    return review;
  }

  /// Rechecks the complete planning context and commits every placement with
  /// its audit/outbox entry in one transaction. No stale partial plan is saved.
  Future<void> apply(DailyPlanReview review) async {
    if (review.ownerId != database.uid) {
      throw const DailyPlanningFailure('different-account');
    }
    if (review.plan.placements.isEmpty || review.plan.placements.length > 500) {
      throw const DailyPlanningFailure('empty-plan');
    }
    await database.changeRecords(
        kinds: _kinds,
        plan: (records) {
          final now = _clock().toUtc();
          if (now.isBefore(review.preparedAt) ||
              now.difference(review.preparedAt) > const Duration(minutes: 15) ||
              review.plan.placements
                  .any((placement) => placement.start.isBefore(now))) {
            throw const DailyPlanningFailure('expired-plan');
          }
          if (_fingerprint(records) != review._fingerprint) {
            throw const DailyPlanningFailure('stale-plan');
          }
          final validator = TaskRepository(database);
          final mutations = <RecordMutation>[];
          for (final placement in review.plan.placements) {
            final previous = records
                .where((record) =>
                    record.kind == RecordKind.task &&
                    record.id == placement.taskId &&
                    !record.deleted)
                .firstOrNull;
            if (previous == null) {
              throw const DailyPlanningFailure('stale-plan');
            }
            final patch = <String, Object?>{
              'scheduledAt': placement.start.toUtc().toIso8601String(),
              'scheduledDay': null,
              'inbox': false,
            };
            final fields = {...previous.fields, ...patch};
            validator.validateTaskConflictCandidate(
                WorkspaceRecord(
                    ownerId: previous.ownerId,
                    kind: previous.kind,
                    id: previous.id,
                    fields: fields,
                    clocks: {
                      for (final key in fields.keys)
                        key:
                            previous.clocks[key] ?? previous.clocks.values.first
                    },
                    modifiedAtMillis: previous.modifiedAtMillis),
                records);
            mutations.add(RecordMutation(
                kind: RecordKind.task,
                id: previous.id,
                workspaceId: previous.workspaceId,
                patch: patch));
          }
          return mutations;
        });
  }

  String _fingerprint(List<WorkspaceRecord> records) {
    final relevant = records
        .where((record) =>
            record.kind != RecordKind.workspace ||
            record.id == ExperienceRepository.optionsId)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sha256
        .convert(utf8.encode(canonicalJson([
          for (final record in relevant)
            {
              'key': record.key,
              'fields': record.fields,
              'clocks': {
                for (final entry in record.clocks.entries)
                  entry.key: entry.value.toJson()
              }
            }
        ])))
        .toString();
  }
}
