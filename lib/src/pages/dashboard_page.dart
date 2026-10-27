import 'dart:async';

import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../display_formatters.dart';
import '../app_theme.dart';
import '../dashboard_summary.dart';
import '../date_helpers.dart';
import '../models.dart';
import '../prayer_times_service.dart';
import '../widgets/page_frame.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.repository,
    required this.day,
    required this.refreshToken,
    required this.onOpenTasks,
    required this.onOpenPrayer,
    required this.onOpenGrowth,
  });

  final AppRepository repository;
  final DateTime day;
  final int refreshToken;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenPrayer;
  final VoidCallback onOpenGrowth;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardSummary? _summary;
  bool _loading = true;
  bool _tasksAvailable = true;
  bool _prayerAvailable = true;
  bool _growthAvailable = true;
  PrayerTimeEntry? _nextPrayer;
  Timer? _prayerTimer;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        dateKey(oldWidget.day) != dateKey(widget.day) ||
        oldWidget.repository.uid != widget.repository.uid) {
      _load();
    }
  }

  @override
  void dispose() {
    _prayerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _summary == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final summary = _summary!;
    final hasError = !_tasksAvailable || !_prayerAvailable || !_growthAvailable;
    final growthScoreAvailable =
        _growthAvailable && (!summary.growthLinked || _prayerAvailable);
    final action = _nextAction(summary);

    return RefreshIndicator(
      onRefresh: _load,
      child: PageFrame(
        title: 'আজকের সারাংশ',
        subtitle: compactDateLabel(widget.day),
        children: [
          if (_nextPrayer != null) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: Text(
                  'পরবর্তী নামাজ: ${prayerLabels[_nextPrayer!.key]}',
                ),
                subtitle: const Text('আপনার নির্বাচিত স্থান ও পদ্ধতি অনুযায়ী'),
                trailing: Text(
                  formatPrayerTime(_nextPrayer!.time),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                onTap: widget.onOpenPrayer,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (hasError) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.sync_problem_outlined),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('কিছু তথ্য লোড হয়নি। আবার চেষ্টা করুন।'),
                    ),
                    TextButton(onPressed: _load, child: const Text('রিট্রাই')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            color: const Color(0xFF173F35),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'আজকের ফোকাস',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: const Color(0xFFBCD9CA)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    action.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(action.description,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFFD4E7DC))),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: action.open,
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF173F35)),
                    icon: const Icon(Icons.arrow_forward),
                    iconAlignment: IconAlignment.end,
                    label: Text(action.buttonLabel),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Semantics(
              header: true,
              child: Text('আজকের অগ্রগতি',
                  style: Theme.of(context).textTheme.titleLarge)),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final cards = [
              _OverviewCard(
                icon: Icons.check_circle_outline,
                title: 'কাজ',
                value: _tasksAvailable
                    ? summary.totalTasks == 0
                        ? 'আজকের তালিকা খালি'
                        : '${banglaNumber(summary.completedTasks)}/${banglaNumber(summary.totalTasks)} সম্পন্ন'
                    : 'তথ্য পাওয়া যায়নি',
                detail: _tasksAvailable
                    ? summary.totalTasks == 0
                        ? 'আজকের প্রথম কাজটি যোগ করুন'
                        : '${banglaNumber(summary.mustDoRemaining)} জরুরি • ${banglaNumber(summary.goodToDoRemaining)} অন্যান্য বাকি'
                    : 'আবার চেষ্টা করুন',
                onTap: widget.onOpenTasks,
                progress: _tasksAvailable && summary.totalTasks > 0
                    ? summary.completedTasks / summary.totalTasks
                    : null,
              ),
              _OverviewCard(
                icon: Icons.mosque_outlined,
                title: 'নামাজ',
                value: _prayerAvailable
                    ? summary.prayersLogged
                        ? '${banglaNumber(summary.prayersCompleted)}/৫ সময়মতো পড়া হয়েছে'
                        : 'এখনো লগ করা হয়নি'
                    : 'তথ্য পাওয়া যায়নি',
                detail: _prayerAvailable && summary.prayersLogged
                    ? '${banglaNumber(summary.prayersMissed)} মিস • '
                        '${banglaNumber(summary.prayersMadeUp)} কাযা • '
                        '${banglaNumber(summary.prayersUnlogged)} হিসাব নেই • '
                        '${banglaNumber(summary.jamaatCount)} জামাতে'
                    : 'আজকের হিসাব খুলুন',
                onTap: widget.onOpenPrayer,
                progress: _prayerAvailable && summary.prayersLogged
                    ? (summary.prayersCompleted + summary.prayersMadeUp) / 5
                    : null,
              ),
              _OverviewCard(
                icon: Icons.trending_up,
                title: 'গ্রোথ',
                value: growthScoreAvailable
                    ? summary.growthLogged
                        ? '${banglaNumber(summary.overallScore)}% সম্পন্ন'
                        : 'এখনো লগ করা হয়নি'
                    : 'তথ্য পাওয়া যায়নি',
                detail: growthScoreAvailable && summary.growthLogged
                    ? 'ইমান ${banglaNumber(summary.imanScore)}% • লাইফ ${banglaNumber(summary.lifeScore)}%'
                    : 'চেকলিস্ট খুলুন',
                onTap: widget.onOpenGrowth,
                progress: growthScoreAvailable && summary.growthLogged
                    ? summary.overallScore / 100
                    : null,
              ),
            ];
            if (constraints.maxWidth >= 720) {
              return IntrinsicHeight(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(child: cards[i]),
                    ]
                  ]));
            }
            return Column(children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cards[i],
              ]
            ]);
          }),
        ],
      ),
    );
  }

  _DashboardAction _nextAction(DashboardSummary summary) {
    if (!_tasksAvailable || !_prayerAvailable || !_growthAvailable) {
      return _DashboardAction(
        title: 'আজকের তথ্য আবার লোড করুন',
        description: 'সম্পূর্ণ সারাংশ দেখতে সিঙ্ক করুন।',
        buttonLabel: 'রিট্রাই',
        open: _load,
      );
    }
    if (summary.mustDoRemaining > 0) {
      return _DashboardAction(
        title: summary.nextMustDo ?? 'জরুরি কাজ শেষ করুন',
        description:
            '${banglaNumber(summary.mustDoRemaining)}টি জরুরি কাজ বাকি আছে।',
        buttonLabel: 'কাজ দেখুন',
        open: widget.onOpenTasks,
      );
    }
    if (summary.prayersUnlogged > 0) {
      return _DashboardAction(
        title: 'নামাজের হিসাব আপডেট করুন',
        description:
            '${banglaNumber(summary.prayersUnlogged)} ওয়াক্তের অবস্থা এখনো লেখা হয়নি।',
        buttonLabel: 'নামাজ দেখুন',
        open: widget.onOpenPrayer,
      );
    }
    if (summary.prayersMissed > 0) {
      return _DashboardAction(
        title: 'মিসড নামাজের কাযা আদায় করুন',
        description:
            '${banglaNumber(summary.prayersMissed)} ওয়াক্ত মিস হিসেবে চিহ্নিত।',
        buttonLabel: 'নামাজ দেখুন',
        open: widget.onOpenPrayer,
      );
    }
    if (!summary.growthLogged || summary.overallScore < 100) {
      return _DashboardAction(
        title: 'গ্রোথ চেকলিস্ট পূরণ করুন',
        description: 'আজকের ইমান ও লাইফ লক্ষ্যগুলো দেখে নিন।',
        buttonLabel: 'গ্রোথ দেখুন',
        open: widget.onOpenGrowth,
      );
    }
    if (summary.goodToDoRemaining > 0) {
      return _DashboardAction(
        title: 'আরও কিছু কাজ বাকি আছে',
        description:
            '${banglaNumber(summary.goodToDoRemaining)}টি অন্যান্য কাজ করতে পারেন।',
        buttonLabel: 'কাজ দেখুন',
        open: widget.onOpenTasks,
      );
    }
    return _DashboardAction(
      title: 'আজকের সব লক্ষ্য সম্পন্ন',
      description: 'আপনার আজকের হিসাব সম্পূর্ণ হয়েছে।',
      buttonLabel: 'নামাজের হিসাব',
      open: widget.onOpenPrayer,
    );
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    if (_summary == null && mounted) {
      setState(() => _loading = true);
    }
    final date = dateKey(widget.day);
    final tasksFuture = _read(() => widget.repository.loadTasksForDate(date));
    final prayerFuture =
        _read(() => widget.repository.loadPrayerDocument(date));
    final growthFuture = _read(() => widget.repository.loadGrowth(date));
    final nextPrayerFuture = _read(() async {
      final config = await PrayerTimeStore(widget.repository.uid).load();
      return config == null
          ? null
          : PrayerTimeService.nextPrayer(config, DateTime.now());
    });
    final tasks = await tasksFuture;
    final prayer = await prayerFuture;
    final growth = await growthFuture;
    final nextPrayer = await nextPrayerFuture;

    if (!mounted || requestId != _requestId) return;
    setState(() {
      _summary = DashboardSummary.fromDocuments(
        tasks: tasks.value,
        prayer: prayer.value,
        growth: growth.value,
      );
      _tasksAvailable = tasks.ok;
      _prayerAvailable = prayer.ok;
      _growthAvailable = growth.ok;
      _nextPrayer = nextPrayer.value;
      _loading = false;
    });
    _prayerTimer?.cancel();
    final upcoming = _nextPrayer;
    if (upcoming != null) {
      final delay =
          upcoming.time.difference(DateTime.now()) + const Duration(seconds: 1);
      if (delay > Duration.zero) _prayerTimer = Timer(delay, _load);
    }
  }

  Future<_ReadResult<T>> _read<T>(Future<T> Function() load) async {
    try {
      return _ReadResult(await load(), true);
    } catch (_) {
      return _ReadResult(null, false);
    }
  }
}

class _ReadResult<T> {
  const _ReadResult(this.value, this.ok);

  final T? value;
  final bool ok;
}

class _DashboardAction {
  const _DashboardAction({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.open,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback open;
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.onTap,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final VoidCallback onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: AppColors.brand, size: 22)),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(title,
                        style: Theme.of(context).textTheme.titleMedium)),
                const Icon(Icons.arrow_forward,
                    size: 18, color: AppColors.muted),
              ]),
              const SizedBox(height: 20),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(detail,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.muted)),
              if (progress != null) ...[
                const SizedBox(height: 16),
                ExcludeSemantics(
                    child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0),
                        borderRadius: BorderRadius.circular(8))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
