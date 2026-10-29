import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../display_formatters.dart';
import '../app_theme.dart';
import '../dashboard_summary.dart';
import '../date_helpers.dart';
import '../models.dart';
import '../dua_collection.dart';
import '../prayer_times_service.dart';
import '../widgets/home_prayer_card.dart';
import '../widgets/home_feature_grid.dart';
import '../widgets/fasting_times_sheet.dart';
import '../widgets/prayer_place_picker.dart';
import 'dua_library_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.repository,
    required this.day,
    required this.refreshToken,
    required this.onOpenTasks,
    required this.onOpenPrayer,
    required this.onOpenGrowth,
    required this.onOpenQuran,
    required this.onOpenDhikr,
    required this.onOpenCalendar,
    required this.onOpenDuas,
    required this.onOpenReports,
    this.onPrayerConfigChanged,
    this.active = true,
    this.clock,
  });

  final AppRepository repository;
  final DateTime day;
  final int refreshToken;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenPrayer;
  final VoidCallback onOpenGrowth;
  final VoidCallback onOpenQuran,
      onOpenDhikr,
      onOpenCalendar,
      onOpenDuas,
      onOpenReports;
  final VoidCallback? onPrayerConfigChanged;
  final bool active;
  final DateTime Function()? clock;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardSummary? _summary;
  bool _loading = true;
  bool _tasksAvailable = true;
  bool _prayerAvailable = true;
  bool _growthAvailable = true;
  PrayerTimeConfig? _prayerConfig;
  bool _timeConfigFailed = false;
  bool _configuring = false;
  Map<String, PrayerStatus> _prayerStatuses = {};
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
  Widget build(BuildContext context) {
    final summary = _summary ?? DashboardSummary.fromDocuments();
    final hasError = !_tasksAvailable || !_prayerAvailable || !_growthAvailable;
    final growthScoreAvailable =
        _growthAvailable && (!summary.growthLinked || _prayerAvailable);
    final action = _nextAction(summary);

    return RefreshIndicator(
      onRefresh: _load,
      child: SafeArea(
          top: false,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
            children: [
              Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                          header: true,
                          child: Text('আসসালামু আলাইকুম',
                              style: Theme.of(context).textTheme.titleLarge)),
                      const SizedBox(height: 4),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                                child: Text(fullBanglaDate(widget.day),
                                    style:
                                        Theme.of(context).textTheme.bodySmall)),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 150),
                                child: TextButton.icon(
                                    onPressed: _configuring
                                        ? null
                                        : _configureLocation,
                                    icon: const Icon(Icons.location_on_outlined,
                                        size: 17),
                                    label: Text(
                                        _prayerConfig?.placeName ??
                                            'স্থান বাছুন',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis))),
                          ]),
                      const SizedBox(height: 10),
                      HomePrayerCard(
                          config: _prayerConfig,
                          failed: _timeConfigFailed,
                          active: widget.active,
                          clock: widget.clock,
                          onOpen: widget.onOpenPrayer,
                          onConfigure: _configureLocation),
                      const SizedBox(height: 18),
                      HomeFeatureGrid(features: [
                        HomeFeature(
                            'prayer',
                            'নামাজের সময়',
                            Icons.mosque_outlined,
                            AppColors.brand,
                            widget.onOpenPrayer),
                        HomeFeature(
                            'quran',
                            'কুরআন রিডিং',
                            Icons.menu_book_outlined,
                            const Color(0xFF846121),
                            widget.onOpenQuran),
                        HomeFeature('tasbih', 'তসবিহ', Icons.touch_app_outlined,
                            const Color(0xFF5366A0), widget.onOpenDhikr),
                        HomeFeature(
                            'dua',
                            'দোয়া',
                            Icons.volunteer_activism_outlined,
                            const Color(0xFF996C3D),
                            widget.onOpenDuas),
                        HomeFeature(
                            'fasting',
                            'সাহরি-ইফতার',
                            Icons.nightlight_outlined,
                            const Color(0xFF6D5C96),
                            _openFasting),
                        HomeFeature(
                            'calendar',
                            'দিনপঞ্জি',
                            Icons.calendar_month_outlined,
                            AppColors.brand,
                            widget.onOpenCalendar),
                        HomeFeature(
                            'tasks',
                            'আজকের কাজ',
                            Icons.task_alt_outlined,
                            const Color(0xFF467E9A),
                            widget.onOpenTasks),
                        HomeFeature('growth', 'গ্রোথ', Icons.spa_outlined,
                            const Color(0xFF63833D), widget.onOpenGrowth),
                        HomeFeature(
                            'reports',
                            'রিপোর্ট',
                            Icons.insights_outlined,
                            const Color(0xFF956257),
                            widget.onOpenReports),
                      ]),
                      const SizedBox(height: 24),
                      if (_summary != null) ...[
                        _PrayerTracker(
                            statuses: _prayerStatuses,
                            available: _prayerAvailable,
                            onOpen: widget.onOpenPrayer),
                        const SizedBox(height: 20),
                      ],
                      _DailyDuaCard(dua: duaForDay(widget.day)),
                      const SizedBox(height: 24),
                      if (_loading && _summary == null) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text('আপনার হিসাব লোড হচ্ছে…'),
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
                                  child: Text(
                                      'কিছু তথ্য লোড হয়নি। আবার চেষ্টা করুন।'),
                                ),
                                TextButton(
                                    onPressed: _load,
                                    child: const Text('রিট্রাই')),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_summary != null)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('আজকের ছোট পদক্ষেপ',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                  color: AppColors.brand)),
                                      const SizedBox(height: 6),
                                      Text(action.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      const SizedBox(height: 4),
                                      Text(action.description),
                                      TextButton.icon(
                                          onPressed: action.open,
                                          icon: const Icon(Icons.arrow_forward,
                                              size: 18),
                                          iconAlignment: IconAlignment.end,
                                          label: Text(action.buttonLabel)),
                                    ]))),
                      const SizedBox(height: 28),
                      if (_summary != null)
                        Semantics(
                            header: true,
                            child: Text('আজকের অগ্রগতি',
                                style: Theme.of(context).textTheme.titleLarge)),
                      const SizedBox(height: 16),
                      if (_summary != null)
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
                              progress: _tasksAvailable &&
                                      summary.totalTasks > 0
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
                              progress:
                                  _prayerAvailable && summary.prayersLogged
                                      ? (summary.prayersCompleted +
                                              summary.prayersMadeUp) /
                                          5
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
                              detail: growthScoreAvailable &&
                                      summary.growthLogged
                                  ? 'ইমান ${banglaNumber(summary.imanScore)}% • লাইফ ${banglaNumber(summary.lifeScore)}%'
                                  : 'চেকলিস্ট খুলুন',
                              onTap: widget.onOpenGrowth,
                              progress:
                                  growthScoreAvailable && summary.growthLogged
                                      ? summary.overallScore / 100
                                      : null,
                            ),
                          ];
                          if (constraints.maxWidth >= 720) {
                            return IntrinsicHeight(
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
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
                    ]),
              ))
            ],
          )),
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
        buttonLabel: 'হিসাব লিখুন',
        open: widget.onOpenPrayer,
      );
    }
    if (summary.prayersMissed > 0) {
      return _DashboardAction(
        title: 'মিসড নামাজের কাযা আদায় করুন',
        description:
            '${banglaNumber(summary.prayersMissed)} ওয়াক্ত মিস হিসেবে চিহ্নিত।',
        buttonLabel: 'হিসাব লিখুন',
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
    final configFuture = _loadPrayerConfig(requestId);
    final tasks = await tasksFuture;
    final prayer = await prayerFuture;
    final growth = await growthFuture;
    await configFuture;

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
      _prayerStatuses = prayerStatusesFromDocument(prayer.value);
      _loading = false;
    });
  }

  Future<void> _loadPrayerConfig(int requestId) async {
    final result =
        await _read(() => PrayerTimeStore(widget.repository.uid).load());
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _prayerConfig = result.value;
      _timeConfigFailed = !result.ok;
    });
  }

  Future<void> _configureLocation() async {
    if (_configuring) return;
    final uid = widget.repository.uid;
    setState(() => _configuring = true);
    try {
      final config = await showModalBottomSheet<PrayerTimeConfig>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          useSafeArea: true,
          builder: (_) => PrayerPlacePicker(initial: _prayerConfig));
      if (config == null || !mounted || uid != widget.repository.uid) return;
      await PrayerTimeStore(uid).save(config);
      if (!mounted || uid != widget.repository.uid) return;
      setState(() {
        _prayerConfig = config;
        _timeConfigFailed = false;
      });
      widget.onPrayerConfigChanged?.call();
    } catch (_) {
      if (mounted && uid == widget.repository.uid) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('নামাজের সময় সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।')));
      }
    } finally {
      if (mounted && uid == widget.repository.uid) {
        setState(() => _configuring = false);
      }
    }
  }

  Future<void> _openFasting() async {
    if (_prayerConfig == null) await _configureLocation();
    if (!mounted || _prayerConfig == null) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) =>
            FastingTimesSheet(config: _prayerConfig!, clock: widget.clock));
  }

  Future<_ReadResult<T>> _read<T>(Future<T> Function() load) async {
    try {
      return _ReadResult(await load(), true);
    } catch (_) {
      return _ReadResult(null, false);
    }
  }
}

