import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../date_helpers.dart';
import '../models.dart';
import '../widgets/page_frame.dart';

class GrowthPage extends StatefulWidget {
  const GrowthPage({super.key, required this.repository, required this.day});

  final AppRepository repository;
  final DateTime day;

  @override
  State<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends State<GrowthPage> {
  String _userType = 'student';
  Map<String, bool> _iman = defaultChecklistMap(imanChecklist);
  Map<String, bool> _life = defaultChecklistMap(lifeChecklists['student']!);
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

    final lifeItems = lifeChecklists[_userType] ?? lifeChecklists['student']!;
    final imanScore = checklistScore(_iman, imanChecklist);
    final lifeScore = checklistScore(_life, lifeItems);
    final overallScore = ((imanScore + lifeScore) / 2).round();

    return PageFrame(
      title: 'গ্রোথ চেকলিস্ট',
      subtitle: 'ইমান ও দৈনন্দিন জীবনের ছোট আমলগুলো প্রতিদিন হিসাব করুন',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: userTypeLabels.entries.map((entry) {
                    return ChoiceChip(
                      label: Text(entry.value),
                      selected: _userType == entry.key,
                      onSelected: (_) => _setUserType(entry.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _ScoreColumn(label: 'ইমান', score: imanScore),
                    ),
                    Expanded(
                      child: _ScoreColumn(label: 'লাইফ', score: lifeScore),
                    ),
                    Expanded(
                      child: _ScoreColumn(label: 'ওভারঅল', score: overallScore),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 720;
            final cards = [
              _ChecklistCard(
                title: 'ইমান চেকলিস্ট',
                score: imanScore,
                items: imanChecklist,
                values: _iman,
                color: const Color(0xFFECFDF5),
                onChanged: (key, value) => _toggle('iman', key, value),
              ),
              _ChecklistCard(
                title: 'লাইফ চেকলিস্ট',
                score: lifeScore,
                items: lifeItems,
                values: _life,
                color: const Color(0xFFEFF6FF),
                onChanged: (key, value) => _toggle('life', key, value),
              ),
            ];

            if (!wide) {
              return Column(
                children: [cards[0], const SizedBox(height: 16), cards[1]],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 16),
                Expanded(child: cards[1]),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _load() async {
    try {
      final preferredType = await widget.repository.loadUserType();
      if (preferredType != null && userTypeLabels.containsKey(preferredType)) {
        _userType = preferredType;
        _life = defaultChecklistMap(lifeChecklists[_userType]!);
      }

      final data = await widget.repository.loadGrowth(dateKey(widget.day));
      final growthData = asStringMap(data?['growthData']);
      final dailyUserType = data?['userType'] as String?;

      if (dailyUserType != null && userTypeLabels.containsKey(dailyUserType)) {
        _userType = dailyUserType;
      }

      _iman = {
        ...defaultChecklistMap(imanChecklist),
        ...parseBoolMap(growthData['iman']),
      };
      _life = {
        ...defaultChecklistMap(
          lifeChecklists[_userType] ?? lifeChecklists['student']!,
        ),
        ...parseBoolMap(growthData['life']),
      };
    } catch (_) {
      _showMessage('গ্রোথ ডেটা লোড করতে সমস্যা হয়েছে');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _setUserType(String userType) async {
    setState(() {
      final previousLife = _life;
      final nextItems = lifeChecklists[userType] ?? lifeChecklists['student']!;
      final nextLife = defaultChecklistMap(nextItems);
      for (final key in nextLife.keys) {
        nextLife[key] = previousLife[key] ?? false;
      }
      _userType = userType;
      _life = nextLife;
    });
    await _save();
  }

  Future<void> _toggle(String category, String key, bool value) async {
    setState(() {
      if (category == 'iman') {
        _iman[key] = value;
      } else {
        _life[key] = value;
      }
    });
    await _save();
  }

  Future<void> _save() async {
    final userType = _userType;
    final iman = Map<String, bool>.of(_iman);
    final life = Map<String, bool>.of(_life);
    final operation = _writeQueue.then((_) => widget.repository.saveGrowth(
        date: dateKey(widget.day),
        userType: userType,
        iman: iman,
        life: life,
      ));
    _writeQueue = operation.catchError((Object _) {
      _showMessage('গ্রোথ ডেটা সিঙ্ক করতে সমস্যা হয়েছে');
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

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({required this.label, required this.score});

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ScoreBadge(score: score),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({
    required this.title,
    required this.score,
    required this.items,
    required this.values,
    required this.color,
    required this.onChanged,
  });

  final String title;
  final int score;
  final List<ChecklistItem> items;
  final Map<String, bool> values;
  final Color color;
  final void Function(String key, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                ScoreBadge(score: score),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map(
              (item) => CheckboxListTile(
                value: values[item.key] == true,
                onChanged: (value) => onChanged(item.key, value ?? false),
                title: Text(item.label),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
