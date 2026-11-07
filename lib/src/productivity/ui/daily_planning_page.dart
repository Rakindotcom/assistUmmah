import 'package:flutter/material.dart';

import '../data/daily_planning_repository.dart';
import '../domain/calendar_day.dart';
import '../domain/daily_task_planner.dart';
import '../domain/experience_options.dart';
import '../domain/planning_time_zone.dart';
import 'experience_strings.dart';

class DailyPlanningPage extends StatefulWidget {
  const DailyPlanningPage({
    super.key,
    required this.repository,
    required this.day,
    required this.options,
  });
  final DailyPlanningRepository repository;
  final CalendarDay day;
  final ExperienceOptions options;
  @override
  State<DailyPlanningPage> createState() => _DailyPlanningPageState();
}

class _DailyPlanningPageState extends State<DailyPlanningPage> {
  DailyPlanReview? _review;
  bool _loading = true, _applying = false, _needsRefresh = false;
  String? _error;
  int _epoch = 0;
  ExperienceStrings get strings => ExperienceStrings(widget.options.language);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_applying) return;
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
      _needsRefresh = false;
    });
    try {
      final review = await widget.repository.preview(widget.day);
      if (!mounted || epoch != _epoch) return;
      setState(() => _review = review);
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _review = null;
        _error = strings.text('Could not build a plan. Try again.',
            'পরিকল্পনা তৈরি করা যায়নি। আবার চেষ্টা করুন।');
      });
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final review = _review;
    if (_loading || _applying || _needsRefresh || review == null) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await widget.repository.apply(review);
      if (mounted) Navigator.pop(context, true);
    } on DailyPlanningFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _needsRefresh = true;
        _error = switch (error.code) {
          'stale-plan' => strings.text(
              'Tasks, events or preferences changed. Refresh the plan to review the latest times.',
              'কাজ, ইভেন্ট বা পছন্দ বদলেছে। নতুন সময়গুলো দেখতে পরিকল্পনা আবার তৈরি করুন।'),
          'expired-plan' => strings.text(
              'Some proposed times have passed. Refresh the plan.',
              'প্রস্তাবিত কিছু সময় পেরিয়ে গেছে। পরিকল্পনা আবার তৈরি করুন।'),
          _ => strings.text('Could not save this plan. Refresh and try again.',
              'পরিকল্পনা সংরক্ষণ করা যায়নি। আবার তৈরি করে চেষ্টা করুন।'),
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = strings.text(
            'Could not save the plan. Your tasks are kept.',
            'পরিকল্পনা সংরক্ষণ করা যায়নি। আপনার কাজগুলো রাখা আছে।'));
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  String _reason(DailyTaskUnscheduledReason reason) => switch (reason) {
        DailyTaskUnscheduledReason.unsupportedRecurrence => strings.text(
            'Set a recurring occurrence time manually.',
            'পুনরাবৃত্ত কাজের সময় নিজে নির্ধারণ করুন।'),
        DailyTaskUnscheduledReason.missingEstimate => strings.text(
            'Add a time estimate first.', 'আগে সময়ের অনুমান যোগ করুন।'),
        DailyTaskUnscheduledReason.waiting => strings.text(
            'This task is waiting.', 'কাজটি অপেক্ষমাণ অবস্থায় আছে।'),
        DailyTaskUnscheduledReason.blocked =>
          strings.text('This task is blocked.', 'কাজটি আটকে আছে।'),
        DailyTaskUnscheduledReason.incompleteDependencies => strings.text(
            'Finish its prerequisites first.',
            'আগে এর পূর্বশর্তগুলো শেষ করুন।'),
        DailyTaskUnscheduledReason.incompleteSubtasks => strings.text(
            'Plan its unfinished subtasks first.',
            'আগে অসমাপ্ত উপকাজগুলোর পরিকল্পনা করুন।'),
        DailyTaskUnscheduledReason.startsAfterDay =>
          strings.text('Its start date is later.', 'কাজের শুরুর তারিখ পরে।'),
        DailyTaskUnscheduledReason.nonworkingDay => strings.text(
            'This is a nonworking day in your preferences.',
            'আপনার পছন্দ অনুযায়ী এই দিনটি কাজের দিন নয়।'),
        DailyTaskUnscheduledReason.workdayEnded => strings.text(
            'No working time remains on this day.',
            'এই দিনে কাজের সময় আর বাকি নেই।'),
        DailyTaskUnscheduledReason.deadlinePassed => strings.text(
            'Its deadline has passed. Review the deadline.',
            'শেষ সময় পেরিয়ে গেছে। সময়সীমা পর্যালোচনা করুন।'),
        DailyTaskUnscheduledReason.deadlineCannotFit => strings.text(
            'It cannot fit before its deadline.',
            'শেষ সময়ের আগে কাজটির জন্য যথেষ্ট সময় নেই।'),
        DailyTaskUnscheduledReason.capacityExceeded => strings.text(
            'It exceeds the remaining daily capacity.',
            'দিনের অবশিষ্ট কাজের সামর্থ্যে এটি ধরছে না।'),
        DailyTaskUnscheduledReason.noContiguousTime => strings.text(
            'No uninterrupted gap is long enough.',
            'যথেষ্ট দীর্ঘ একটানা ফাঁকা সময় নেই।'),
        DailyTaskUnscheduledReason.planningLimitReached => strings.text(
            'Review this plan before scheduling more tasks.',
            'আরও কাজের সময় দেওয়ার আগে এই পরিকল্পনা পর্যালোচনা করুন।'),
      };

  @override
  Widget build(BuildContext context) {
    final review = _review;
    String time(DateTime instant) {
      final local = PlanningTimeZone.inZone(
          instant, review?.options.timeZone ?? widget.options.timeZone);
      final value = MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay.fromDateTime(local),
          alwaysUse24HourFormat:
              review?.options.use24HourClock ?? widget.options.use24HourClock);
      return strings.number('$value ${local.timeZoneName}');
    }

    String workspace(String id) {
      final module =
          WorkspaceModule.values.where((value) => value.name == id).firstOrNull;
      return module == null ? id : strings.module(module);
    }

    return Scaffold(
        appBar: AppBar(
            title: Text(strings.text('Plan this day', 'দিনের পরিকল্পনা')),
            actions: [
              IconButton(
                  tooltip: strings.text('Refresh plan', 'আবার পরিকল্পনা তৈরি'),
                  onPressed: _loading || _applying ? null : _load,
                  icon: const Icon(Icons.refresh)),
            ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(20), children: [
                Text(
                    '${strings.number(widget.day.toString())} · ${review?.options.timeZone ?? widget.options.timeZone}',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(strings.text('Review suggested times before applying.',
                    'সংরক্ষণের আগে প্রস্তাবিত সময়গুলো দেখুন।')),
                const SizedBox(height: 8),
                Text(
                    strings.text(
                        'Uses local events and task estimates. Existing commitments stay in place.',
                        'স্থানীয় ইভেন্ট ও কাজের সময়-অনুমান ব্যবহার করে। আগের নির্ধারিত সময় বহাল থাকবে।'),
                    style: Theme.of(context).textTheme.bodySmall),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  TextButton(
                      onPressed: _applying ? null : _load,
                      child: Text(
                          strings.text('Refresh plan', 'আবার পরিকল্পনা তৈরি'))),
                ],
                if (review != null) ...[
                  const SizedBox(height: 20),
                  Text(
                      strings.text(
                          '${strings.number(review.plan.plannedMinutes)} min proposed · ${strings.number(review.plan.remainingCapacityMinutes)} min available',
                          '${strings.number(review.plan.plannedMinutes)} মিনিটের প্রস্তাব · বাকি ${strings.number(review.plan.remainingCapacityMinutes)} মিনিট'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (review.plan.placements.isEmpty)
                    Text(strings.text('No new time blocks to schedule.',
                        'সময় নির্ধারণের জন্য নতুন কোনো কাজ নেই।')),
                  for (final placement in review.plan.placements)
                    Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      review.tasksById[placement.taskId]!.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${time(placement.start)}–${time(placement.end)}'),
                                  Text(
                                      strings.text(
                                          '${strings.number(placement.end.difference(placement.start).inMinutes)} min · ${workspace(review.tasksById[placement.taskId]!.workspaceId)} · ${strings.priority(review.tasksById[placement.taskId]!.priority)}',
                                          '${strings.number(placement.end.difference(placement.start).inMinutes)} মিনিট · ${workspace(review.tasksById[placement.taskId]!.workspaceId)} · ${strings.priority(review.tasksById[placement.taskId]!.priority)}'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ]))),
                  if (review.plan.unscheduled.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                        strings.text(
                            'Needs your attention', 'আপনার সিদ্ধান্ত দরকার'),
                        style: Theme.of(context).textTheme.titleMedium),
                    for (final item in review.plan.unscheduled)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.info_outline),
                          title: Text(review.tasksById[item.taskId]!.title),
                          subtitle: Text(_reason(item.reason))),
                  ],
                ],
              ]),
        bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton(
                onPressed: _loading ||
                        _applying ||
                        _needsRefresh ||
                        review == null ||
                        review.plan.placements.isEmpty
                    ? null
                    : _apply,
                child: Text(_applying
                    ? strings.text('Saving…', 'সংরক্ষণ হচ্ছে…')
                    : strings.text('Apply plan', 'পরিকল্পনা সংরক্ষণ')))));
  }
}
