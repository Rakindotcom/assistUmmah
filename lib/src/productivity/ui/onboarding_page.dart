import 'package:flutter/material.dart';

import '../../widgets/app_brand.dart';
import '../domain/experience_options.dart';
import 'experience_strings.dart';

class ProductivityOnboardingPage extends StatefulWidget {
  const ProductivityOnboardingPage(
      {super.key,
      required this.timeZone,
      required this.onComplete,
      this.initialLanguage = 'bn'});
  final String timeZone, initialLanguage;
  final Future<void> Function(ExperienceOptions) onComplete;
  @override
  State<ProductivityOnboardingPage> createState() =>
      _ProductivityOnboardingPageState();
}

class _ProductivityOnboardingPageState
    extends State<ProductivityOnboardingPage> {
  late String _language;
  final _modules = <WorkspaceModule>{WorkspaceModule.personal};
  ExperienceTheme _theme = ExperienceTheme.system;
  bool _saving = false, _failed = false;
  @override
  void initState() {
    super.initState();
    _language = ['en', 'bn'].contains(widget.initialLanguage)
        ? widget.initialLanguage
        : 'en';
  }

  Future<void> _complete() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    final active = _modules.contains(WorkspaceModule.personal)
        ? WorkspaceModule.personal
        : _modules.firstWhere((module) => module != WorkspaceModule.faith);
    try {
      await widget.onComplete(ExperienceOptions(
          language: _language,
          timeZone: widget.timeZone,
          modules: _modules,
          theme: _theme,
          activeWorkspace: active.name,
          completedOnboarding: true));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ExperienceStrings(_language);
    final valid = _modules.any((module) => module != WorkspaceModule.faith);
    return Localizations.override(
        context: context,
        locale: Locale(_language),
        child: Scaffold(
          appBar: AppBar(title: const AppBrand(compact: true)),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              Text(
                  strings.text('Make room for what matters.',
                      'যা জরুরি, তার জন্য সময় রাখুন।'),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(strings.text(
                  'Capture your ideas, plan your day, and build a steady rhythm.',
                  'ভাবনাগুলো লিখুন, দিনটি সাজান, আর নিয়মিত এগিয়ে চলুন।')),
              const SizedBox(height: 28),
              Text(strings.text('Language', 'ভাষা'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 8, children: [
                for (final language in ['bn', 'en'])
                  ChoiceChip(
                      label: Text(language == 'bn' ? 'বাংলা' : 'English'),
                      selected: _language == language,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _language = language)),
              ]),
              const SizedBox(height: 28),
              Text(
                  strings.text('What would you like to organize?',
                      'কোন বিষয়গুলো গুছিয়ে নিতে চান?'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 8, children: [
                for (final module in WorkspaceModule.values
                    .where((module) => module != WorkspaceModule.faith))
                  FilterChip(
                      label: Text(strings.module(module)),
                      selected: _modules.contains(module),
                      onSelected: _saving
                          ? null
                          : (selected) => setState(() {
                                selected
                                    ? _modules.add(module)
                                    : _modules.remove(module);
                              })),
              ]),
              if (!valid)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(strings.text('Choose at least one workspace.',
                        'অন্তত একটি কর্মপরিসর বেছে নিন।'))),
              const SizedBox(height: 20),
              ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(strings.text('Optional modules', 'ঐচ্ছিক বিষয়')),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _modules.contains(WorkspaceModule.faith),
                      onChanged: _saving
                          ? null
                          : (enabled) => setState(() {
                                enabled
                                    ? _modules.add(WorkspaceModule.faith)
                                    : _modules.remove(WorkspaceModule.faith);
                              }),
                      title: Text(strings.module(WorkspaceModule.faith)),
                      subtitle: Text(strings.text(
                          'Prayer, Quran reading, duas and dhikr.',
                          'নামাজ, কুরআন রিডিং, দোয়া ও যিকির।')),
                    )
                  ]),
              const SizedBox(height: 20),
              Text(strings.text('Appearance', 'অ্যাপের রং'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 8, children: [
                for (final theme in ExperienceTheme.values)
                  ChoiceChip(
                      label: Text(switch (theme) {
                        ExperienceTheme.system =>
                          strings.text('System', 'ফোনের মতো'),
                        ExperienceTheme.light => strings.text('Light', 'হালকা'),
                        ExperienceTheme.dark => strings.text('Dark', 'গাঢ়'),
                      }),
                      selected: _theme == theme,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _theme = theme)),
              ]),
              const SizedBox(height: 28),
              if (_failed)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(strings.taskError('save-failed'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              FilledButton(
                  onPressed: _saving || !valid ? null : _complete,
                  child: Text(_saving
                      ? strings.text('Saving…', 'সংরক্ষণ হচ্ছে…')
                      : strings.text('Start my workspace', 'শুরু করুন'))),
              const SizedBox(height: 12),
              Text(
                  strings.text('You can change these choices in Settings.',
                      'সেটিংস থেকে এই পছন্দগুলো পরে বদলাতে পারবেন।'),
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ))),
        ));
  }
}
