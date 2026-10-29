import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../home_prayer_snapshot.dart';
import '../models.dart';
import '../prayer_times_service.dart';

class HomePrayerCard extends StatefulWidget {
  const HomePrayerCard(
      {super.key,
      required this.config,
      required this.onOpen,
      required this.onConfigure,
      this.clock,
      this.active = true,
      this.failed = false});
  final PrayerTimeConfig? config;
  final VoidCallback onOpen, onConfigure;
  final DateTime Function()? clock;
  final bool active, failed;

  @override
  State<HomePrayerCard> createState() => _HomePrayerCardState();
}

class _HomePrayerCardState extends State<HomePrayerCard> {
  Timer? _timer;
  HomePrayerSnapshot? _snapshot;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _refresh(force: true);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant HomePrayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh(
        force: oldWidget.config != widget.config ||
            oldWidget.clock != widget.clock);
    if (oldWidget.active != widget.active ||
        oldWidget.config != widget.config) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.active && widget.config != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(_refresh);
      });
    }
  }

  void _refresh({bool force = false}) {
    _now = widget.clock?.call() ?? DateTime.now();
    final config = widget.config;
    if (config == null) {
      _snapshot = null;
      return;
    }
    final local =
        tz.TZDateTime.from(_now, PrayerTimeService.location(config.timeZoneId));
    final previous = _snapshot;
    if (force ||
        previous == null ||
        !previous.next.time.isAfter(_now) ||
        _now.isBefore(previous.latest.time) ||
        local.day != previous.now.day ||
        local.month != previous.now.month ||
        local.year != previous.now.year ||
        (previous.latest.key == 'fajr' &&
            previous.schedule.sunrise != null &&
            previous.now.isBefore(previous.schedule.sunrise!) &&
            !_now.isBefore(previous.schedule.sunrise!))) {
      _snapshot = HomePrayerSnapshot(config, _now);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DecoratedBox(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF103F3A), Color(0xFF087568)])),
          child: Stack(children: [
            const Positioned.fill(
                child: IgnorePointer(
                    child: ExcludeSemantics(
                        child: CustomPaint(painter: _MosqueSilhouette())))),
            Padding(
              padding: const EdgeInsets.all(18),
              child: snapshot == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text('নামাজের সময় আপনার হাতেই',
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(color: Colors.white)),
                          const SizedBox(height: 8),
                          Text(
                              widget.failed
                                  ? 'সময়ের সেটিংস পড়া যায়নি। আবার স্থান বেছে নিন।'
                                  : 'একবার স্থান বেছে নিন। প্রতিদিনের সময় ইন্টারনেট ছাড়াই পাবেন।',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: const Color(0xFFD5EDE6))),
                          const SizedBox(height: 18),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            FilledButton.icon(
                                onPressed: widget.onConfigure,
                                style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFF7ECD2),
                                    foregroundColor: const Color(0xFF103F3A)),
                                icon: const Icon(Icons.location_on_outlined,
                                    size: 18),
                                label: const Text('স্থান সেট করুন')),
                            TextButton(
                                onPressed: widget.onOpen,
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.white),
                                child: const Text('নামাজ দেখুন')),
                          ]),
                        ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          Row(children: [
                            const Icon(Icons.schedule_outlined,
                                color: Color(0xFFD5EDE6), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'পরবর্তী নামাজ${snapshot.nextIsTomorrow ? ' · আগামীকাল' : ''}',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                        color: const Color(0xFFD5EDE6)))),
                          ]),
                          const SizedBox(height: 10),
                          LayoutBuilder(builder: (context, constraints) {
                            final prayer = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(prayerLabels[snapshot.next.key]!,
                                      style: theme.textTheme.headlineLarge
                                          ?.copyWith(color: Colors.white)),
                                  Text(
                                      '${formatPrayerTime(snapshot.next.time)} · শুরু',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              color: const Color(0xFFD5EDE6))),
                                ]);
                            final countdown = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('সময় বাকি',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                              color: const Color(0xFFD5EDE6))),
                                  Semantics(
                                      label:
                                          '${prayerCountdown(snapshot.next.time.difference(_now))} বাকি',
                                      child: ExcludeSemantics(
                                          child: Text(
                                              prayerCountdown(snapshot.next.time
                                                  .difference(_now)),
                                              key: const Key(
                                                  'home-prayer-countdown'),
                                              style: theme
                                                  .textTheme.headlineSmall
                                                  ?.copyWith(
                                                      color: const Color(
                                                          0xFFF7ECD2))))),
                                ]);
                            if (constraints.maxWidth < 290 ||
                                MediaQuery.textScalerOf(context).scale(14) >
                                    20) {
                              return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    prayer,
                                    const SizedBox(height: 12),
                                    countdown
                                  ]);
                            }
                            return Row(children: [
                              Expanded(child: prayer),
                              const SizedBox(width: 16),
                              countdown
                            ]);
                          }),
                          const SizedBox(height: 12),
                          ExcludeSemantics(
                              child: LinearProgressIndicator(
                                  value: (_now
                                              .difference(snapshot.latest.time)
                                              .inMilliseconds /
                                          snapshot.next.time
                                              .difference(snapshot.latest.time)
                                              .inMilliseconds)
                                      .clamp(0.0, 1.0),
                                  minHeight: 4,
                                  borderRadius: BorderRadius.circular(8),
                                  color: const Color(0xFFF1DCA6),
                                  backgroundColor: Colors.white24)),
                          const SizedBox(height: 4),
                          Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Text(
                                    snapshot.afterSunriseBeforeDhuhr
                                        ? 'সূর্যোদয় ${formatPrayerTime(snapshot.schedule.sunrise!)}'
                                        : '${prayerLabels[snapshot.latest.key]} শুরু ${formatPrayerTime(snapshot.latest.time)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFFD5EDE6))),
                                TextButton(
                                    onPressed: widget.onOpen,
                                    style: TextButton.styleFrom(
                                        foregroundColor: Colors.white),
                                    child: const Text('নামাজ দেখুন')),
                              ]),
                        ]),
            ),
          ]),
        ),
        if (snapshot != null)
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                for (final entry in snapshot.schedule.entries)
                  SizedBox(
                    width: MediaQuery.textScalerOf(context).scale(14) > 20
                        ? 88
                        : 64,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: entry.time == snapshot.next.time
                                ? theme.colorScheme.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 6, horizontal: 4),
                            child: Column(children: [
                              Text(prayerLabels[entry.key]!,
                                  style: theme.textTheme.labelMedium),
                              const SizedBox(height: 4),
                              Text(formatPrayerTime(entry.time),
                                  style: theme.textTheme.labelLarge),
                            ])),
                      ),
                    ),
                  ),
              ])),
      ]),
    );
  }
}

