import 'package:flutter/material.dart';

import '../app_identity.dart';

class AppBrand extends StatelessWidget {
  const AppBrand({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 10 : 12),
            child: Image.asset(
              AppIdentity.iconAsset,
              width: compact ? 34 : 44,
              height: compact ? 34 : 44,
              cacheWidth:
                  ((compact ? 34 : 44) * MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            )),
        const SizedBox(width: 12),
        Flexible(
            child: Text(AppIdentity.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (compact
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.titleLarge)
                    ?.copyWith(
                        fontWeight: FontWeight.w700, letterSpacing: -0.3))),
      ]);
}