class _PrayerTracker extends StatelessWidget {
  const _PrayerTracker(
      {required this.statuses, required this.available, required this.onOpen});
  final Map<String, PrayerStatus> statuses;
  final bool available;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text('নামাজের হিসাব',
                    style: Theme.of(context).textTheme.titleMedium)),
            TextButton(onPressed: onOpen, child: const Text('লিখুন'))
          ]),
          if (!available)
            const Text('হিসাব লোড হয়নি। নামাজের পৃষ্ঠায় আবার চেষ্টা করুন।')
          else
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final key in prayerKeys)
                    Builder(builder: (context) {
                      final state =
                          statuses[key]?.state ?? PrayerState.unlogged;
                      final (icon, color, label) = switch (state) {
                        PrayerState.prayed => (
                            Icons.check_circle,
                            AppColors.success,
                            'সময়মতো পড়া'
                          ),
                        PrayerState.madeUp => (
                            Icons.history,
                            AppColors.information,
                            'কাযা আদায়'
                          ),
                        PrayerState.missed => (
                            Icons.remove_circle_outline,
                            AppColors.danger,
                            'মিস হয়েছে'
                          ),
                        PrayerState.unlogged => (
                            Icons.radio_button_unchecked,
                            AppColors.muted,
                            'হিসাব নেই'
                          ),
                      };
                      return Semantics(
                          label: '${prayerLabels[key]}: $label',
                          child: ExcludeSemantics(
                              child: SizedBox(
                                  width: MediaQuery.textScalerOf(context)
                                              .scale(14) >
                                          20
                                      ? 84
                                      : 62,
                                  child: Column(children: [
                                    Icon(icon, color: color, size: 25),
                                    const SizedBox(height: 6),
                                    Text(prayerLabels[key]!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium)
                                  ]))));
                    }),
                ])),
        ]),
      ));
}

