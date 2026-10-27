import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../display_formatters.dart';
import '../models.dart';
import '../widgets/page_frame.dart';
import '../widgets/load_failure_state.dart';
import '../widgets/text_entry_dialog.dart';
import '../widgets/status_badge.dart';

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
  bool _loadFailed = false;
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
    if (_loadFailed) {
      return LoadFailureState(title: 'যোগাযোগ লোড করা যায়নি', onRetry: _load);
    }

    final contacts = _contacts[_activeSection] ?? [];
    final wide = MediaQuery.sizeOf(context).width >= 820;

    return Stack(
      children: [
        PageFrame(
          title: 'জরুরি যোগাযোগ',
          subtitle: 'যাদের সাথে নিয়মিত যোগাযোগ রাখা দরকার',
          action: wide
              ? FilledButton.icon(
                  onPressed: _showAddContactDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('যোগাযোগ'))
              : null,
          children: [
            Wrap(
              alignment: WrapAlignment.start,
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
                        StatusBadge(
                            label: '${banglaNumber(contacts.length)} জন'),
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
        if (!wide)
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
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final data = await widget.repository.loadContacts();
      final contacts = asStringMap(data?['contacts']);
      _contacts['message'] = _parseContacts(contacts['message']);
      _contacts['call'] = _parseContacts(contacts['call']);
    } catch (_) {
      _loadFailed = true;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showAddContactDialog() async {
    final now = DateTime.now();
    final section = _activeSection;
    final uid = widget.repository.uid;
    await showDialog<void>(
      context: context,
      builder: (_) => TextEntryDialog(
          title: 'নতুন যোগাযোগ যোগ করুন',
          label: 'যোগাযোগের নাম',
          submitLabel: 'যোগ করুন',
          errorMessage: 'যোগাযোগ সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।',
          onSave: (name) async {
            if (!mounted || uid != widget.repository.uid) {
              throw StateError('Account changed');
            }
            final contact = ContactItem(
                id: '${now.microsecondsSinceEpoch}',
                name: name,
                createdAt: now.toIso8601String());
            await _runChange((contacts) {
              if (!contacts[section]!.any((item) => item.id == contact.id)) {
                contacts[section]!.add(contact);
              }
            });
          }),
    );
  }

  Future<void> _deleteContact(String id) async {
    final section = _activeSection;
    try {
      await _runChange((contacts) {
        contacts[section] =
            contacts[section]!.where((item) => item.id != id).toList();
      });
    } catch (_) {
      _showMessage('যোগাযোগ মুছে ফেলা যায়নি। আবার চেষ্টা করুন।');
    }
  }

  Future<void> _runChange(
    void Function(Map<String, List<ContactItem>> contacts) apply,
  ) {
    if (!widget.repository.canSync) {
      setState(() => apply(_contacts));
      return Future<void>.value();
    }

    final repository = widget.repository;
    final operation = _writeQueue.then((_) async {
      final data = await repository.changeContacts(apply);
      if (mounted && data != null && repository.uid == widget.repository.uid) {
        final contacts = asStringMap(data['contacts']);
        setState(() {
          _contacts['message'] = _parseContacts(contacts['message']);
          _contacts['call'] = _parseContacts(contacts['call']);
        });
      }
    });
    _writeQueue = operation.catchError((Object _) {});
    return operation;
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
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(Icons.person_outline),
          ),
          title: Text(contact.name),
          trailing: IconButton(
            tooltip: 'যোগাযোগ মুছুন',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
  }
}
