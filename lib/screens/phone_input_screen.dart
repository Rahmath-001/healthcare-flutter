import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/routes.dart';
import '../core/service_providers.dart';
import '../core/theme/app_palette.dart';
import '../core/theme/app_tokens.dart';
import '../l10n/l10n.dart';
import '../services/carrier_service.dart';
import '../utils/debouncer.dart';
import '../utils/phone_validator.dart';
import '../widgets/primary_button.dart';

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
        _snack(result.reason ?? context.l10n.phoneVoipRejected);
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

  Widget? _phoneSuffix(BuildContext context) {
    if (_phoneValid == null) return null;
    // Theme tones, not `Colors.green`/`Colors.red`: the raw material greens
    // fail contrast on the dark surface, and the red one is a shade the app
    // uses nowhere else.
    return Icon(
      _phoneValid! ? Icons.check_circle : Icons.cancel,
      color: _phoneValid! ? context.tones.success : context.tones.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Android can auto-retrieve the SMS code and complete sign-in before the
    // user ever reaches the OTP screen. The router's redirect owns where they
    // go next, so this screen no longer navigates on sign-in itself.

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.phoneTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: Breakpoints.readableWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.xl,
                vertical: Insets.lg,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: Insets.sm),
                    Text(
                      context.l10n.phoneSubtitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Insets.sm),
                    Text(
                      context.l10n.phoneIndiaOnly,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: Insets.gutter),
                    TextFormField(
                      controller: _ctrl,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      maxLength: 10,
                      enabled: !_loading,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        prefixText: '+91  ',
                        labelText: context.l10n.phoneLabel,
                        counterText: '',
                        suffixIcon: _phoneSuffix(context),
                      ),
                      validator: (v) => PhoneValidator.isValidNational(v ?? '')
                          ? null
                          : context.l10n.phoneInvalid,
                    ),
                    const SizedBox(height: Insets.xl),
                    PrimaryButton(
                      label: context.l10n.phoneSendCode,
                      onPressed: _submit,
                      loading: _loading,
                    ),
                    // The carrier check used to be a translucent scrim with
                    // fake skeleton bars drawn over the form the user had just
                    // filled in — a placeholder standing in for content that
                    // already existed and was still on screen underneath. The
                    // button's own spinner reports the wait; this line says
                    // what is being waited on.
                    const SizedBox(height: Insets.md),
                    AnimatedOpacity(
                      opacity: _loading ? 1 : 0,
                      duration: Motion.of(context, Motion.fast),
                      child: Text(
                        context.l10n.phoneCheckingCarrier,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
