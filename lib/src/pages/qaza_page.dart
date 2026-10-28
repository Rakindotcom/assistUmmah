import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../display_formatters.dart';
import '../date_helpers.dart';
import '../models.dart';
import '../qaza_backlog.dart';
import '../widgets/page_frame.dart';

class QazaPage extends StatefulWidget {
  const QazaPage({super.key, required this.repository, this.today});

  final AppRepository repository;
  final DateTime? today;

  @override
  State<QazaPage> createState() => _QazaPageState();
}

class _QazaPageState extends State<QazaPage> with WidgetsBindingObserver {
  List<QazaEntry> _entries = const [];
  final Set<String> _busyIds = {};
  bool _loading = true;
  bool _loadFailed = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant QazaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository.uid != widget.repository.uid) {
      _entries = const [];
      _busyIds.clear();
      _load();
    } else if (oldWidget.today != widget.today) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _busyIds.isEmpty) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _entries.length;
    final showEntries = count > 0;
    final showStatus = _loading || _loadFailed;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width >= 820 ? 32 : 20,
            24,
            MediaQuery.sizeOf(context).width >= 820 ? 32 : 20,
            96),
        itemCount: 1 + (showEntries ? count + (showStatus ? 1 : 0) : 1),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _bounded(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'কাযার তালিকা',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'সব তারিখে মিস হিসেবে চিহ্নিত নামাজ',
                  ),
                  if (showEntries) ...[
                    const SizedBox(height: 12),
                    Text('${banglaNumber(count)} ওয়াক্ত কাযা বাকি'),
                  ],
                  const SizedBox(height: 18),
                ],
              ),
            );
          }
          if (!showEntries || (showStatus && index == 1)) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_loadFailed) {
              return _bounded(
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.sync_problem_outlined),
                    title: Text(showEntries
                        ? 'নতুন তালিকা লোড করা যায়নি'
                        : 'কাযার তালিকা লোড করা যায়নি'),
                    trailing: TextButton(
                      onPressed: _load,
                      child: const Text('রিট্রাই'),
                    ),
                  ),
                ),
              );
            }
            return _bounded(
              EmptyState(
                  icon: Icons.check_circle_outline,
                  message: widget.repository.canSync
                      ? 'কোনো মিসড নামাজ চিহ্নিত নেই'
                      : 'সব দিনের কাযা দেখতে সাইন ইন করুন'),
            );
          }

          final entry = _entries[index - 1 - (showStatus ? 1 : 0)];
          final date = DateTime.parse(entry.date);
          final busy = _busyIds.contains(entry.id);
          return _bounded(
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    title:
                        Text(prayerLabels[entry.prayerKey] ?? entry.prayerKey),
                    subtitle: Text(compactDateLabel(date)),
                    trailing: busy
                        ? const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _loading ? null : () => _complete(entry),
                            child: const Text('কাযা সম্পন্ন'),
                          ),
                  ),
                )),
          );
        },
      ),
    );
  }

  Widget _bounded(Widget child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: SizedBox(width: double.infinity, child: child),
        ),
      );

  Future<void> _load() async {
    final requestId = ++_requestId;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final backlog = await widget.repository.loadQazaBacklog(
        today: widget.today ?? dateOnly(),
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _entries = backlog.entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _complete(QazaEntry entry) async {
    if (_busyIds.contains(entry.id)) return;
    final repository = widget.repository;
    setState(() => _busyIds.add(entry.id));
    try {
      final completed = await repository.completeQazaIfMissed(
        date: entry.date,
        prayerKey: entry.prayerKey,
      );
      if (!mounted || widget.repository.uid != repository.uid) return;
      ++_requestId; // Ignore a refresh that started before this write.
      setState(() {
        _entries = [
          for (final item in _entries)
            if (item.id != entry.id) item,
        ];
        _loading = false;
      });
      if (!completed) {
        _showMessage('এই নামাজের অবস্থা অন্য কোথাও বদলে গেছে');
        await _load();
      }
    } catch (_) {
      if (mounted && widget.repository.uid == repository.uid) {
        _showMessage('কাযা সম্পন্ন করা যায়নি। আবার চেষ্টা করুন।');
      }
    } finally {
      if (mounted && widget.repository.uid == repository.uid) {
        setState(() => _busyIds.remove(entry.id));
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
