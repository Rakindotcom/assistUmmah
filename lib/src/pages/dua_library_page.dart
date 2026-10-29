import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../display_formatters.dart';
import '../dua_collection.dart';
import '../widgets/page_frame.dart';

class DuaLibraryPage extends StatefulWidget {
  const DuaLibraryPage({super.key});

  @override
  State<DuaLibraryPage> createState() => _DuaLibraryPageState();
}

class _DuaLibraryPageState extends State<DuaLibraryPage> {
  final _search = TextEditingController();
  String _category = 'সব';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ['সব', ...quranDuas.map((dua) => dua.category).toSet()];
    final results = quranDuas
        .where((dua) =>
            (_category == 'সব' || dua.category == _category) &&
            dua.matches(_search.text))
        .toList();
    return PageFrame(
        title: 'দোয়া সংগ্রহ',
        subtitle: 'কুরআনের দোয়া · ইন্টারনেট ছাড়াই পড়ুন',
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: 'দোয়া বা আয়াত খুঁজুন',
                hintText: 'যেমন: বাবা-মা, জ্ঞান, ২০:১১৪',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'সার্চ মুছুন',
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.close))),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final category in categories)
                  Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (_) =>
                              setState(() => _category = category))),
              ])),
          const SizedBox(height: 12),
          Text('${banglaNumber(results.length)}টি দোয়া',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
          if (results.isEmpty)
            const EmptyState(
                icon: Icons.search_off,
                message: 'এই অনুসন্ধানে কোনো দোয়া পাওয়া যায়নি'),
          for (final dua in results)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                  child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => DuaDetailPage(dua: dua))),
                child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(dua.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium)),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right, size: 20)
                          ]),
                          const SizedBox(height: 8),
                          Text(dua.arabic,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.rtl,
                              locale: const Locale('ar'),
                              style: const TextStyle(
                                  fontFamily: 'NotoNaskhArabic',
                                  fontSize: 26,
                                  height: 1.8)),
                          const SizedBox(height: 8),
                          Text(dua.displayReference,
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                        ])),
              )),
            ),
          const SizedBox(height: 8),
          const Text(
              'এখানে আয়াতের দোয়ার অংশ দেওয়া হয়েছে। প্রতিটি দোয়ার সঙ্গে পূর্ণ আয়াতের লিংক আছে। বাংলা অর্থ ভাবানুবাদ।'),
        ]);
  }
}

class DuaDetailPage extends StatelessWidget {
  const DuaDetailPage({super.key, required this.dua});
  final QuranDua dua;

  Future<void> _copy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: dua.copyText));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('দোয়া কপি হয়েছে')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('কপি করা যায়নি। আবার চেষ্টা করুন।')));
      }
    }
  }

  Future<void> _source(BuildContext context) async {
    try {
      if (await launchUrl(Uri.parse(dua.sourceUrl),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {/* The offline text stays available if no browser can open. */}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('লিংক খোলা যায়নি। দোয়াটি অফলাইনেও পড়তে পারবেন।')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('কুরআনের দোয়া')),
        body: PageFrame(
            title: dua.title,
            subtitle: '${dua.displayReference} · দোয়ার অংশ',
            children: [
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SelectableText(dua.arabic,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontFamily: 'NotoNaskhArabic',
                              fontSize: 32,
                              height: 2)))),
              const SizedBox(height: 24),
              Text('বাংলা অর্থ', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              SelectableText(dua.meaning,
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 12),
              Text('ভাবানুবাদ · ${dua.displayReference}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
              Wrap(spacing: 12, runSpacing: 12, children: [
                FilledButton.icon(
                    onPressed: () => _copy(context),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('দোয়া কপি করুন')),
                OutlinedButton.icon(
                    onPressed: () => _source(context),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('পূর্ণ আয়াত দেখুন')),
              ]),
            ]),
      );
}
