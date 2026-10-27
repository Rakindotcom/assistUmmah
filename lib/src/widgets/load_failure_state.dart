import 'package:flutter/material.dart';

class LoadFailureState extends StatelessWidget {
  const LoadFailureState(
      {super.key, required this.title, required this.onRetry});
  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                              color:
                                  Theme.of(context).colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(16)),
                          child: Icon(Icons.cloud_off_outlined,
                              color: Theme.of(context).colorScheme.error,
                              size: 28)),
                      const SizedBox(height: 20),
                      Semantics(
                          liveRegion: true,
                          child: Text(title,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge)),
                      const SizedBox(height: 8),
                      Text('সংরক্ষিত তথ্য দেখাতে পারিনি। আবার চেষ্টা করুন।',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('রিট্রাই')),
                    ],
                  ))),
        ),
      ));
}
