import 'package:flutter/material.dart';

import '../display_formatters.dart';
import '../models.dart';
import '../prayer_alerts.dart';

class PrayerAlertCard extends StatelessWidget {
  const PrayerAlertCard({
    super.key,
    required this.settings,
    required this.locationReady,
    required this.busy,
    required this.permissionGranted,
    required this.exact,
    required this.scheduledCount,
    required this.onChanged,
    required this.onConfigureLocation,
  });

  final PrayerAlertSettings settings;
  final bool locationReady;
  final bool busy;
  final bool permissionGranted;
  final bool exact;
  final int scheduledCount;
  final void Function(PrayerAlertSettings next, bool requestPermission)
      onChanged;
  final VoidCallback onConfigureLocation;

  @override
  Widget build(BuildContext context) {
    final enabled = locationReady && !busy;
    final canChangeMaster = !busy && (locationReady || settings.enabled);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy) const LinearProgressIndicator(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('নামাজের সময়ের অ্যালার্ট'),
              subtitle: const Text('নির্বাচিত ওয়াক্তে ফোনে নোটিফিকেশন'),
              value: settings.enabled,
              onChanged: canChangeMaster
                  ? (value) => onChanged(
                        settings.copyWith(enabled: value),
                        value,
                      )
                  : null,
            ),
            if (!locationReady)
              TextButton.icon(
                onPressed: onConfigureLocation,
                icon: const Icon(Icons.place_outlined),
                label: const Text('আগে নামাজের সময় সেট করুন'),
              )
            else ...[
              const SizedBox(height: 4),
              const Text('যেসব নামাজে অ্যালার্ট চাই'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final key in prayerKeys)
                    FilterChip(
                      label: Text(prayerLabels[key] ?? key),
                      selected: settings.selectedPrayers[key] == true,
                      onSelected: enabled
                          ? (selected) => onChanged(
                                settings.copyWith(
                                  selectedPrayers: {
                                    ...settings.selectedPrayers,
                                    key: selected,
                                  },
                                ),
                                false,
                              )
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: settings.leadMinutes,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'অ্যালার্টের সময়'),
                onChanged: enabled
                    ? (value) {
                        if (value != null) {
                          onChanged(
                            settings.copyWith(leadMinutes: value),
                            false,
                          );
                        }
                      }
                    : null,
                items: [
                  for (final minutes in prayerAlertLeadOptions)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(minutes == 0
                          ? 'ওয়াক্তে'
                          : '${banglaNumber(minutes)} মিনিট আগে'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('নিঃশব্দ অ্যালার্ট'),
                subtitle: const Text('সাউন্ড ও ভাইব্রেশন বন্ধ'),
                value: settings.silent,
                onChanged: enabled
                    ? (value) => onChanged(
                          settings.copyWith(silent: value),
                          false,
                        )
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('নীরব সময়'),
                subtitle: const Text('এই সময়ের অ্যালার্ট বাদ দিন'),
                value: settings.quietEnabled,
                onChanged: enabled
                    ? (value) => onChanged(
                          settings.copyWith(quietEnabled: value),
                          false,
                        )
                    : null,
              ),
              if (settings.quietEnabled)
                Wrap(
                  spacing: 10,
                  children: [
                    TextButton(
                      onPressed: enabled
                          ? () => _chooseQuietTime(context, start: true)
                          : null,
                      child: Text(
                          'শুরু ${_formatMinute(context, settings.quietStartMinute)}'),
                    ),
                    TextButton(
                      onPressed: enabled
                          ? () => _chooseQuietTime(context, start: false)
                          : null,
                      child: Text(
                          'শেষ ${_formatMinute(context, settings.quietEndMinute)}'),
                    ),
                  ],
                ),
              if (settings.enabled) ...[
                const SizedBox(height: 8),
                if (!permissionGranted)
                  TextButton.icon(
                    onPressed: enabled ? () => onChanged(settings, true) : null,
                    icon: const Icon(Icons.notifications_off_outlined),
                    label: const Text('নোটিফিকেশন অনুমতি দিন'),
                  )
                else
                  Text(
                    '${banglaNumber(scheduledCount)}টি অ্যালার্ট সেট আছে • '
                    '${exact ? 'যথাসময়ে' : 'সময় আনুমানিক হতে পারে'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 4),
                Text(
                  '১০ দিনের অ্যালার্ট রাখা হয়। নতুন দিনের সময় যোগ করতে অ্যাপ খুলুন।',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _chooseQuietTime(
    BuildContext context, {
    required bool start,
  }) async {
    final previous =
        start ? settings.quietStartMinute : settings.quietEndMinute;
    final chosen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: previous ~/ 60, minute: previous % 60),
    );
    if (chosen == null) return;
    final minute = chosen.hour * 60 + chosen.minute;
    if (minute ==
        (start ? settings.quietEndMinute : settings.quietStartMinute)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('শুরু ও শেষ সময় আলাদা করুন।')),
        );
      }
      return;
    }
    onChanged(
      start
          ? settings.copyWith(quietStartMinute: minute)
          : settings.copyWith(quietEndMinute: minute),
      false,
    );
  }

  String _formatMinute(BuildContext context, int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);
}
