import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../date_helpers.dart';
import '../models.dart';
import '../widgets/page_frame.dart';

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
    'prayer': true,
    'tasks': true,
    'growth': false,
  };
  bool _loading = true;

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

    final displayName = widget.user?.displayName?.trim().isNotEmpty == true
        ? widget.user!.displayName!
        : '${_profile['name'] ?? ''}';
    final email = widget.user?.email ?? '${_profile['email'] ?? ''}';

    return PageFrame(
      title: 'সেটিংস',
      subtitle: 'অ্যাকাউন্ট, নোটিফিকেশন ও অগ্রগতির রিপোর্ট',
      children: [
        if (!widget.firebaseReady)
          Card(
            color: Colors.amber.shade50,
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Firebase options এখনো সেট করা হয়নি। অ্যাপটি offline preview mode-এ চলছে।',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        Card(
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.person_outline,
                title: 'প্রোফাইল',
                subtitle: [displayName, email]
                    .where((value) => value.isNotEmpty)
                    .join(' • '),
                onTap: _editProfileName,
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _notifications['prayer'] == true,
                onChanged: _toggleNotifications,
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('নোটিফিকেশন'),
                subtitle: const Text('নামাজ, কাজ ও গ্রোথ রিমাইন্ডার'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.today_outlined,
                title: 'দৈনিক রিপোর্ট',
                subtitle: 'আজকের নামাজ ও গ্রোথের সারাংশ',
                onTap: () =>
                    _showReport('দৈনিক রিপোর্ট', dateOnly(), dateOnly()),
              ),
              const Divider(height: 1),
              _SettingsTile(
                icon: Icons.calendar_view_week_outlined,
                title: 'সাপ্তাহিক রিপোর্ট',
                subtitle: 'শেষ ৭ দিনের অগ্রগতি',
                onTap: () => _showReport(
                  'সাপ্তাহিক রিপোর্ট',
                  dateOnly().subtract(const Duration(days: 6)),
                  dateOnly(),
                ),
              ),
              const Divider(height: 1),
              _SettingsTile(
                icon: Icons.bar_chart_outlined,
                title: 'মাসিক রিপোর্ট',
                subtitle: 'চলতি মাসের অগ্রগতি ও পরিসংখ্যান',
                onTap: () {
                  final now = dateOnly();
                  _showReport(
                      'মাসিক রিপোর্ট', DateTime(now.year, now.month), now);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.credit_card_outlined,
                title: 'বিলিং',
                subtitle: 'ফ্রি ভার্সন - আপাতত বিলিং প্রয়োজন নেই',
                onTap: () {},
              ),
              if (widget.firebaseReady) ...[
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.logout,
                  title: 'সাইন আউট',
                  subtitle: 'আপনার অ্যাকাউন্ট থেকে সাইন আউট করুন',
                  destructive: true,
                  onTap: _signOut,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Ummah Assist v1.0.0\nমুসলিমদের জন্য যত্ন দিয়ে তৈরি',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Future<void> _load() async {
    try {
      final data = await widget.repository.loadSettings();
      final profile = asStringMap(data?['profile']);
      final notifications = parseBoolMap(data?['notifications']);

      _profile = {
        'name': profile['name'] ?? widget.user?.displayName ?? '',
        'email': profile['email'] ?? widget.user?.email ?? '',
        'userType': profile['userType'] ?? 'student',
      };

      if (notifications.isNotEmpty) {
        _notifications = {
          ..._notifications,
          ...notifications,
        };
      }
    } catch (_) {
      _showMessage('সেটিংস লোড করতে সমস্যা হয়েছে');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _editProfileName() async {
    final controller = TextEditingController(
        text: '${_profile['name'] ?? widget.user?.displayName ?? ''}');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('নাম সম্পাদনা করুন'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'আপনার নাম'),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('সেভ'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    final name = result?.trim() ?? '';
    if (name.isEmpty) {
      return;
    }

    setState(() => _profile = {..._profile, 'name': name});
    try {
      await widget.user?.updateDisplayName(name);
      await _save();
    } catch (_) {
      _showMessage('প্রোফাইল আপডেট করতে সমস্যা হয়েছে');
    }
  }

  Future<void> _toggleNotifications(bool enabled) async {
    setState(() {
      _notifications = {
        'prayer': enabled,
        'tasks': enabled,
        'growth': enabled,
      };
    });
    await _save();
  }

  Future<void> _save() async {
    await widget.repository.saveSettings(
      profile: _profile,
      notifications: _notifications,
    );
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

              final summary = snapshot.data ?? ReportSummary.empty;
              if (!widget.repository.canSync) {
                return const Text(
                    'রিপোর্ট দেখতে Firebase কনফিগার করে সাইন ইন করুন।');
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${compactDateLabel(start)} - ${compactDateLabel(end)}'),
                  const SizedBox(height: 14),
                  _ReportRow(label: 'ট্র্যাকড দিন', value: '${summary.days}'),
                  _ReportRow(
                      label: 'নামাজ লগড দিন',
                      value: '${summary.prayerLoggedDays}'),
                  _ReportRow(
                      label: 'পড়া হয়েছে', value: '${summary.totalPrayed}'),
                  _ReportRow(label: 'জামাত', value: '${summary.totalJamaat}'),
                  _ReportRow(label: 'মিসড', value: '${summary.totalMissed}'),
                  const Divider(),
                  _ReportRow(
                      label: 'ইমান গড়', value: '${summary.averageIman}%'),
                  _ReportRow(
                      label: 'লাইফ গড়', value: '${summary.averageLife}%'),
                  _ReportRow(
                      label: 'ওভারঅল গড়', value: '${summary.averageOverall}%'),
                ],
              );
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

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
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
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color =
        destructive ? Colors.red : Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: destructive ? Colors.red.shade700 : null,
        ),
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
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
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
