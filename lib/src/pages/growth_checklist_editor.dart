import 'package:flutter/material.dart';

import '../models.dart';

class GrowthChecklistEditor extends StatefulWidget {
  const GrowthChecklistEditor({
    super.key,
    required this.title,
    required this.initialItems,
    required this.defaultItems,
  });

  final String title;
  final List<ChecklistItem> initialItems;
  final List<ChecklistItem> defaultItems;

  @override
  State<GrowthChecklistEditor> createState() => _GrowthChecklistEditorState();
}

class _GrowthChecklistEditorState extends State<GrowthChecklistEditor> {
  late final List<ChecklistItem> _items = List.of(widget.initialItems);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'ডিফল্ট ফিরিয়ে আনুন',
            onPressed: _restoreDefaults,
            icon: const Icon(Icons.restore),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(List.of(_items)),
            child: const Text('সংরক্ষণ'),
          ),
        ],
      ),
      body: SafeArea(
        child: _items.isEmpty
            ? const Center(child: Text('চেকলিস্ট খালি। নতুন আইটেম যোগ করুন।'))
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: _items.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final item = _items.removeAt(oldIndex);
                    _items.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Card(
                    key: ValueKey(item.key),
                    child: ListTile(
                      title: Text(item.label),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'নাম পরিবর্তন',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(index),
                          ),
                          IconButton(
                            tooltip: 'আইটেম মুছুন',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                setState(() => _items.removeAt(index)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('আইটেম যোগ'),
      ),
    );
  }

  Future<void> _restoreDefaults() async {
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ডিফল্ট চেকলিস্ট ফিরিয়ে আনবেন?'),
        content: const Text('এই তালিকার বর্তমান পরিবর্তনগুলো বদলে যাবে।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ফিরিয়ে আনুন'),
          ),
        ],
      ),
    );
    if (restore == true && mounted) {
      setState(() {
        _items
          ..clear()
          ..addAll(widget.defaultItems);
      });
    }
  }

  Future<void> _edit(int? index) async {
    var draft = index == null ? '' : _items[index].label;
    var error = '';
    final label = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title:
              Text(index == null ? 'আইটেম যোগ করুন' : 'আইটেমের নাম পরিবর্তন'),
          content: TextFormField(
            initialValue: draft,
            autofocus: true,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: 'আইটেমের নাম',
              errorText: error.isEmpty ? null : error,
            ),
            onChanged: (value) => draft = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () {
                final value = draft.trim();
                if (value.isEmpty) {
                  updateDialog(() => error = 'নাম লিখুন');
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: const Text('ঠিক আছে'),
            ),
          ],
        ),
      ),
    );
    if (label == null || !mounted) return;
    setState(() {
      if (index == null) {
        final base = DateTime.now().microsecondsSinceEpoch;
        var suffix = 0;
        var id = 'custom$base';
        while (_items.any((item) => item.key == id)) {
          suffix++;
          id = 'custom${base}_$suffix';
        }
        _items.add(ChecklistItem(id, label));
      } else {
        _items[index] = ChecklistItem(_items[index].key, label);
      }
    });
  }
}
