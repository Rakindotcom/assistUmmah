import 'package:flutter/material.dart';

import '../widgets/page_frame.dart';

class MorePage extends StatelessWidget {
  const MorePage({
    super.key,
    required this.onOpenCalendar,
    required this.onOpenQuran,
    required this.onOpenDhikr,
    required this.onOpenContacts,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenQuran;
  final VoidCallback onOpenDhikr;
  final VoidCallback onOpenContacts;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'আরও',
      subtitle: 'কুরআন, যিকির, দিনপঞ্জি, যোগাযোগ, রিপোর্ট ও অ্যাকাউন্ট',
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 680;
          final destinations = [
            (
              Icons.menu_book_outlined,
              'কুরআন রিডিং',
              'দৈনিক লক্ষ্য ও পড়ার হিসাব',
              onOpenQuran
            ),
            (
              Icons.touch_app_outlined,
              'যিকিরের লক্ষ্য',
              'দৈনিক গণনা ও অগ্রগতি',
              onOpenDhikr
            ),
            (
              Icons.calendar_month_outlined,
              'দিনপঞ্জি',
              'আগের দিনের নামাজ ও গ্রোথের হিসাব',
              onOpenCalendar
            ),
            (
              Icons.contacts_outlined,
              'যোগাযোগ',
              'পরিবার ও গুরুত্বপূর্ণ ব্যক্তিদের তালিকা',
              onOpenContacts
            ),
            (
              Icons.settings_outlined,
              'সেটিংস ও রিপোর্ট',
              'রিমাইন্ডার, অগ্রগতি ও অ্যাকাউন্ট',
              onOpenSettings
            ),
          ];
          return Wrap(spacing: 16, runSpacing: 12, children: [
            for (final destination in destinations)
              SizedBox(
                width: wide
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth,
                child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: destination.$4,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: wide ? 112 : 80),
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(children: [
                              Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Icon(destination.$1,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      size: 22)),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(destination.$2,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall),
                                    const SizedBox(height: 4),
                                    Text(destination.$3,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant)),
                                  ])),
                              const SizedBox(width: 8),
                              Icon(Icons.chevron_right,
                                  size: 20,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ])),
                      ),
                    )),
              ),
          ]);
        }),
      ],
    );
  }
}
