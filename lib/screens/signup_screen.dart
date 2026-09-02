import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/router/routes.dart';
import '../core/service_providers.dart';
import '../core/session/user_role.dart';
import '../features/auth/presentation/role_selection_screen.dart';
import '../widgets/apple_button.dart';
import '../widgets/google_button.dart';

/// Patient and provider registration form from the client wireframe.
/// Phone verification continues in the existing secure phone/OTP screens.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _house = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _zip = TextEditingController();
  final _state = TextEditingController();
  final _country = TextEditingController(text: 'India');
  final _otp = TextEditingController();
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _otpSent = false;

  @override
  void dispose() {
    for (final controller in [
      _firstName, _lastName, _email, _mobile, _house, _street, _city, _zip,
      _state, _country, _otp,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value, String field) =>
      value == null || value.trim().isEmpty ? 'Enter $field' : null;

  bool get _basicDetailsValid =>
      _firstName.text.trim().isNotEmpty &&
      _lastName.text.trim().isNotEmpty &&
      _email.text.contains('@') &&
      _mobile.text.trim().length >= 8;

  Future<void> _google() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      await ref.read(sessionControllerProvider.notifier).completeFirebaseSignIn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google sign-in failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _apple() async {
    setState(() => _appleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithApple();
      await ref.read(sessionControllerProvider.notifier).completeFirebaseSignIn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apple sign-in failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  void _sendOtp() {
    if (!_basicDetailsValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete your basic information first.')),
      );
      return;
    }
    setState(() => _otpSent = true);
  }

  void _verifyOtp() {
    if (!_basicDetailsValid) return;
    context.push(Uri(
      path: Routes.phone,
      queryParameters: {
        'name': '${_firstName.text.trim()} ${_lastName.text.trim()}',
      },
    ).toString());
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = ref.watch(requestedRoleProvider) == UserRole.provider;
    final title = isProvider ? 'Doctor / Provider Registration' : 'Patient Registration';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('MiDoctor')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                children: [
                  Text(title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Register with Google, Apple, or your mobile phone.'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: GoogleButton(onPressed: _google, loading: _googleLoading)),
                      const SizedBox(width: 12),
                      Expanded(child: AppleButton(onPressed: _apple, loading: _appleLoading)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _RegistrationSection(
                    title: 'Basic Information',
                    children: [
                      _field(_firstName, 'First name', capitalization: TextCapitalization.words),
                      _field(_lastName, 'Last name', capitalization: TextCapitalization.words),
                      _field(_email, 'Email', type: TextInputType.emailAddress, validator: (value) => value != null && value.contains('@') ? null : 'Enter a valid email'),
                      _field(_mobile, 'Mobile number', type: TextInputType.phone),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _sendOtp,
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Send OTP'),
                  ),
                  if (_otpSent) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _otp,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Enter OTP'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _verifyOtp,
                          child: const Text('Validate OTP'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Verification continues on the secure phone screen.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _RegistrationSection(
                    title: 'Home Address',
                    children: [
                      _field(_house, 'House number'),
                      _field(_street, 'Street'),
                      _field(_city, 'City'),
                      _field(_zip, 'Zip code', type: TextInputType.number),
                      _field(_state, 'State'),
                      _field(_country, 'Country'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _otpSent ? _verifyOtp : _sendOtp,
                          child: Text(_otpSent ? 'Validate OTP' : 'Register'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? type,
    TextCapitalization capitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: type,
          textCapitalization: capitalization,
          decoration: InputDecoration(labelText: label),
          validator: validator ?? (value) => _required(value, label.toLowerCase()),
        ),
      );
}

class _RegistrationSection extends StatelessWidget {
  const _RegistrationSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      );
}
