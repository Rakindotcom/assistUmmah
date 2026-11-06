import 'package:flutter/material.dart';

import '../notifications/task_reminder_controller.dart';
import 'experience_strings.dart';

class TaskReminderSettings extends StatelessWidget {
  const TaskReminderSettings(
      {super.key, required this.controller, required this.strings});
  final TaskReminderController controller;
  final ExperienceStrings strings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final delivery = controller.delivery;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title:
                  Text(strings.text('Task notifications', 'কাজের নোটিফিকেশন')),
              subtitle: Text(strings.text(
                  'Remind me on this device. Task titles appear in notifications.',
                  'এই ডিভাইসে মনে করিয়ে দিন। নোটিফিকেশনে কাজের নাম দেখা যাবে।')),
              value: controller.enabled,
              onChanged: !controller.ready || controller.working
                  ? null
                  : (value) => controller.setEnabled(value)),
          if (controller.working) const LinearProgressIndicator(),
          if (controller.permissionDenied) ...[
            Text(strings.text(
                'Notifications are blocked. Allow them in device settings, then try again.',
                'নোটিফিকেশন বন্ধ আছে। ডিভাইসের সেটিংসে অনুমতি দিয়ে আবার চেষ্টা করুন।')),
            TextButton(
                onPressed: controller.working
                    ? null
                    : () => controller.setEnabled(true),
                child: Text(strings.text(
                    'Enable notifications', 'নোটিফিকেশন চালু করুন'))),
          ],
          if (controller.enabled &&
              delivery != null &&
              !controller.permissionDenied) ...[
            Text(strings.text(
                'Next ${strings.number(delivery.scheduledCount)} reminders scheduled.',
                'পরবর্তী ${strings.number(delivery.scheduledCount)}টি রিমাইন্ডার নির্ধারিত আছে।')),
            if (delivery.deferredCount > 0)
              Text(strings.text(
                  '${strings.number(delivery.deferredCount)} reminders are not scheduled yet. Open the app regularly to schedule the next ones.',
                  'আরও ${strings.number(delivery.deferredCount)}টি রিমাইন্ডার এখনো নির্ধারিত হয়নি। পরেরগুলো চালু রাখতে অ্যাপটি নিয়মিত খুলুন।')),
            if (!delivery.exact && delivery.scheduledCount > 0)
              Text(strings.text(
                  'Exact alarms are unavailable. Android may deliver these reminders late.',
                  'সঠিক সময়ের অ্যালার্মের অনুমতি নেই। অ্যান্ড্রয়েডে রিমাইন্ডার কিছুটা দেরিতে আসতে পারে।')),
          ],
          if (controller.error != null)
            Text(strings.text(
                'Could not update reminders. Your tasks are saved. Try again.',
                'রিমাইন্ডার আপডেট হয়নি। কাজের তথ্য রাখা আছে। আবার চেষ্টা করুন।')),
          if (controller.enabled || controller.error != null)
            TextButton.icon(
                onPressed: controller.working ? null : controller.refresh,
                icon: const Icon(Icons.refresh),
                label: Text(strings.text(
                    'Refresh reminders', 'রিমাইন্ডার রিফ্রেশ করুন'))),
        ]);
      });
}
