import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _signup = false;
  bool _loading = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.mosque,
                            size: 52, color: Color(0xFF0F766E)),
                        const SizedBox(height: 12),
                        Text(
                          _signup ? 'অ্যাকাউন্ট তৈরি করুন' : 'স্বাগতম',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _signup
                              ? 'Ummah Assist ব্যবহার করতে সব তথ্য পূরণ করুন'
                              : 'চালিয়ে যেতে সাইন ইন করুন',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.grey.shade700,
                                  ),
                        ),
                        const SizedBox(height: 24),
                        if (_signup) ...[
                          TextFormField(
                            controller: _nameController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'পূর্ণ নাম',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return 'দয়া করে আপনার নাম লিখুন';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'ইমেইল ঠিকানা',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (value) {
                            final email = (value ?? '').trim();
                            if (email.isEmpty || !email.contains('@')) {
                              return 'সঠিক ইমেইল দিন';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _hidePassword,
                          textInputAction: _signup
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onFieldSubmitted: (_) => _submitEmail(),
                          decoration: InputDecoration(
                            labelText: 'পাসওয়ার্ড',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword),
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').length < 6) {
                              return 'পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে';
                            }
                            return null;
                          },
                        ),
                        if (_signup) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _hidePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submitEmail(),
                            decoration: const InputDecoration(
                              labelText: 'পাসওয়ার্ড নিশ্চিত করুন',
                              prefixIcon: Icon(Icons.lock_reset_outlined),
                            ),
                            validator: (value) {
                              if (value != _passwordController.text) {
                                return 'পাসওয়ার্ড মিলছে না';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _loading ? null : _submitEmail,
                          icon: _loading
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  _signup ? Icons.person_add_alt : Icons.login),
                          label:
                              Text(_signup ? 'অ্যাকাউন্ট তৈরি করুন' : 'লগইন'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _signInWithGoogle,
                          icon: const Icon(Icons.g_mobiledata, size: 28),
                          label: const Text('Google দিয়ে সাইন ইন করুন'),
                        ),
                        if (!_signup)
                          TextButton(
                            onPressed: _loading ? null : _resetPassword,
                            child: const Text('পাসওয়ার্ড ভুলে গেছেন?'),
                          ),
                        const Divider(height: 28),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                    _signup = !_signup;
                                  }),
                          child: Text(
                            _signup
                                ? 'ইতিমধ্যে অ্যাকাউন্ট আছে? লগইন করুন'
                                : 'কোন অ্যাকাউন্ট নেই? সাইন আপ করুন',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitEmail() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _loading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (_signup) {
        final credential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        final name = _nameController.text.trim();
        await credential.user?.updateDisplayName(name);
        await _saveUserDocument(credential.user, displayName: name);
      } else {
        final credential =
            await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        await _saveUserDocument(credential.user);
      }
    } on FirebaseAuthException catch (error) {
      _showError(_authMessage(error));
    } catch (_) {
      _showError('অনাকাঙ্ক্ষিত সমস্যা হয়েছে। আবার চেষ্টা করুন।');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      await _saveUserDocument(result.user);
    } on FirebaseAuthException catch (error) {
      _showError(_authMessage(error));
    } catch (_) {
      _showError('Google সাইন ইন করতে সমস্যা হয়েছে।');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('পাসওয়ার্ড রিসেট করতে প্রথমে ইমেইল দিন');
      return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('পাসওয়ার্ড রিসেট লিংক পাঠানো হয়েছে')),
        );
      }
    } on FirebaseAuthException catch (error) {
      _showError(_authMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveUserDocument(User? user, {String? displayName}) async {
    if (user == null) {
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'email': user.email ?? '',
      'displayName': displayName ?? user.displayName ?? '',
      'lastLogin': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _authMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'এই ইমেইলের সাথে ইতিমধ্যে একটি অ্যাকাউন্ট আছে';
      case 'invalid-email':
        return 'অবৈধ ইমেইল ঠিকানা';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'ইমেইল অথবা পাসওয়ার্ড ভুল';
      case 'weak-password':
        return 'পাসওয়ার্ড খুবই দুর্বল';
      case 'too-many-requests':
        return 'অনেক ব্যর্থ প্রচেষ্টা। পরে আবার চেষ্টা করুন';
      case 'network-request-failed':
        return 'ইন্টারনেট সংযোগ সমস্যা';
      default:
        return 'অথেনটিকেশন সমস্যা হয়েছে: ${error.code}';
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
