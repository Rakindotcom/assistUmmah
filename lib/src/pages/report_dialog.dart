import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../date_helpers.dart';
import '../display_formatters.dart';
import '../models.dart';

class ReportDialog extends StatefulWidget {
  const ReportDialog(
      {super.key,
      required this.repository,
      required this.title,
      required this.start,
      required this.end});
  final AppRepository repository;
  final String title;
  final DateTime start;
  final DateTime end;

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  late Future<ReportSummary> _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _report =
        widget.repository.buildReport(start: widget.start, end: widget.end);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: FutureBuilder<ReportSummary>(
          future: _report,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('রিপোর্ট লোড করা যায়নি। আবার চেষ্টা করুন।'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => setState(_load),
                    icon: const Icon(Icons.refresh),
                    label: const Text('আবার চেষ্টা করুন'),
                  ),
                ],
              ));
            }
            if (!widget.repository.canSync) {
              return const Text(
                  'রিপোর্ট দেখতে আপনার অ্যাকাউন্টে সাইন ইন করুন।');
            }
            final summary = snapshot.data ?? ReportSummary.empty;
            return SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${compactDateLabel(widget.start)} - ${compactDateLabel(widget.end)}'),
                const SizedBox(height: 14),
                _ReportRow(
                    label: 'নির্বাচিত দিন', value: banglaNumber(summary.days)),
                _ReportRow(
                  label: 'নামাজ লগড দিন',
                  value: banglaNumber(summary.prayerLoggedDays),
                ),
                _ReportRow(
                  label: 'পড়া হয়েছে',
                  value: banglaNumber(summary.totalPrayed),
                ),
                _ReportRow(
                    label: 'জামাত', value: banglaNumber(summary.totalJamaat)),
                _ReportRow(
                  label: 'মিসড (চিহ্নিত)',
                  value: banglaNumber(summary.totalMissed),
                ),
                _ReportRow(
                  label: 'কাযা আদায়',
                  value: banglaNumber(summary.totalMadeUp),
                ),
                _ReportRow(
                  label: 'হিসাব নেই (লগড দিনে)',
                  value: banglaNumber(summary.totalUnlogged),
                ),
                const Divider(),
                _ReportRow(
                  label: 'গ্রোথের হিসাব রাখা দিন',
                  value: banglaNumber(summary.growthLoggedDays),
                ),
                _ReportRow(
                  label: 'ইমান গড়',
                  value: summary.growthLoggedDays == 0
                      ? 'হিসাব নেই'
                      : '${banglaNumber(summary.averageIman)}%',
                ),
                _ReportRow(
                  label: 'লাইফ গড়',
                  value: summary.growthLoggedDays == 0
                      ? 'হিসাব নেই'
                      : '${banglaNumber(summary.averageLife)}%',
                ),
                _ReportRow(
                  label: 'ওভারঅল গড়',
                  value: summary.growthLoggedDays == 0
                      ? 'হিসাব নেই'
                      : '${banglaNumber(summary.averageOverall)}%',
                ),
              ],
            ));
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('বন্ধ'))
        ],
      );
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
