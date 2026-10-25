import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../models.dart';
import '../widgets/page_frame.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final Map<String, List<ContactItem>> _contacts = {'message': [], 'call': []};

  String _activeSection = 'message';
  bool _loading = true;
  Future<void> _writeQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final contacts = _contacts[_activeSection] ?? [];

    return Stack(
      children: [
        PageFrame(
          title: 'জরুরি যোগাযোগ',
          subtitle: 'যাদের সাথে নিয়মিত যোগাযোগ রাখা দরকার',
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                ChoiceChip(
                  label: const Text('মেসেজ দিলেও হবে'),
                  selected: _activeSection == 'message',
                  onSelected: (_) => setState(() => _activeSection = 'message'),
                ),
                ChoiceChip(
                  label: const Text('কল করতে হবে'),
                  selected: _activeSection == 'call',
                  onSelected: (_) => setState(() => _activeSection = 'call'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _activeSection == 'message'
                              ? Icons.chat_bubble_outline
                              : Icons.call_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _activeSection == 'message'
                                ? 'যাদের মেসেজ দিলেও হবে'
                                : 'যাদের কল করতে হবে',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Chip(label: Text('${contacts.length}')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (contacts.isEmpty)
                      const EmptyState(
                        icon: Icons.person_add_alt_1_outlined,
                        message: 'এখনো কোন যোগাযোগ যোগ করা হয়নি',
                      )
                    else
                      ...contacts.map(
                        (contact) => _ContactTile(
                          contact: contact,
                          onDelete: () => _deleteContact(contact.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 22,
          bottom: 22,
          child: FloatingActionButton.extended(
            onPressed: _showAddContactDialog,
            icon: const Icon(Icons.add),
            label: const Text('যোগাযোগ'),
          ),
        ),
      ],
    );
  }

  Future<void> _load() async {
    try {
      final data = await widget.repository.loadContacts();
      final contacts = asStringMap(data?['contacts']);
      _contacts['message'] = _parseContacts(contacts['message']);
      _contacts['call'] = _parseContacts(contacts['call']);
    } catch (_) {
      _showMessage('যোগাযোগ লোড করতে সমস্যা হয়েছে');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showAddContactDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('নতুন যোগাযোগ যোগ করুন'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: _activeSection == 'message'
                  ? 'মেসেজ যোগাযোগের নাম'
                  : 'কল যোগাযোগের নাম',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('যোগ করুন'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (!mounted) return;

    final name = result?.trim() ?? '';
    if (name.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final contact = ContactItem(
      id: '${now.microsecondsSinceEpoch}',
      name: name,
      createdAt: now.toIso8601String(),
    );

    final section = _activeSection;
    await _runChange((contacts) {
      if (!contacts[section]!.any((item) => item.id == contact.id)) {
        contacts[section]!.add(contact);
      }
    });
  }

  Future<void> _deleteContact(String id) async {
    final section = _activeSection;
    await _runChange((contacts) {
      contacts[section] =
          contacts[section]!.where((item) => item.id != id).toList();
    });
  }

  Future<void> _runChange(
    void Function(Map<String, List<ContactItem>> contacts) apply,
  ) {
    if (!widget.repository.canSync) {
      setState(() => apply(_contacts));
      return Future<void>.value();
    }

    final operation = _writeQueue.then((_) async {
      final data = await widget.repository.changeContacts(apply);
      if (mounted && data != null) {
        final contacts = asStringMap(data['contacts']);
        setState(() {
          _contacts['message'] = _parseContacts(contacts['message']);
          _contacts['call'] = _parseContacts(contacts['call']);
        });
      }
    });
    _writeQueue = operation.catchError((Object _) {
      _showMessage('যোগাযোগ সিঙ্ক করতে সমস্যা হয়েছে');
    });
    return _writeQueue;
  }

  List<ContactItem> _parseContacts(Object? raw) {
    if (raw is Iterable) {
      return raw
          .map(ContactItem.fromMap)
          .where((item) => item.name.isNotEmpty)
          .toList();
    }
    return [];
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onDelete});

  final ContactItem contact;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(Icons.person_outline),
          ),
          title: Text(contact.name),
          trailing: IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            color: Colors.red.shade500,
          ),
        ),
      ),
    );
  }
}
