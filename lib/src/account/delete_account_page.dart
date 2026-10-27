import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'account_service.dart';

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage(
      {super.key, required this.usesPassword, this.onDelete});
  final bool usesPassword;
  final Future<bool> Function(String? password)? onDelete;

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final _password = TextEditingController();
  bool _confirmed = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final accepted = await (widget.onDelete?.call(_password.text) ??
          AccountService.deleteAccount(password: _password.text));
      if (!mounted) return;
      if (accepted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('আপনার অ্যাকাউন্ট ও সংশ্লিষ্ট তথ্য মুছে ফেলা হয়েছে।'),
        ));
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = switch (error.code) {
            'wrong-password' ||
            'invalid-credential' =>
              'পাসওয়ার্ড সঠিক নয়। আবার চেষ্টা করুন।',
            'requires-recent-login' =>
              'নিরাপত্তার জন্য আবার পরিচয় নিশ্চিত করে মুছে ফেলা সম্পন্ন করুন।',
            'user-mismatch' =>
              'এই অ্যাকাউন্টের Google পরিচয় দিয়ে নিশ্চিত করুন।',
            'network-request-failed' =>
              'ইন্টারনেট সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।',
            _ => 'পরিচয় নিশ্চিত করা যায়নি। আবার সাইন ইন করে চেষ্টা করুন।',
          });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'মুছে ফেলা শেষ হয়নি। সংযোগ পরীক্ষা করে আবার চেষ্টা করুন। আগের ধাপগুলো আবার নিরাপদে চলবে।');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('অ্যাকাউন্ট মুছে ফেলুন')),
          body: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              Icon(Icons.person_remove_outlined,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 20),
              Text('এটি স্থায়ী পরিবর্তন',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text(
                  'আপনার অ্যাকাউন্ট, কাজ, নামাজ, গ্রোথ, কুরআন, যিকির, পরিচিতি ও সেটিংস মুছে ফেলা হবে। মোছা শুরু হলে অ্যাকাউন্টে নতুন তথ্য রাখা বন্ধ হবে। এই কাজ ফিরিয়ে নেওয়া যাবে না।'),
              const SizedBox(height: 12),
              const Text(
                  'মোছা শেষ না হওয়া পর্যন্ত অ্যাপটি খোলা রাখুন। সংযোগ বিচ্ছিন্ন হলে আবার সাইন ইন করে এখান থেকে মোছা সম্পন্ন করতে পারবেন। পুরনো সেশন থেকে তথ্য আবার তৈরি হওয়া ঠেকাতে শুধু অ্যাকাউন্ট পরিচিতির একটি খালি রোধচিহ্ন রাখা হয়। এই ডিভাইসের অবশিষ্ট ক্যাশ পরিষ্কারের জন্য অ্যাপটি বন্ধ করে আবার চালু করুন।'),
              const SizedBox(height: 20),
              if (widget.usesPassword)
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration:
                      const InputDecoration(labelText: 'বর্তমান পাসওয়ার্ড'),
                  onChanged: (_) => setState(() {}),
                )
              else
                const Text('Google দিয়ে আপনার পরিচয় আবার নিশ্চিত করতে হবে।'),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                    'আমি বুঝেছি, আমার অ্যাকাউন্ট ও সংশ্লিষ্ট তথ্য স্থায়ীভাবে মুছে ফেলা হবে।'),
                value: _confirmed,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _confirmed = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                        liveRegion: true,
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)))),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: _busy ||
                        !_confirmed ||
                        (widget.usesPassword && _password.text.isEmpty)
                    ? null
                    : _submit,
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('স্থায়ীভাবে মুছে ফেলার অনুরোধ করুন')),
              ),
            ]),
          )),
        ),
      );
}
