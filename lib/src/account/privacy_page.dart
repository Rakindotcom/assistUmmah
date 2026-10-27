import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  static final Uri publicPolicy = Uri.https('assistummah.web.app', '/privacy');
  static final Uri deletionPage =
      Uri.https('assistummah.web.app', '/delete-account');

  Future<void> _open(BuildContext context, Uri url) async {
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } catch (_) {/* Offer a copyable address when no browser is available. */}
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('লিংক খোলা যায়নি: $url'),
      action: SnackBarAction(
          label: 'কপি',
          onPressed: () => Clipboard.setData(ClipboardData(text: '$url'))),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('গোপনীয়তা নীতি')),
        body: FutureBuilder<String>(
          future: rootBundle.loadString('assets/legal/privacy.bn.json'),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                  child: Text('নীতি লোড করা যায়নি। আবার পৃষ্ঠাটি খুলুন।'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final policy = jsonDecode(snapshot.data!) as Map<String, dynamic>;
            final sections =
                (policy['sections'] as List).cast<Map<String, dynamic>>();
            return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(padding: const EdgeInsets.all(24), children: [
                    Text('রবের পথে',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text('হালনাগাদ: ${policy['updated']}'),
                    for (final section in sections) ...[
                      const SizedBox(height: 24),
                      Text(section['heading'] as String,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      SelectableText(section['body'] as String),
                    ],
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                        onPressed: () => _open(context, publicPolicy),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('ওয়েবসাইটে নীতি পড়ুন')),
                    OutlinedButton.icon(
                        onPressed: () => _open(context, deletionPage),
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('ওয়েব থেকে অ্যাকাউন্ট মুছুন')),
                    TextButton(
                        onPressed: () => _open(
                            context, Uri.parse(policy['supportUrl'] as String)),
                        child: const Text('সহায়তা ও যোগাযোগ')),
                    if ((policy['supportEmail'] as String).isNotEmpty)
                      TextButton(
                          onPressed: () => _open(
                              context,
                              Uri(
                                  scheme: 'mailto',
                                  path: policy['supportEmail'] as String)),
                          child: Text(policy['supportEmail'] as String)),
                  ]),
                ));
          },
        ),
      );
}
