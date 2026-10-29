import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dhikr_progress.dart';
import '../display_formatters.dart';

class TasbihFrame extends StatelessWidget {
  const TasbihFrame({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          children: [
            Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children),
            ))
          ],
        ),
      );
}

class DhikrPhraseText extends StatelessWidget {
  const DhikrPhraseText({super.key, required this.goal, this.compact = false});

  final DhikrGoal goal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final phrase = DhikrPhrase.forGoal(goal);
    final theme = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (phrase != null) ...[
        Text(phrase.arabic,
            textDirection: TextDirection.rtl,
            locale: const Locale('ar'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'NotoNaskhArabic',
                fontSize: compact ? 28 : 38,
                height: 1.5,
                color: theme.colorScheme.onSurface)),
        const SizedBox(height: 2),
      ],
      Text(goal.name,
          textAlign: TextAlign.center,
          style: compact
              ? theme.textTheme.titleMedium
              : theme.textTheme.titleLarge),
      if (phrase != null && !compact) ...[
        const SizedBox(height: 6),
        Text(phrase.meaning,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    ]);
  }
}

/// One large, accessible tap surface. Count persistence belongs to the page.
class TasbihCounter extends StatelessWidget {
  const TasbihCounter({
    super.key,
    required this.goal,
    required this.count,
    required this.onTap,
  });

  final DhikrGoal goal;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final size = math.min(260.0, constraints.maxWidth);
      return Center(
        child: Semantics(
          button: true,
          enabled: onTap != null,
          label: '${goal.name}: এক যোগ করুন',
          value: '${banglaNumber(count)} / ${banglaNumber(goal.target)}',
          onTap: onTap,
          child: ExcludeSemantics(
            child: SizedBox.square(
              dimension: size,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: (count / goal.target).clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 160),
                builder: (context, progress, child) => CustomPaint(
                  painter: _TasbihRing(
                      progress, scheme.primary, scheme.primaryContainer),
                  child: child,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Material(
                    color: scheme.primaryContainer.withValues(alpha: 0.3),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('dhikr-plus-${goal.id}'),
                      onTap: onTap,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(banglaNumber(count),
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(
                                          fontSize: 56, color: scheme.primary)),
                            ),
                            const SizedBox(height: 4),
                            Text('ট্যাপ করুন',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium),
                            if (MediaQuery.textScalerOf(context).scale(14) <=
                                19) ...[
                              const SizedBox(height: 8),
                              Icon(Icons.touch_app_outlined,
                                  size: 24, color: scheme.primary),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _TasbihRing extends CustomPainter {
  const _TasbihRing(this.progress, this.color, this.track);

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(center, radius, paint);
    final angle = -math.pi / 2 + math.pi * 2 * progress;
    if (progress > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false,
          paint..color = color);
    }
    canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        9,
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TasbihRing oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      track != oldDelegate.track;
}
