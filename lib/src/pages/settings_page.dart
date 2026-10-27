import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../account/account_service.dart';
import '../account/delete_account_page.dart';
import '../account/privacy_page.dart';
import '../app_identity.dart';
import '../display_formatters.dart';
import '../diagnostics/diagnostics_service.dart';
import '../date_helpers.dart';
import '../models.dart';
import '../reminder_service.dart';
import '../widgets/page_frame.dart';
import '../widgets/load_failure_state.dart';
import '../widgets/text_entry_dialog.dart';
import 'trends_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    required this.user,
    required this.firebaseReady,
  });

  final AppRepository repository;
  final User? user;
  final bool firebaseReady;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, Object?> _profile = {
    'name': '',
    'email': '',
    'userType': 'student',
  };
  Map<String, bool> _notifications = {
    'prayer': false,
    'tasks': false,
    'growth': false,
  };
  bool _diagnosticsBusy = false;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed) {
      return LoadFailureState(title: 'সেটিংস লোড করা যায়নি', onRetry: _load);
    }

    final displayName = widget.user?.displayName?.trim().isNotEmpty == true
        ? widget.user!.displayName!
        : '${_profile['name'] ?? ''}';
    final email = widget.user?.email ?? '${_profile['email'] ?? ''}';

    final account =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('আপনার অ্যাকাউন্ট', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 12),
      Card(
          child: Column(children: [
        _SettingsTile(
            icon: Icons.person_outline,
            title: 'প্রোফাইল',
            subtitle: [displayName, email]
                .where((value) => value.isNotEmpty)
                .join(' • '),
            onTap: _editProfileName),
        const Divider(height: 1),
        if (ReminderService.supported)
          SwitchListTile(
              value: _notifications.values.any((enabled) => enabled),
              onChanged: _toggleNotifications,
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('দৈনিক রিমাইন্ডার'),
              subtitle: const Text(
                  'কাজ সকাল ৮টা, নামাজের হিসাব রাত ৮টা, গ্রোথ রাত ৯টা'))
        else
          const ListTile(
              leading: Icon(Icons.notifications_off_outlined),
              title: Text('দৈনিক রিমাইন্ডার'),
              subtitle: Text('Android ও iOS অ্যাপে উপলব্ধ')),
      ])),
      const SizedBox(height: 16),
      Card(
          child: Column(children: [
        const _SettingsTile(
            icon: Icons.verified_user_outlined,
            title: 'ফ্রি অ্যাকাউন্ট',
            subtitle: 'অ্যাপটি ব্যবহার করতে কোনো সাবস্ক্রিপশন লাগে না',
            onTap: null),
        if (widget.firebaseReady && DiagnosticsService.supported)
          SwitchListTile(
            value: DiagnosticsService.enabled,
            onChanged: _diagnosticsBusy
                ? null
                : (value) async {
                    setState(() => _diagnosticsBusy = true);
                    try {
                      await DiagnosticsService.setEnabled(value);
                    } catch (_) {
                      if (mounted) {
                        _showMessage(
                            'পছন্দটি সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।');
                      }
                    } finally {
                      if (mounted) setState(() => _diagnosticsBusy = false);
                    }
                  },
            secondary: const Icon(Icons.bug_report_outlined),
            title: const Text('সমস্যার রিপোর্ট পাঠান'),
            subtitle: const Text(
                'ঐচ্ছিক: ফোনের মডেল, সিস্টেম ও ক্র্যাশের কারিগরি তথ্য Google Firebase-এ পাঠিয়ে অ্যাপের সমস্যা ঠিক করতে সাহায্য করুন। আপনার দৈনিক হিসাব রিপোর্টে যোগ করা হয় না।'),
          ),
        _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'গোপনীয়তা নীতি',
            subtitle: 'তথ্যের ব্যবহার, সংরক্ষণ ও আপনার অধিকার',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PrivacyPage()))),
        if (widget.firebaseReady) ...[
          const Divider(height: 1),
          _SettingsTile(
              icon: Icons.logout,
              title: 'সাইন আউট',
              subtitle: 'আপনার অ্যাকাউন্ট থেকে সাইন আউট করুন',
              destructive: true,
              onTap: _signOut),
          const Divider(height: 1),
          _SettingsTile(
              icon: Icons.person_remove_outlined,
              title: 'অ্যাকাউন্ট মুছে ফেলুন',
              subtitle: 'অ্যাকাউন্ট ও সংশ্লিষ্ট তথ্য স্থায়ীভাবে মুছুন',
              destructive: true,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => DeleteAccountPage(
                      usesPassword: widget.user?.providerData.any((provider) =>
                              provider.providerId == 'password') ??
                          false)))),
        ],
      ])),
    ]);
    final reports =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('অগ্রগতি ও রিপোর্ট', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 12),
      Card(
          child: Column(children: [
        _SettingsTile(
            icon: Icons.show_chart_outlined,
            title: 'অগ্রগতির ট্রেন্ড',
            subtitle: 'শেষ ৭ ও ৩০ দিনের দিনভিত্তিক হিসাব',
            onTap: _openTrends),
        const Divider(height: 1),
        _SettingsTile(
            icon: Icons.today_outlined,
            title: 'দৈনিক রিপোর্ট',
            subtitle: 'আজকের নামাজ ও গ্রোথের সারাংশ',
            onTap: () => _showReport('দৈনিক রিপোর্ট', dateOnly(), dateOnly())),
        const Divider(height: 1),
        _SettingsTile(
            icon: Icons.calendar_view_week_outlined,
            title: 'সাপ্তাহিক রিপোর্ট',
            subtitle: 'শেষ ৭ দিনের অগ্রগতি',
            onTap: () => _showReport('সাপ্তাহিক রিপোর্ট',
                dateOnly().subtract(const Duration(days: 6)), dateOnly())),
        const Divider(height: 1),
        _SettingsTile(
            icon: Icons.bar_chart_outlined,
            title: 'মাসিক রিপোর্ট',
            subtitle: 'চলতি মাসের অগ্রগতি ও পরিসংখ্যান',
            onTap: () {
              final now = dateOnly();
              _showReport('মাসিক রিপোর্ট', DateTime(now.year, now.month), now);
            }),
      ])),
    ]);
    return PageFrame(
        title: 'সেটিংস',
        subtitle: 'অ্যাকাউন্ট, নোটিফিকেশন ও অগ্রগতির রিপোর্ট',
        children: [
          if (!widget.firebaseReady) ...[
            Card(
                color: const Color(0xFFFFF8E3),
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(
                                  'আপনি প্রিভিউ ব্যবহার করছেন। এই মোডে তথ্য স্থায়ীভাবে সংরক্ষিত হয় না।',
                                  style:
                                      Theme.of(context).textTheme.bodyMedium)),
                        ]))),
            const SizedBox(height: 24),
          ],
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth >= 760) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: account),
                    const SizedBox(width: 24),
                    Expanded(child: reports),
                  ]);
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  account,
                  const SizedBox(height: 24),
                  reports,
                ]);
          }),
          const SizedBox(height: 28),
          Text('${AppIdentity.name} • সংস্করণ 1.0.0',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final data = await widget.repository.loadSettings();
      final profile = asStringMap(data?['profile']);
      final notifications = parseBoolMap(data?['notifications']);

      _profile = {
        'name': profile['name'] ?? widget.user?.displayName ?? '',
        'email': profile['email'] ?? widget.user?.email ?? '',
        'userType': profile['userType'] ?? 'student',
      };

      if (data?['remindersConfigured'] == true && notifications.isNotEmpty) {
        _notifications = {..._notifications, ...notifications};
      }

      if (ReminderService.supported) {
        try {
          await ReminderService.instance.sync(_notifications);
        } catch (_) {
          _showMessage('রিমাইন্ডার চালু করা যায়নি');
        }
      }
    } catch (_) {
      _loadFailed = true;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _editProfileName() async {
    final repository = widget.repository;
    final user = widget.user;
    await showDialog<void>(
      context: context,
      builder: (_) => TextEntryDialog(
          title: 'নাম সম্পাদনা করুন',
          label: 'আপনার নাম',
          submitLabel: 'সেভ',
          initialValue: '${_profile['name'] ?? user?.displayName ?? ''}',
          errorMessage: 'প্রোফাইল সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।',
          onSave: (name) async {
            if (!mounted || repository.uid != widget.repository.uid) {
              throw StateError('Account changed');
            }
            final next = {..._profile, 'name': name};
            await user?.updateDisplayName(name);
            await repository.saveProfile(next);
            if (mounted && repository.uid == widget.repository.uid) {
              setState(() => _profile = next);
            }
          }),
    );
  }

  Future<void> _toggleNotifications(bool enabled) async {
    final next = {'prayer': enabled, 'tasks': enabled, 'growth': enabled};
    try {
      final granted = await ReminderService.instance.sync(
        next,
        requestPermission: enabled,
      );
      if (!granted) {
        _showMessage('রিমাইন্ডার চালু করতে নোটিফিকেশন অনুমতি দিন');
        return;
      }
      await widget.repository.saveNotificationSettings(next);
      if (mounted) setState(() => _notifications = next);
    } catch (_) {
      try {
        await ReminderService.instance.sync(_notifications);
      } catch (_) {
        // Keep the saved preference unchanged even if the device is unavailable.
      }
      _showMessage('রিমাইন্ডার আপডেট করা যায়নি');
    }
  }

  Future<void> _showReport(String title, DateTime start, DateTime end) async {
    final future = widget.repository.buildReport(start: start, end: end);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: FutureBuilder<ReportSummary>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return const Text('রিপোর্ট লোড করা যায়নি। আবার চেষ্টা করুন।');
              }

              final summary = snapshot.data ?? ReportSummary.empty;
              if (!widget.repository.canSync) {
                return const Text(
                  'রিপোর্ট দেখতে আপনার অ্যাকাউন্টে সাইন ইন করুন।',
                );
              }

              return SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${compactDateLabel(start)} - ${compactDateLabel(end)}'),
                  const SizedBox(height: 14),
                  _ReportRow(
                      label: 'নির্বাচিত দিন',
                      value: banglaNumber(summary.days)),
                  _ReportRow(
                    label: 'নামাজ লগড দিন',
                    value: banglaNumber(summary.prayerLoggedDays),
                  ),
                  _ReportRow(
                    label: 'পড়া হয়েছে',
                    value: banglaNumber(summary.totalPrayed),
                  ),
                  _ReportRow(
                      label: 'জামাত', value: banglaNumber(summary.totalJamaat)),
                  _ReportRow(
                    label: 'মিসড (চিহ্নিত)',
                    value: banglaNumber(summary.totalMissed),
                  ),
                  _ReportRow(
                    label: 'কাযা আদায়',
                    value: banglaNumber(summary.totalMadeUp),
                  ),
                  _ReportRow(
                    label: 'হিসাব নেই (লগড দিনে)',
                    value: banglaNumber(summary.totalUnlogged),
                  ),
                  const Divider(),
                  _ReportRow(
                    label: 'ইমান গড়',
                    value: '${banglaNumber(summary.averageIman)}%',
                  ),
                  _ReportRow(
                    label: 'লাইফ গড়',
                    value: '${banglaNumber(summary.averageLife)}%',
                  ),
                  _ReportRow(
                    label: 'ওভারঅল গড়',
                    value: '${banglaNumber(summary.averageOverall)}%',
                  ),
                ],
              ));
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('বন্ধ'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openTrends() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('রিপোর্ট')),
          body: TrendsPage(repository: widget.repository, today: dateOnly()),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('সাইন আউট'),
          content: const Text('আপনি কি সাইন আউট করতে চান?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('সাইন আউট'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final cleaned = await AccountService.signOut();
      if (!cleaned && messenger.mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text(
                'সাইন আউট হয়েছে। রিমাইন্ডার বন্ধ হয়েছে কি না ডিভাইসের সেটিংসে পরীক্ষা করুন।')));
      }
    } catch (_) {
      if (mounted) _showMessage('সাইন আউট করা যায়নি। আবার চেষ্টা করুন।');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: destructive ? Theme.of(context).colorScheme.error : null,
        ),
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
