import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../display_formatters.dart';
import '../date_helpers.dart';
import '../progress_trends.dart';
import '../widgets/page_frame.dart';
import 'calendar_page.dart';

class TrendsPage extends StatefulWidget {
  const TrendsPage({
    super.key,
    required this.repository,
    required this.today,
  });

  final AppRepository repository;
  final DateTime today;

  @override
  State<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<TrendsPage> with WidgetsBindingObserver {
  ProgressTrends? _trends;
  bool _loading = true;
  bool _failed = false;
  int _visibleDays = 30;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant TrendsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository.uid != widget.repository.uid ||
        dateKey(oldWidget.today) != dateKey(widget.today)) {
      _trends = null;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.canSync) {
      return const Center(
        child: Text('ট্রেন্ড দেখতে সাইন ইন করুন'),
      );
    }
    if (_loading && _trends == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed && _trends == null) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ট্রেন্ড লোড করা যায়নি'),
                TextButton(onPressed: _load, child: const Text('রিট্রাই')),
              ],
            ),
          ),
        ),
      );
    }

    final trends = _trends!;
    final start = trends.days.length - _visibleDays;
    final visible = trends.days.skip(start).toList();
    final window = trends.window(start, _visibleDays);
    final recent = trends.window(trends.days.length - 8, 7);
    final previous = trends.window(trends.days.length - 15, 7);
    return RefreshIndicator(
      onRefresh: _load,
      child: PageFrame(
        title: 'অগ্রগতির ট্রেন্ড',
        subtitle: 'লগ করা দিনগুলোর পরিবর্তন দেখুন',
        children: [
          if (_failed)
            Card(
              child: ListTile(
                title: const Text('নতুন তথ্য লোড করা যায়নি'),
                trailing:
                    TextButton(onPressed: _load, child: const Text('রিট্রাই')),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('৭ দিন'),
                selected: _visibleDays == 7,
                onSelected: (_) => setState(() => _visibleDays = 7),
              ),
              ChoiceChip(
                label: const Text('৩০ দিন'),
                selected: _visibleDays == 30,
                onSelected: (_) => setState(() => _visibleDays = 30),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('শেষ ${banglaNumber(_visibleDays)} দিনের সারাংশ',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                      'নামাজের হিসাব: ${banglaNumber(window.prayerLoggedDays)}/${banglaNumber(window.days)} দিন'),
                  Text(
                      'পড়া বা কাযা: ${banglaNumber(window.completedPrayers)} ওয়াক্ত • '
                      'মিস হিসেবে চিহ্নিত: ${banglaNumber(window.missedPrayers)}'),
                  Text(
                      'গ্রোথের হিসাব: ${banglaNumber(window.growthLoggedDays)}/${banglaNumber(window.days)} দিন'),
                  Text(window.averageGrowth == null
                      ? 'গ্রোথের গড়: হিসাব নেই'
                      : 'গ্রোথের গড়: ${banglaNumber(window.averageGrowth!)}% (লগ করা দিনগুলোর মধ্যে)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('গতকাল পর্যন্ত শেষ ৭ দিন বনাম আগের ৭ দিন',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_comparison(recent, previous)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('দিনভিত্তিক হিসাব',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text(
              'প্রতি ঘরে উপরে নামাজ (সম্পন্ন/৫), নিচে গ্রোথ। — মানে হিসাব নেই।'),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final scaler = MediaQuery.textScalerOf(context);
            final columns =
                ((constraints.maxWidth + 8) / (scaler.scale(64) + 8))
                    .floor()
                    .clamp(2, 7);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visible.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent: scaler.scale(52) + 24,
              ),
              itemBuilder: (context, index) => _DayCell(
                day: visible[index],
                onTap: () => _showDay(visible[index]),
              ),
            );
          }),
          const SizedBox(height: 10),
          const Text('খালি দিনকে শূন্য অগ্রগতি হিসেবে ধরা হয়নি।'),
        ],
      ),
    );
  }

  String _comparison(TrendWindow recent, TrendWindow previous) {
    if (recent.growthLoggedDays < 3 || previous.growthLoggedDays < 3) {
      return 'তুলনা করতে প্রতি সপ্তাহে অন্তত ৩ দিনের গ্রোথ হিসাব দরকার। '
          'এখন ${banglaNumber(recent.growthLoggedDays)} ও ${banglaNumber(previous.growthLoggedDays)} দিন আছে।';
    }
    final change = recent.averageGrowth! - previous.averageGrowth!;
    final direction = change > 0
        ? 'বেড়েছে'
        : change < 0
            ? 'কমেছে'
            : 'একই আছে';
    return 'গ্রোথের গড় ${banglaNumber(change.abs())} পয়েন্ট $direction '
        '(${banglaNumber(previous.averageGrowth!)}% থেকে ${banglaNumber(recent.averageGrowth!)}%)। '
        'প্রতি সপ্তাহে ${banglaNumber(previous.growthLoggedDays)} ও '
        '${banglaNumber(recent.growthLoggedDays)} দিন লগ করা হয়েছে।';
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    if (mounted) setState(() => _loading = true);
    try {
      final trends = await widget.repository.loadProgressTrends(
        end: widget.today,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _trends = trends;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _showDay(ProgressDay day) async {
    final openCalendar = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(compactDateLabel(day.date),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(day.prayerLogged
                  ? '${banglaNumber(day.prayer.prayed)} পড়া • ${banglaNumber(day.prayer.madeUp)} কাযা • '
                      '${banglaNumber(day.prayer.missed)} মিস • ${banglaNumber(day.prayer.unlogged)} হিসাব নেই'
                  : 'নামাজের হিসাব নেই'),
              Text(day.growthLogged
                  ? 'ইমান ${banglaNumber(day.imanScore!)}% • লাইফ ${banglaNumber(day.lifeScore!)}% • '
                      'ওভারঅল ${banglaNumber(day.overallScore!)}%'
                  : 'গ্রোথের হিসাব নেই'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('দিনপঞ্জিতে খুলুন'),
              ),
            ],
          ),
        ),
      ),
    );
    if (openCalendar == true && mounted) await _openCalendar(day.date);
  }

  Future<void> _openCalendar(DateTime day) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(compactDateLabel(day))),
          body: CalendarPage(
            repository: widget.repository,
            today: widget.today,
            initialDay: day,
          ),
        ),
      ),
    );
    if (mounted) await _load();
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.onTap});

  final ProgressDay day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final score = day.overallScore;
    final theme = Theme.of(context);
    final color = score == null
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.primaryContainer.withValues(
            alpha: 0.2 + score / 125,
          );
    return Semantics(
      button: true,
      label: '${compactDateLabel(day.date)}: '
          '${day.prayerLogged ? '${banglaNumber(day.completedPrayers)} ওয়াক্ত সম্পন্ন' : 'নামাজের হিসাব নেই'}, '
          '${score == null ? 'গ্রোথের হিসাব নেই' : 'গ্রোথ ${banglaNumber(score)} শতাংশ'}',
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ExcludeSemantics(
                child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                    '${banglaNumber(day.date.day)}/${banglaNumber(day.date.month)}',
                    style: theme.textTheme.labelMedium,
                    maxLines: 1),
                Text(
                    day.prayerLogged
                        ? '${banglaNumber(day.completedPrayers)}/৫'
                        : '—',
                    style: theme.textTheme.labelMedium,
                    maxLines: 1),
                Text(score == null ? '—' : '${banglaNumber(score)}%',
                    style: theme.textTheme.labelMedium, maxLines: 1),
              ],
            )),
          ),
        ),
      ),
    );
  }
}
