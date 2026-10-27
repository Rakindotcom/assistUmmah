import 'package:flutter/material.dart';

class TextEntryDialog extends StatefulWidget {
  const TextEntryDialog(
      {super.key,
      required this.title,
      required this.label,
      required this.submitLabel,
      required this.onSave,
      this.initialValue = '',
      this.errorMessage = 'সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'});
  final String title;
  final String label;
  final String submitLabel;
  final String initialValue;
  final String errorMessage;
  final Future<void> Function(String value) onSave;

  @override
  State<TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<TextEntryDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initialValue);
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSave(_controller.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8),
            child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                        controller: _controller,
                        autofocus: true,
                        enabled: !_saving,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _save(),
                        decoration: InputDecoration(labelText: widget.label),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'নাম লিখুন'
                                : null),
                    if (_failed)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(widget.errorMessage,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                  ],
                ))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('বাতিল')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'সংরক্ষণ হচ্ছে…' : widget.submitLabel)),
        ],
      ));
}
