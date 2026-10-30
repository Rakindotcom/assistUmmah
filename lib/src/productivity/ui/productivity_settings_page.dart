import 'package:flutter/material.dart';

import '../data/experience_repository.dart';
import '../data/workspace_backup.dart';
import '../domain/experience_options.dart';
import '../domain/planning_time_zone.dart';
import 'experience_strings.dart';

class ProductivitySettingsPage extends StatefulWidget {
  const ProductivitySettingsPage(
      {super.key,
      required this.repository,
      required this.options,
      required this.backup,
      this.onOpenAccount});
  final ExperienceRepository repository;
  final ExperienceOptions options;
  final WorkspaceBackup backup;
  final VoidCallback? onOpenAccount;
  @override
  State<ProductivitySettingsPage> createState() =>
      _ProductivitySettingsPageState();
}

class _ProductivitySettingsPageState extends State<ProductivitySettingsPage> {
  bool _working = false;
  ExperienceStrings get strings => ExperienceStrings(widget.options.language);
  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(strings.text(
                'Could not complete this action. Your current data is kept.',
                'কাজটি সম্পন্ন হয়নি। আপনার বর্তমান তথ্য রাখা আছে।'))));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _patch(Map<String, Object?> patch) =>
      _run(() => widget.repository.updateOptions(patch));
  Future<void> _import() async {
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(strings.text('Restore workspace backup?',
                  'কর্মপরিসরের ব্যাকআপ ফিরিয়ে আনবেন?')),
              content: Text(strings.text(
                  'Values in the backup can replace current entries. Entries created later remain. The file must belong to this account.',
                  'ব্যাকআপের তথ্য বর্তমান তথ্য বদলে দিতে পারে। পরে তৈরি করা বিষয়গুলো থাকবে। ফাইলটি এই অ্যাকাউন্টের হতে হবে।')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(strings.text('Cancel', 'বাতিল'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child:
                        Text(strings.text('Choose backup', 'ব্যাকআপ বেছে নিন')))
              ],
            ));
    if (approved != true || !mounted) return;
    await _run(() async {
      try {
        final count = await widget.backup.restore();
        if (count != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(strings.text(
                  'Restored ${strings.number(count)} entries.',
                  '${strings.number(count)}টি তথ্য ফিরিয়ে আনা হয়েছে।'))));
        }
      } on FormatException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(strings.text(
                  'This backup is invalid, belongs to another account, or needs a newer app version. Nothing was imported.',
                  'ব্যাকআপটি সঠিক নয়, অন্য অ্যাকাউন্টের, অথবা নতুন অ্যাপ সংস্করণ দরকার। কোনো তথ্য আনা হয়নি।'))));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    return Scaffold(
        appBar: AppBar(title: Text(strings.text('Settings', 'সেটিংস'))),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            if (_working) const LinearProgressIndicator(),
            DropdownButtonFormField<String>(
                initialValue: options.language,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: strings.text('Language', 'ভাষা')),
                items: const [
                  DropdownMenuItem(value: 'bn', child: Text('বাংলা')),
                  DropdownMenuItem(value: 'en', child: Text('English'))
                ],
                onChanged: _working
                    ? null
                    : (value) {
                        if (value != null) _patch({'language': value});
                      }),
            const SizedBox(height: 20),
            DropdownButtonFormField<ExperienceTheme>(
                initialValue: options.theme,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: strings.text('Appearance', 'অ্যাপের রং')),
                items: [
                  for (final theme in ExperienceTheme.values)
                    DropdownMenuItem(
                        value: theme,
                        child: Text(switch (theme) {
                          ExperienceTheme.system =>
                            strings.text('System', 'ফোনের মতো'),
                          ExperienceTheme.light =>
                            strings.text('Light', 'হালকা'),
                          ExperienceTheme.dark => strings.text('Dark', 'গাঢ়'),
                        }))
                ],
                onChanged: _working
                    ? null
                    : (value) {
                        if (value != null) _patch({'theme': value.name});
                      }),
            const SizedBox(height: 20),
            Text(strings.text('Workspaces and modules', 'কর্মপরিসর ও বিষয়'),
                style: Theme.of(context).textTheme.titleMedium),
            for (final module in WorkspaceModule.values)
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.module(module)),
                  value: options.modules.contains(module),
                  subtitle: module == WorkspaceModule.faith
                      ? Text(strings.text(
                          'Disabling keeps all prayer and reading history.',
                          'বন্ধ করলেও নামাজ ও পড়ার পুরনো হিসাব থাকবে।'))
                      : null,
                  onChanged: _working
                      ? null
                      : (selected) {
                          final modules = {...options.modules};
                          selected
                              ? modules.add(module)
                              : modules.remove(module);
                          final primary = modules
                              .where((value) => value != WorkspaceModule.faith)
                              .toList();
                          if (primary.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(strings.text(
                                    'Keep at least one workspace enabled.',
                                    'অন্তত একটি কর্মপরিসর চালু রাখুন।'))));
                            return;
                          }
                          _patch({
                            'modules':
                                modules.map((value) => value.name).toList(),
                            if (!modules.any((value) =>
                                value.name == options.activeWorkspace))
                              'activeWorkspace': primary.first.name
                          });
                        }),
            const Divider(height: 32),
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.text('Time zone', 'সময় অঞ্চল')),
                subtitle: Text(options.timeZone),
                trailing: const Icon(Icons.chevron_right),
                onTap: _working
                    ? null
                    : () async {
                        final zone = await Navigator.of(context).push<String>(
                            MaterialPageRoute(
                                builder: (_) =>
                                    _TimeZonePage(strings: strings)));
                        if (zone != null && mounted) _patch({'timeZone': zone});
                      }),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.text('24-hour clock', '২৪ ঘণ্টার ঘড়ি')),
                value: options.use24HourClock,
                onChanged: _working
                    ? null
                    : (value) => _patch({'use24HourClock': value})),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
                initialValue: options.weekStartsOn,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: strings.text(
                        'First day of the week', 'সপ্তাহের প্রথম দিন')),
                items: [
                  for (var day = 1; day <= 7; day++)
                    DropdownMenuItem(
                        value: day,
                        child: Text(strings.text(
                            [
                              'Monday',
                              'Tuesday',
                              'Wednesday',
                              'Thursday',
                              'Friday',
                              'Saturday',
                              'Sunday'
                            ][day - 1],
                            [
                              'সোমবার',
                              'মঙ্গলবার',
                              'বুধবার',
                              'বৃহস্পতিবার',
                              'শুক্রবার',
                              'শনিবার',
                              'রবিবার'
                            ][day - 1])))
                ],
                onChanged: _working
                    ? null
                    : (value) {
                        if (value != null) _patch({'weekStartsOn': value});
                      }),
            const Divider(height: 36),
            Text(strings.text('Backups', 'ব্যাকআপ'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(strings.text(
                'Export includes your workspace, trash, unsynced changes and edit history. This JSON file is not encrypted; keep it private.',
                'কর্মপরিসর, ট্র্যাশ, সিঙ্ক না হওয়া পরিবর্তন ও সম্পাদনার ইতিহাস ব্যাকআপে থাকবে। এই JSON ফাইলটি এনক্রিপ্ট করা নয়; ব্যক্তিগতভাবে রাখুন।')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _working
                    ? null
                    : () => _run(() async {
                          final saved = await widget.backup.export();
                          if (saved && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(strings.text(
                                    'Backup saved.', 'ব্যাকআপ রাখা হয়েছে।'))));
                          }
                        }),
                icon: const Icon(Icons.download_outlined),
                label: Text(strings.text('Export backup', 'ব্যাকআপ নিন'))),
            OutlinedButton.icon(
                onPressed: _working ? null : _import,
                icon: const Icon(Icons.restore),
                label: Text(
                    strings.text('Restore backup', 'ব্যাকআপ ফিরিয়ে আনুন'))),
            if (widget.onOpenAccount != null) ...[
              const Divider(height: 32),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.text(
                      'Account and privacy', 'অ্যাকাউন্ট ও গোপনীয়তা')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _working ? null : widget.onOpenAccount),
            ],
          ]),
        ))));
  }
}

class _TimeZonePage extends StatefulWidget {
  const _TimeZonePage({required this.strings});
  final ExperienceStrings strings;
  @override
  State<_TimeZonePage> createState() => _TimeZonePageState();
}

class _TimeZonePageState extends State<_TimeZonePage> {
  final _zones = PlanningTimeZone.availableZones;
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final zones = _zones
        .where((zone) => zone.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Scaffold(
        appBar: AppBar(
            title: Text(widget.strings
                .text('Choose time zone', 'সময় অঞ্চল বেছে নিন'))),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: SearchBar(
                  hintText: widget.strings
                      .text('Search city or region', 'শহর বা অঞ্চল খুঁজুন'),
                  onChanged: (value) => setState(() => _query = value))),
          Expanded(
              child: ListView.builder(
                  itemCount: zones.length,
                  itemBuilder: (context, index) => ListTile(
                      title: Text(zones[index]),
                      onTap: () => Navigator.pop(context, zones[index])))),
        ]));
  }
}
