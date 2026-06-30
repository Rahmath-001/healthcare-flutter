import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../utils/debouncer.dart';
import '../utils/page_transitions.dart';
import '../widgets/google_button.dart';
import '../widgets/primary_button.dart';
import 'phone_input_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _debouncer = Debouncer();
  bool _googleLoading = false;
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
      await context.read<AuthService>().signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Google sign-in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _phone() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).push(
      slideUpRoute(PhoneInputScreen(displayName: _nameCtrl.text.trim())),
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
      appBar: AppBar(title: const Text('Create account')),
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
                    labelText: 'Full name',
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
