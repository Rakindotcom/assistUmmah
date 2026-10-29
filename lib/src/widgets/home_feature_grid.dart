import 'package:flutter/material.dart';

class HomeFeature {
  const HomeFeature(this.id, this.label, this.icon, this.color, this.open);
  final String id, label;
  final IconData icon;
  final Color color;
  final VoidCallback open;
}

class HomeFeatureGrid extends StatelessWidget {
  const HomeFeatureGrid({super.key, required this.features});
  final List<HomeFeature> features;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
        final columns = constraints.maxWidth >= 800
            ? 6
            : constraints.maxWidth >= 540
                ? 4
                : largeText
                    ? 2
                    : 3;
        return Column(children: [
          for (var start = 0; start < features.length; start += columns) ...[
            if (start > 0) const SizedBox(height: 10),
            IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  for (var offset = 0; offset < columns; offset++) ...[
                    if (offset > 0) const SizedBox(width: 10),
                    Expanded(
                        child: start + offset < features.length
                            ? _FeatureTile(feature: features[start + offset])
                            : const SizedBox()),
                  ],
                ])),
          ],
        ]);
      });
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.feature});
  final HomeFeature feature;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('home-${feature.id}'),
          onTap: feature.open,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: feature.color.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(15)),
                        child:
                            Icon(feature.icon, color: feature.color, size: 25)),
                    const SizedBox(height: 6),
                    Text(feature.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge),
                  ])),
        ),
      );
}
