import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/router/routes.dart';
import '../core/service_providers.dart';
import '../l10n/l10n.dart';
import '../utils/debouncer.dart';
import '../widgets/apple_button.dart';
import '../widgets/google_button.dart';
import '../widgets/primary_button.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _debouncer = Debouncer();
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool? _nameValid;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    _debouncer.run(() {
      if (mounted) {
        setState(() => _nameValid = _nameCtrl.text.trim().length >= 2);
      }
    });
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _google() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      // Firebase proved who they are; this turns that into a session
      // that says what they may do. Without it the router sees no
      // session and bounces straight back to sign-in.
      await ref
          .read(sessionControllerProvider.notifier)
          .completeFirebaseSignIn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Google sign-in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _apple() async {
    setState(() => _appleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithApple();
      await ref
          .read(sessionControllerProvider.notifier)
          .completeFirebaseSignIn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Apple sign-in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  void _phone() {
    if (!_formKey.currentState!.validate()) return;
    context.push(
      Uri(
        path: Routes.phone,
        queryParameters: {'name': _nameCtrl.text.trim()},
      ).toString(),
    );
  }

  Widget? get _nameSuffix {
    if (_nameValid == null) return null;
    return Icon(
      _nameValid! ? Icons.check_circle : Icons.cancel,
      color: _nameValid! ? Colors.green : Colors.red,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.authCreateAccount)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text('Tell us your name',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.l10n.editProfileFullName,
                    border: const OutlineInputBorder(),
                    suffixIcon: _nameSuffix,
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: 24),
                PrimaryButton(label: 'Continue with phone', onPressed: _phone),
                const SizedBox(height: 14),
                GoogleButton(onPressed: _google, loading: _googleLoading),
                ...ref.watch(appleSignInAvailableProvider).maybeWhen(
                      data: (available) => available
                          ? [
                              const SizedBox(height: 14),
                              AppleButton(
                                  onPressed: _apple, loading: _appleLoading),
                            ]
                          : const <Widget>[],
                      orElse: () => const <Widget>[],
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