class _DailyDuaCard extends StatelessWidget {
  const _DailyDuaCard({required this.dua});
  final QuranDua dua;

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFFFCF9F1),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE9E0C9))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => DuaDetailPage(dua: dua))),
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.auto_stories_outlined,
                          color: Color(0xFF846121), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text('আজকের দোয়া',
                              style: Theme.of(context).textTheme.titleMedium)),
                      const Icon(Icons.arrow_forward, size: 18)
                    ]),
                    const SizedBox(height: 14),
                    Text(dua.arabic,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                        locale: const Locale('ar'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontFamily: 'NotoNaskhArabic',
                            fontSize: 27,
                            height: 1.8)),
                    const SizedBox(height: 10),
                    Text(dua.title,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(dua.displayReference,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFF846121))),
                  ])),
        ),
      );
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
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(11)),
                    child: Icon(icon, color: AppColors.brand, size: 21)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: AppColors.muted)),
                      const SizedBox(height: 3),
                      Text(value,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(detail,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.muted)),
                      if (progress != null) ...[
                        const SizedBox(height: 10),
                        ExcludeSemantics(
                            child: LinearProgressIndicator(
                                value: progress!.clamp(0.0, 1.0),
                                minHeight: 3,
                                borderRadius: BorderRadius.circular(8))),
                      ],
                    ])),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.muted),
              ]),
            )),
      );
}
