import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../date_helpers.dart';
import '../daily_logic.dart';
import '../models.dart';
import '../widgets/page_frame.dart';

class PrayerPage extends StatefulWidget {
  const PrayerPage({super.key, required this.repository, required this.day});

  final AppRepository repository;
  final DateTime day;

  @override
  State<PrayerPage> createState() => _PrayerPageState();
}

class _PrayerPageState extends State<PrayerPage> {
  Map<String, PrayerStatus> _prayers = defaultPrayerMap();
  Map<String, bool> _qaza = {for (final key in prayerKeys) key: false};
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

    final prayed = _prayers.values.where((status) => status.prayed).length;
    final jamaat = _prayers.values.where((status) => status.jamaat).length;
    final missed = 5 - prayed;
    final pendingQaza = _qaza.entries.where((entry) => entry.value).toList();

    return PageFrame(
      title: 'নামাজ ট্র্যাকিং',
      subtitle: 'আজকের পাঁচ ওয়াক্ত নামাজ ও জামাতে পড়া ট্র্যাক করুন',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _StatTile(
                  label: 'পড়া হয়েছে',
                  value: prayed,
                  color: Colors.green,
                ),
                _StatTile(label: 'জামাত', value: jamaat, color: Colors.blue),
                _StatTile(label: 'বাকি', value: missed, color: Colors.red),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'আজকের নামাজ',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                ...prayerKeys.map((key) {
                  final status = _prayers[key] ??
                      const PrayerStatus(prayed: false, jamaat: false);
                  return _PrayerTile(
                    label: prayerLabels[key] ?? key,
                    status: status,
                    onPrayedChanged: (value) => _updatePrayer(
                      key,
                      status.copyWith(
                        prayed: value,
                        jamaat: value ? status.jamaat : false,
                      ),
                    ),
                    onJamaatChanged: status.prayed
                        ? (value) =>
                            _updatePrayer(key, status.copyWith(jamaat: value))
                        : null,
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'গতকালের কাযা',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                if (pendingQaza.isEmpty)
                  const EmptyState(
                    icon: Icons.check_circle_outline,
                    message: 'গতকালের কোন কাযা বাকি নেই',
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: pendingQaza.map((entry) {
                      return ActionChip(
                        avatar: const Icon(Icons.history_outlined),
                        label: Text('${prayerLabels[entry.key]} কাযা সম্পন্ন'),
                        onPressed: () => _completeQaza(entry.key),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _load() async {
    try {
      final todayDoc = await widget.repository.loadPrayerDocument(
        dateKey(widget.day),
      );
      final loadedPrayers = asStringMap(todayDoc?['prayers']);
      if (loadedPrayers.isNotEmpty) {
        _prayers = {
          for (final key in prayerKeys)
            key: PrayerStatus.fromMap(loadedPrayers[key]),
        };
      }

      final yesterdayKey = dateKey(
        DateTime(widget.day.year, widget.day.month, widget.day.day - 1),
      );
      final yesterdayDoc = await widget.repository.loadPrayerDocument(
        yesterdayKey,
      );
      final qazaCompletions = parseBoolMap(yesterdayDoc?['qazaCompletions']);
      final yesterdayPrayers = asStringMap(yesterdayDoc?['prayers']);

      _qaza = {
        for (final key in prayerKeys)
          key: isQazaPending(yesterdayPrayers, qazaCompletions, key),
      };
    } catch (_) {
      _showMessage('নামাজের ডেটা লোড করতে সমস্যা হয়েছে');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _updatePrayer(String key, PrayerStatus status) async {
    setState(() => _prayers[key] = status);
    final prayers = Map<String, PrayerStatus>.of(_prayers);
    final operation = _writeQueue.then((_) => widget.repository.savePrayer(
          date: dateKey(widget.day),
          prayers: prayers,
        ));
    _writeQueue = operation.catchError((Object _) {
      _showMessage('নামাজের ডেটা সিঙ্ক করতে সমস্যা হয়েছে');
    });
    await _writeQueue;
  }

  Future<void> _completeQaza(String key) async {
    setState(() => _qaza[key] = false);
    final operation = _writeQueue.then((_) => widget.repository.completeQaza(
        date: dateKey(
          DateTime(widget.day.year, widget.day.month, widget.day.day - 1),
        ),
        prayerKey: key,
      ));
    _writeQueue = operation.catchError((Object _) {
      _showMessage('কাযা আপডেট করতে সমস্যা হয়েছে');
    });
    await _writeQueue;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w900),
          ),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _PrayerTile extends StatelessWidget {
  const _PrayerTile({
    required this.label,
    required this.status,
    required this.onPrayedChanged,
    required this.onJamaatChanged,
  });

  final String label;
  final PrayerStatus status;
  final ValueChanged<bool> onPrayedChanged;
  final ValueChanged<bool>? onJamaatChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color:
            status.prayed ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Checkbox(
                value: status.prayed,
                onChanged: (value) => onPrayedChanged(value ?? false),
              ),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Text('জামাত'),
              Switch(value: status.jamaat, onChanged: onJamaatChanged),
            ],
          ),
        ),
      ),
    );
  }
}
