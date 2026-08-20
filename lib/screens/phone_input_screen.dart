import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/routes.dart';
import '../core/service_providers.dart';
import '../services/carrier_service.dart';
import '../utils/debouncer.dart';
import '../utils/phone_validator.dart';
import '../widgets/primary_button.dart';
import '../widgets/shimmer_placeholder.dart';

class PhoneInputScreen extends ConsumerStatefulWidget {
  final String? displayName;

  const PhoneInputScreen({super.key, this.displayName});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _carrier = CarrierService();
  final _debouncer = Debouncer();
  bool _loading = false;
  bool? _phoneValid;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onPhoneChanged);
  }

  void _onPhoneChanged() {
    _debouncer.run(() {
      if (mounted) {
        final text = _ctrl.text;
        setState(() {
          _phoneValid =
              text.isEmpty ? null : PhoneValidator.isValidNational(text);
        });
      }
    });
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    final e164 = PhoneValidator.toE164(_ctrl.text);
    final auth = ref.read(authServiceProvider);

    final result = await _carrier.verify(e164);
    if (!result.ok) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(result.reason ??
            'Only Airtel, Jio or Vi mobile numbers are allowed. VoIP not permitted.');
      }
      return;
    }

    await auth.startPhoneAuth(
      e164: e164,
      onCodeSent: () {
        if (!mounted) return;
        setState(() => _loading = false);
        context.push(
          Uri(
            path: Routes.otp,
            queryParameters: {
              'phone': e164,
              if (widget.displayName != null) 'name': widget.displayName!,
            },
          ).toString(),
        );
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

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Widget? get _phoneSuffix {
    if (_phoneValid == null) return null;
    return Icon(
      _phoneValid! ? Icons.check_circle : Icons.cancel,
      color: _phoneValid! ? Colors.green : Colors.red,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Android can auto-retrieve the SMS code and complete sign-in before the
    // user ever reaches the OTP screen. The router's redirect owns where they
    // go next, so this screen no longer navigates on sign-in itself.

    return Scaffold(
      appBar: AppBar(title: const Text('Phone number')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Stack(
            children: [
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Text('Enter your mobile number',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                        'India only • Airtel, Jio or Vi • VoIP numbers not allowed'),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _ctrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        prefixText: '+91  ',
                        labelText: 'Mobile number',
                        counterText: '',
                        border: const OutlineInputBorder(),
                        suffixIcon: _phoneSuffix,
                      ),
                      validator: (v) => PhoneValidator.isValidNational(v ?? '')
                          ? null
                          : 'Enter a valid 10-digit Indian mobile number',
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: 'Send OTP',
                      onPressed: _submit,
                      loading: _loading,
                    ),
                  ],
                ),
              ),
              // Shimmer overlay during carrier check
              if (_loading)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _loading ? 0.7 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        padding: const EdgeInsets.only(top: 80),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShimmerPlaceholder.rect(height: 16, width: 200),
                            const SizedBox(height: 16),
                            ShimmerPlaceholder.rect(height: 56),
                            const SizedBox(height: 16),
                            Center(
                              child: Text('Verifying carrier...',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
