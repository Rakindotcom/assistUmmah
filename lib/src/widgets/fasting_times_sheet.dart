import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../date_helpers.dart';
import '../prayer_times_service.dart';

class FastingTimesSheet extends StatefulWidget {
  const FastingTimesSheet({super.key, required this.config, this.clock});
  final PrayerTimeConfig config;
  final DateTime Function()? clock;
  @override
  State<FastingTimesSheet> createState() => _FastingTimesSheetState();
}

class _FastingTimesSheetState extends State<FastingTimesSheet> {
  bool _tomorrow = false;
  @override
  Widget build(BuildContext context) {
    final now = tz.TZDateTime.from(widget.clock?.call() ?? DateTime.now(),
        PrayerTimeService.location(widget.config.timeZoneId));
    final day = DateTime(now.year, now.month, now.day + (_tomorrow ? 1 : 0));
    final schedule = PrayerTimeService.forDay(widget.config, day);
    final fajr = schedule.entries.first.time;
    final maghrib =
        schedule.entries.firstWhere((entry) => entry.key == 'maghrib').time;
    return SafeArea(
        child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('সাহরি-ইফতার',
                style: Theme.of(context).textTheme.headlineSmall),
            Text('${widget.config.placeName} · ${compactDateLabel(day)}'),
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: const Text('আজ'),
                  selected: !_tomorrow,
                  onSelected: (_) => setState(() => _tomorrow = false),
                  materialTapTargetSize: MaterialTapTargetSize.padded),
              ChoiceChip(
                  label: const Text('আগামীকাল'),
                  selected: _tomorrow,
                  onSelected: (_) => setState(() => _tomorrow = true),
                  materialTapTargetSize: MaterialTapTargetSize.padded),
            ]),
            const SizedBox(height: 16),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.nightlight_outlined),
                          const SizedBox(height: 8),
                          const Text('সাহরির শেষ সীমা · ফজর শুরু'),
                          Text(formatPrayerTime(fajr),
                              style: Theme.of(context).textTheme.headlineLarge),
                          const Divider(height: 28),
                          const Icon(Icons.wb_twilight_outlined),
                          const SizedBox(height: 8),
                          const Text('ইফতার · মাগরিব শুরু'),
                          Text(formatPrayerTime(maghrib),
                              style: Theme.of(context).textTheme.headlineLarge),
                        ]))),
            const SizedBox(height: 16),
            Text(
                '${prayerCalculationMethods[widget.config.method]} · ${widget.config.timeZoneId}'),
            const SizedBox(height: 6),
            const Text(
                'এগুলো আপনার নির্বাচিত স্থান, পদ্ধতি ও সময় সমন্বয় অনুযায়ী গণনা করা। স্থানীয় মসজিদ বা নির্ভরযোগ্য স্থানীয় সময়সূচির সঙ্গে মিলিয়ে নিন।'),
          ]),
    ));
  }
}
