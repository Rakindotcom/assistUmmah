import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import 'account/account_service.dart';
import 'account/privacy_page.dart';
import 'app.dart';
import 'diagnostics/diagnostics_service.dart';

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, this.initialize});
  final Future<void> Function()? initialize;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _busy = true;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (mounted) setState(() => _busy = true);
    try {
      if (widget.initialize != null) {
        await widget.initialize!();
      } else {
        if (!DefaultFirebaseOptions.isConfigured) {
          throw StateError('Firebase is not configured');
        }
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
              options: DefaultFirebaseOptions.currentPlatform);
        }
        await AccountService.clearPendingCache();
        try {
          await DiagnosticsService.initialize();
        } catch (_) {
          // Optional reporting cannot prevent the app from opening.
        }
      }
      if (mounted) {
        setState(() {
          _ready = true;
          _busy = false;
        });
      }
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'app startup',
      ));
      if (mounted) {
        setState(() {
          _ready = false;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => UmmahAssistApp(
        firebaseReady: _ready,
        home: _ready ? null : _StartupStatus(busy: _busy, onRetry: _start),
      );
}

class _StartupStatus extends StatelessWidget {
  const _StartupStatus({required this.busy, required this.onRetry});
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: busy
                    ? const [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text('রবের পথে চালু হচ্ছে…'),
                      ]
                    : [
                        const Icon(Icons.cloud_off_outlined, size: 48),
                        const SizedBox(height: 20),
                        Text('অ্যাপ চালু করা যায়নি',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        const Text(
                            'সংযোগ পরীক্ষা করে আবার চেষ্টা করুন। আপনার সংরক্ষিত তথ্য মুছে যায়নি।',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        FilledButton(
                            onPressed: onRetry,
                            child: const Text('আবার চেষ্টা করুন')),
                        TextButton(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => const PrivacyPage())),
                            child: const Text('গোপনীয়তা ও যোগাযোগ')),
                      ],
              )),
        ))),
      );
}
