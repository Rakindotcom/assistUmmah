import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../display_formatters.dart';
import '../domain/experience_options.dart';
import '../domain/task.dart';

class ExperienceStrings {
  const ExperienceStrings(this.language);
  factory ExperienceStrings.of(BuildContext context) =>
      ExperienceStrings(Localizations.localeOf(context).languageCode);
  final String language;
  bool get bengali => language == 'bn';
  String text(String english, String bangla) => bengali ? bangla : english;
  String number(Object value) => bengali ? banglaDigits('$value') : '$value';
  String date(DateTime value) =>
      number(DateFormat.yMMMd(bengali ? 'bn' : 'en').format(value));
  String time(DateTime value, {required bool use24HourClock}) => number(
      DateFormat(use24HourClock ? 'HH:mm' : 'h:mm a', bengali ? 'bn' : 'en')
          .format(value));
  static String asciiDigits(String value) => value.replaceAllMapped(
      RegExp('[০-৯]'), (match) => '০১২৩৪৫৬৭৮৯'.indexOf(match[0]!).toString());
  static int? parseInteger(String value) => int.tryParse(asciiDigits(value));
  String module(WorkspaceModule module) => switch (module) {
        WorkspaceModule.personal => text('Personal', 'ব্যক্তিগত'),
        WorkspaceModule.work => text('Work', 'কাজ'),
        WorkspaceModule.study => text('Study', 'পড়াশোনা'),
        WorkspaceModule.wellness => text('Wellness', 'সুস্থতা'),
        WorkspaceModule.faith => text('Faith', 'ঈমান ও আমল'),
      };
  String status(TaskStatus status) => switch (status) {
        TaskStatus.notStarted => text('Not started', 'শুরু হয়নি'),
        TaskStatus.inProgress => text('In progress', 'চলছে'),
        TaskStatus.waiting => text('Waiting', 'অপেক্ষায়'),
        TaskStatus.blocked => text('Blocked', 'আটকে আছে'),
        TaskStatus.completed => text('Completed', 'সম্পন্ন'),
      };
  String priority(TaskPriority priority) => switch (priority) {
        TaskPriority.none => text('No priority', 'অগ্রাধিকার নেই'),
        TaskPriority.low => text('Low', 'কম'),
        TaskPriority.normal => text('Normal', 'সাধারণ'),
        TaskPriority.high => text('High', 'বেশি'),
        TaskPriority.urgent => text('Urgent', 'জরুরি'),
      };
  String taskError(String code) => switch (code) {
        'parent-completed' => text(
            'Reopen the parent task before adding or reopening a subtask.',
            'উপকাজ যোগ করতে বা আবার শুরু করতে আগে মূল কাজটি আবার চালু করুন।'),
        'circular-reference' => text(
            'This creates a circular dependency. Choose another task.',
            'এতে কাজগুলো একে অন্যের ওপর আটকে যাবে। অন্য কাজ বেছে নিন।'),
        'dependencies-open' => text('Complete the prerequisite tasks first.',
            'আগে নির্ভরশীল কাজগুলো সম্পন্ন করুন।'),
        'subtasks-open' =>
          text('Complete the subtasks first.', 'আগে উপকাজগুলো সম্পন্ন করুন।'),
        'choose-occurrence' => text(
            'Open a date to complete this recurring task.',
            'পুনরাবৃত্ত কাজটি সম্পন্ন করতে একটি দিন খুলুন।'),
        'different-workspace' => text(
            'Linked items must be in the same workspace.',
            'সংযুক্ত বিষয়গুলো একই কর্মপরিসরে থাকতে হবে।'),
        'in-trash' => text('Restore the linked task from trash first.',
            'আগে সংযুক্ত কাজটি ট্র্যাশ থেকে ফিরিয়ে আনুন।'),
        'not-scheduled' => text('This series does not run on that date.',
            'এই দিনে কাজটি নির্ধারিত নেই।'),
        'already-exists' =>
          text('This item already exists.', 'বিষয়টি আগে থেকেই আছে।'),
        _ => text('Could not save. Your draft is kept; try again.',
            'সংরক্ষণ হয়নি। আপনার লেখা রাখা আছে; আবার চেষ্টা করুন।'),
      };
}
