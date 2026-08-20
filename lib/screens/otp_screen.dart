import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/service_providers.dart';
import '../widgets/primary_button.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String e164;
  final String? displayName;

  const OtpScreen({super.key, required this.e164, this.displayName});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  static const _cooldown = 30;
  int _remaining = _cooldown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _remaining = _cooldown;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        if (mounted) setState(() => _remaining = 0);
      } else {
        if (mounted) setState(() => _remaining--);
      }
    });
  }

  bool get _canResend => _remaining == 0 && !_loading;

  Future<void> _resend() async {
    if (!_canResend) return;
    setState(() => _loading = true);
    final auth = ref.read(authServiceProvider);
    await auth.startPhoneAuth(
      e164: widget.e164,
      onCodeSent: () {
        if (!mounted) return;
        setState(() => _loading = false);
        _startTimer();
        _snack('Code resent');
      },
      onAutoVerified: () {
        if (mounted) setState(() => _loading = false);
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() => _loading = false);
        _snack(msg);
      },
    );
  }

  Future<void> _verify() async {
    final code = _ctrl.text.trim();
    if (code.length != 6) {
      _snack('Enter the 6-digit code');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(authServiceProvider)
          .verifyOtp(code, displayName: widget.displayName);
      await ref
          .read(sessionControllerProvider.notifier)
          .completeFirebaseSignIn();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Invalid or expired code');
      }
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    // Auto-verification (test numbers, Android SMS retriever) can complete
    // sign-in while this screen is still on top. The router's redirect reacts
    // to the session change and moves the user on, so nothing to do here.

    return Scaffold(
      appBar: AppBar(title: const Text('Verify')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text('Enter the code',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Sent to ${widget.e164}'),
              const SizedBox(height: 24),
              // Pop-in animation on the OTP field
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutBack,
                builder: (_, value, child) => Opacity(
                  opacity: value,
                  child:
                      Transform.scale(scale: 0.9 + 0.1 * value, child: child),
                ),
                child: TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, letterSpacing: 8),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Verify',
                onPressed: _verify,
                loading: _loading,
              ),
              const SizedBox(height: 16),
              Center(
                child: _canResend
                    ? TextButton(
                        onPressed: _resend,
                        child: const Text('Resend code'),
                      )
                    : Text(
                        'Resend in ${_remaining}s',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
