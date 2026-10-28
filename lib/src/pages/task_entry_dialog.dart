import 'package:flutter/material.dart';

import '../app_calendar_delegate.dart';
import '../date_helpers.dart';
import '../models.dart';

/// Keeps the draft in the dialog until the repository confirms the write.
class TaskEntryDialog extends StatefulWidget {
  const TaskEntryDialog({
    super.key,
    required this.section,
    required this.day,
    required this.onSave,
  });

  final String section;
  final DateTime day;
  final Future<void> Function(String text, TaskRepeat? repeat, DateTime date)
      onSave;

  @override
  State<TaskEntryDialog> createState() => _TaskEntryDialogState();
}

class _TaskEntryDialogState extends State<TaskEntryDialog> {
  final _text = TextEditingController();
  TaskRepeat? _repeat;
  late DateTime _selectedDate = dateOnly(widget.day);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      calendarDelegate: AppCalendarDelegate(Localizations.localeOf(context)),
      context: context,
      initialDate: _selectedDate,
      firstDate: dateOnly(widget.day),
      lastDate: DateTime(widget.day.year + 10, 12, 31),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'কাজের নাম লিখুন');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(text, _repeat, _selectedDate);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'কাজ সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: const Text('নতুন কাজ যোগ করুন'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _text,
                  autofocus: true,
                  enabled: !_saving,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 200,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: widget.section == 'mustDo'
                        ? 'অবশ্যই করতে হবে'
                        : 'করা ভালো',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TaskRepeat?>(
                  isExpanded: true,
                  initialValue: _repeat,
                  decoration: const InputDecoration(labelText: 'পুনরাবৃত্তি'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('একবার')),
                    DropdownMenuItem(
                        value: TaskRepeat.daily, child: Text('প্রতিদিন')),
                    DropdownMenuItem(
                        value: TaskRepeat.weekly, child: Text('প্রতি সপ্তাহে')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _repeat = value),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _chooseDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('তারিখ: ${compactDateLabel(_selectedDate)}'),
                ),
                if (_repeat == TaskRepeat.weekly)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        '${compactDateLabel(_selectedDate)} তারিখের বারেই প্রতি সপ্তাহে যোগ হবে'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'সংরক্ষণ হচ্ছে…' : 'যোগ করুন'),
            ),
          ],
        ),
      );
}
