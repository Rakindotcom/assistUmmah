import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../date_helpers.dart';
import '../growth_progress.dart';
import '../models.dart';
import '../widgets/page_frame.dart';
import 'growth_checklist_editor.dart';

class GrowthPage extends StatefulWidget {
  const GrowthPage({
    super.key,
    required this.repository,
    required this.day,
    this.historical = false,
    this.refreshToken = 0,
    this.onSaved,
    this.onSaveError,
    this.onOpenQuran,
    this.onOpenDhikr,
  });

  final AppRepository repository;
  final DateTime day;
  final bool historical;
  final int refreshToken;
  final VoidCallback? onSaved;
  final ValueChanged<String>? onSaveError;
  final VoidCallback? onOpenQuran;
  final VoidCallback? onOpenDhikr;

  @override
  State<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends State<GrowthPage> {
  String _userType = 'student';
  Map<String, bool> _iman = defaultChecklistMap(imanChecklist);
  Map<String, bool> _life = defaultChecklistMap(lifeChecklists['student']!);
  GrowthChecklistConfig _config = GrowthChecklistConfig.defaults();
  List<ChecklistItem> _imanItems = imanChecklist;
  List<ChecklistItem> _lifeItems = lifeChecklists['student']!;
  Map<String, dynamic>? _prayerDocument;
  bool _prayerLinked = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _savingConfig = false;
  int _loadId = 0;
  int _mutationRevision = 0;
  int _confirmedRevision = 0;
  int _pendingSaves = 0;
  Future<void> _writeQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GrowthPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged = oldWidget.repository.uid != widget.repository.uid ||
        dateKey(oldWidget.day) != dateKey(widget.day);
    if (identityChanged ||
        (oldWidget.refreshToken != widget.refreshToken &&
            _mutationRevision == _confirmedRevision)) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('গ্রোথের তথ্য লোড করা যায়নি'),
                TextButton(onPressed: _load, child: const Text('রিট্রাই')),
              ],
            ),
          ),
        ),
      );
    }

    final visibleIman = linkedImanValues(_iman, _prayerLinked, _prayerDocument);
    final imanScore = checklistScore(visibleIman, _imanItems);
    final lifeScore = checklistScore(_life, _lifeItems);
    final overallScore = ((imanScore + lifeScore) / 2).round();

    return PageFrame(
      title: 'গ্রোথ চেকলিস্ট',
      subtitle: widget.historical
          ? '${compactDateLabel(widget.day)} দিনের হিসাব সংশোধন করুন'
          : 'ইমান ও দৈনন্দিন জীবনের ছোট আমলগুলো প্রতিদিন হিসাব করুন',
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
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      label: Text(entry.value),
                      selected: _userType == entry.key,
                      onSelected:
                          _savingConfig ? null : (_) => _setUserType(entry.key),
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
        if (_mutationRevision > _confirmedRevision) ...[
          Semantics(
            liveRegion: true,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_pendingSaves > 0
                        ? 'পরিবর্তন সংরক্ষণ হচ্ছে…'
                        : 'পরিবর্তন সংরক্ষিত হয়নি'),
                    if (_pendingSaves == 0) ...[
                      const SizedBox(height: 8),
                      const Text(
                          'এই পৃষ্ঠায় পরিবর্তন রাখা আছে। আবার চেষ্টা করুন।'),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _savingConfig ? null : _save,
                        icon: const Icon(Icons.refresh),
                        label: const Text('আবার সংরক্ষণ করুন'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_imanItems.any((item) => item.key == 'prayer')) ...[
          Card(
            child: SwitchListTile(
              title: const Text('নামাজের হিসাবের সাথে যুক্ত'),
              subtitle: const Text(
                  'পাঁচ ওয়াক্ত পড়া বা কাযা সম্পন্ন হলে চেকলিস্টে ধরা হবে'),
              value: _prayerLinked,
              onChanged: _savingConfig ? null : _setPrayerLinked,
            ),
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 720;
            final cards = [
              _ChecklistCard(
                title: 'ইমান চেকলিস্ট',
                score: imanScore,
                items: _imanItems,
                values: visibleIman,
                onChanged: _savingConfig
                    ? null
                    : (key, value) => _toggle('iman', key, value),
                onEdit: widget.historical || _savingConfig
                    ? null
                    : () => _editChecklist('iman'),
                linkedPrayer: _prayerLinked,
              ),
              _ChecklistCard(
                title: 'লাইফ চেকলিস্ট',
                score: lifeScore,
                items: _lifeItems,
                values: _life,
                onChanged: _savingConfig
                    ? null
                    : (key, value) => _toggle('life', key, value),
                onEdit: widget.historical || _savingConfig
                    ? null
                    : () => _editChecklist('life'),
                linkedPrayer: false,
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
        if (!widget.historical &&
            (widget.onOpenQuran != null || widget.onOpenDhikr != null)) ...[
          const SizedBox(height: 28),
          Text('আরও আমল', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (widget.onOpenQuran != null)
            Card(
                child: ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text('কুরআন রিডিং লক্ষ্য'),
                    subtitle: const Text('প্রতিদিনের পড়া ও অগ্রগতি দেখুন'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: widget.onOpenQuran)),
          const SizedBox(height: 12),
          if (widget.onOpenDhikr != null)
            Card(
                child: ListTile(
                    leading: const Icon(Icons.touch_app_outlined),
                    title: const Text('যিকিরের লক্ষ্য'),
                    subtitle: const Text('দৈনিক গণনা ও অগ্রগতি দেখুন'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: widget.onOpenDhikr)),
        ],
      ],
    );
  }

  Future<void> _load() async {
    final requestId = ++_loadId;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      await _writeQueue;
      final config = await widget.repository.loadGrowthChecklistConfig();
      final preferredType = await widget.repository.loadUserType();
      final data = await widget.repository.loadGrowth(dateKey(widget.day));
      final prayerDocument =
          await widget.repository.loadPrayerDocument(dateKey(widget.day));
      if (!mounted || requestId != _loadId) return;

      var userType =
          preferredType != null && userTypeLabels.containsKey(preferredType)
              ? preferredType
              : 'student';
      final growthData = asStringMap(data?['growthData']);
      final dailyUserType = data?['userType'] as String?;
      if (dailyUserType != null && userTypeLabels.containsKey(dailyUserType)) {
        userType = dailyUserType;
      }
      final prayerLinked = data == null && !widget.historical
          ? true
          : data?['prayerLinked'] == true;
      late final List<ChecklistItem> imanItems;
      late final List<ChecklistItem> lifeItems;
      if (widget.historical && data != null) {
        final snapshot = GrowthChecklistSnapshot.fromDocument(data);
        imanItems = snapshot.iman;
        lifeItems = snapshot.life;
      } else {
        imanItems = config.iman;
        lifeItems = config.lifeFor(userType);
      }
      setState(() {
        _config = config;
        _userType = userType;
        _prayerDocument = prayerDocument;
        _prayerLinked = prayerLinked;
        _imanItems = imanItems;
        _lifeItems = lifeItems;
        _iman = {
          ...defaultChecklistMap(imanItems),
          ...parseBoolMap(growthData['iman']),
        };
        _life = {
          ...defaultChecklistMap(lifeItems),
          ...parseBoolMap(growthData['life']),
        };
        _mutationRevision = 0;
        _confirmedRevision = 0;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _loadId) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _setUserType(String userType) async {
    if (_savingConfig) return;
    setState(() {
      final previousLife = _life;
      final nextItems = _config.lifeFor(userType);
      final nextLife = defaultChecklistMap(nextItems);
      for (final key in nextLife.keys) {
        nextLife[key] = previousLife[key] ?? false;
      }
      _userType = userType;
      _lifeItems = nextItems;
      _life = nextLife;
      _mutationRevision++;
    });
    await _save();
  }

  Future<void> _toggle(String category, String key, bool value) async {
    if (_savingConfig ||
        (category == 'iman' && key == 'prayer' && _prayerLinked)) {
      return;
    }
    setState(() {
      if (category == 'iman') {
        _iman[key] = value;
      } else {
        _life[key] = value;
      }
      _mutationRevision++;
    });
    await _save();
  }

  Future<bool> _save() async {
    final revision = _mutationRevision;
    final repository = widget.repository;
    final day = dateKey(widget.day);
    final historical = widget.historical;
    final prayerLinked = _prayerLinked;
    final userType = _userType;
    final iman = linkedImanValues(
        Map<String, bool>.of(_iman), prayerLinked, _prayerDocument);
    final life = Map<String, bool>.of(_life);
    final snapshot =
        GrowthChecklistSnapshot(iman: _imanItems, life: _lifeItems);
    setState(() => _pendingSaves++);
    final operation = _writeQueue.then((_) => repository.saveGrowth(
          date: day,
          userType: userType,
          iman: iman,
          life: life,
          checklistSnapshot: snapshot,
          prayerLinked: prayerLinked,
          updatePreferredType: !historical,
        ));
    _writeQueue = operation.catchError((Object _) {});
    try {
      await operation;
      if (mounted && revision > _confirmedRevision) {
        setState(() => _confirmedRevision = revision);
      }
      if (mounted) widget.onSaved?.call();
      return true;
    } catch (_) {
      const message = 'গ্রোথ ডেটা সিঙ্ক করতে সমস্যা হয়েছে';
      if (widget.onSaveError case final onSaveError?) {
        onSaveError(message);
      } else {
        _showMessage(message);
      }
      return false;
    } finally {
      if (mounted) setState(() => _pendingSaves--);
    }
  }

  Future<void> _setPrayerLinked(bool next) async {
    if (_savingConfig || next == _prayerLinked) return;
    final previous = _prayerLinked;
    final previousRevision = _mutationRevision;
    setState(() {
      _savingConfig = true;
      _prayerLinked = next;
      _mutationRevision++;
    });
    final saved = await _save();
    if (!mounted) return;
    setState(() {
      if (!saved) {
        _prayerLinked = previous;
        _mutationRevision = previousRevision;
      }
      _savingConfig = false;
    });
  }

  Future<void> _editChecklist(String category) async {
    if (_savingConfig) return;
    final items = category == 'iman' ? _imanItems : _lifeItems;
    final updated = await Navigator.of(context).push<List<ChecklistItem>>(
      MaterialPageRoute(
        builder: (_) => GrowthChecklistEditor(
          title: category == 'iman' ? 'ইমান চেকলিস্ট' : 'লাইফ চেকলিস্ট',
          initialItems: items,
          defaultItems: category == 'iman'
              ? imanChecklist
              : lifeChecklists[_userType] ?? lifeChecklists['student']!,
        ),
      ),
    );
    if (!mounted || updated == null || _sameItems(items, updated)) return;

    final nextConfig = _config.withItems(category, _userType, updated);
    final nextImanItems = category == 'iman' ? updated : _imanItems;
    final nextLifeItems = category == 'life' ? updated : _lifeItems;
    final nextIman = {
      for (final item in nextImanItems) item.key: _iman[item.key] ?? false,
    };
    final savedIman =
        linkedImanValues(nextIman, _prayerLinked, _prayerDocument);
    final nextLife = {
      for (final item in nextLifeItems) item.key: _life[item.key] ?? false,
    };
    final repository = widget.repository;
    final day = dateKey(widget.day);
    final userType = _userType;
    final prayerLinked = _prayerLinked;
    final revision = _mutationRevision;
    setState(() => _savingConfig = true);
    final operation = _writeQueue.then((_) => repository.saveGrowth(
          date: day,
          userType: userType,
          iman: savedIman,
          life: nextLife,
          prayerLinked: prayerLinked,
          checklistSnapshot: GrowthChecklistSnapshot(
            iman: nextImanItems,
            life: nextLifeItems,
          ),
          checklistConfig: nextConfig,
        ));
    _writeQueue = operation.catchError((Object _) {});
    try {
      await operation;
      if (!mounted) return;
      setState(() {
        _config = nextConfig;
        _imanItems = nextImanItems;
        _lifeItems = nextLifeItems;
        _iman = nextIman;
        _life = nextLife;
        if (revision > _confirmedRevision) _confirmedRevision = revision;
      });
      widget.onSaved?.call();
    } catch (_) {
      _showMessage('চেকলিস্ট সংরক্ষণ করা যায়নি');
    } finally {
      if (mounted) setState(() => _savingConfig = false);
    }
  }

  bool _sameItems(List<ChecklistItem> a, List<ChecklistItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].key != b[i].key || a[i].label != b[i].label) return false;
    }
    return true;
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
    required this.onChanged,
    required this.onEdit,
    required this.linkedPrayer,
  });

  final String title;
  final int score;
  final List<ChecklistItem> items;
  final Map<String, bool> values;
  final void Function(String key, bool value)? onChanged;
  final VoidCallback? onEdit;
  final bool linkedPrayer;

  @override
  Widget build(BuildContext context) {
    return Card(
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
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                ScoreBadge(score: score),
                if (onEdit != null)
                  IconButton(
                    tooltip: '$title সম্পাদনা',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map(
              (item) => CheckboxListTile(
                value: values[item.key] == true,
                onChanged:
                    onChanged == null || (linkedPrayer && item.key == 'prayer')
                        ? null
                        : (value) => onChanged!(item.key, value ?? false),
                title: Text(item.label,
                    style: Theme.of(context).textTheme.bodyLarge),
                subtitle: linkedPrayer && item.key == 'prayer'
                    ? const Text('নামাজ ট্র্যাকিং থেকে আপডেট হয়')
                    : null,
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