class _MosqueSilhouette extends CustomPainter {
  const _MosqueSilhouette();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB1DFD2).withValues(alpha: 0.09);
    final x = size.width * 0.82;
    final ground = size.height;
    final dome = Path()
      ..moveTo(x - 55, ground - 36)
      ..cubicTo(x - 58, ground - 85, x - 12, ground - 82, x, ground - 110)
      ..cubicTo(x + 12, ground - 82, x + 58, ground - 85, x + 55, ground - 36)
      ..close();
    canvas.drawPath(dome, paint);
    canvas.drawRect(Rect.fromLTRB(x - 55, ground - 36, x + 55, ground), paint);
    for (final offset in [-78.0, 78.0]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x + offset - 7, ground - 110, 14, 110),
              const Radius.circular(5)),
          paint);
      final spire = Path()
        ..moveTo(x + offset - 11, ground - 105)
        ..lineTo(x + offset, ground - 125)
        ..lineTo(x + offset + 11, ground - 105)
        ..close();
      canvas.drawPath(spire, paint);
    }
    final moon = Path.combine(
        PathOperation.difference,
        Path()
          ..addOval(
              Rect.fromCircle(center: Offset(size.width - 30, 32), radius: 16)),
        Path()
          ..addOval(Rect.fromCircle(
              center: Offset(size.width - 24, 27), radius: 16)));
    canvas.drawPath(
        moon, paint..color = const Color(0xFFF1DCA6).withValues(alpha: 0.25));
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      canvas.drawCircle(
          Offset(x + math.cos(angle) * 45, 40 + math.sin(angle) * 20),
          1.4,
          paint);
    }
  }

  @override
  bool shouldRepaint(_MosqueSilhouette oldDelegate) => false;
}
