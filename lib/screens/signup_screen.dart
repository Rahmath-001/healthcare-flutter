import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/router/routes.dart';
import '../core/service_providers.dart';
import '../core/session/user_role.dart';
import '../core/theme/app_palette.dart';
import '../features/auth/presentation/role_selection_screen.dart';
import '../widgets/apple_button.dart';
import '../widgets/google_button.dart';

/// Patient and provider registration form from the client wireframe.
/// The local mock OTP uses the same short, time-boxed verification interaction.
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
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _basicExpanded = true;
  bool _addressExpanded = false;

  @override
  void dispose() {
    for (final controller in [
      _firstName,
      _lastName,
      _email,
      _mobile,
      _house,
      _street,
      _city,
      _zip,
      _state,
      _country,
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
      _mobile.text.trim().length == 10;

  Future<void> _google() async {
    setState(() => _googleLoading = true);
    try {
      // A person sent here from Login has already completed Google's account
      // chooser. Reuse that Firebase identity so accepting the terms creates
      // the MiDoctor user/session without a second, confusing sign-in prompt.
      final auth = ref.read(authServiceProvider);
      if (!auth.isSignedIn) await auth.signInWithGoogle();
      await ref
          .read(sessionControllerProvider.notifier)
          .completeFirebaseSignIn();
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
      final auth = ref.read(authServiceProvider);
      if (!auth.isSignedIn) await auth.signInWithApple();
      await ref
          .read(sessionControllerProvider.notifier)
          .completeFirebaseSignIn();
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

  void _register() {
    if (!_basicDetailsValid || !_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete your registration details first.')),
      );
      return;
    }
    // This is real Firebase phone verification, not the old local OTP sheet.
    // The terms and requested role are already held by the registration flow;
    // OtpScreen will exchange the verified Firebase identity with MiDoctor.
    context.push(
      Uri(
        path: Routes.phone,
        queryParameters: {
          'name': '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim(),
          'phone': _mobile.text.trim(),
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = ref.watch(requestedRoleProvider) == UserRole.provider;
    final title =
        isProvider ? 'Doctor / Provider Registration' : 'Patient Registration';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MiDoctor'),
        leading: IconButton(
          tooltip: 'Cancel registration',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go(Routes.landing),
        ),
      ),
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
                  const Text(
                      'Register with Google, Apple, or your mobile phone.'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: GoogleButton(
                              onPressed: _google, loading: _googleLoading)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: AppleButton(
                              onPressed: _apple, loading: _appleLoading)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _ProgressSection(
                    title: 'Basic Information',
                    expanded: _basicExpanded,
                    completed: false,
                    onToggle: () =>
                        setState(() => _basicExpanded = !_basicExpanded),
                    children: [
                      _field(_firstName, 'First name',
                          capitalization: TextCapitalization.words),
                      _field(_lastName, 'Last name',
                          capitalization: TextCapitalization.words),
                      _field(_email, 'Email',
                          type: TextInputType.emailAddress,
                          validator: (value) =>
                              value != null && value.contains('@')
                                  ? null
                                  : 'Enter a valid email'),
                      _field(_mobile, 'Mobile number',
                          type: TextInputType.phone, indiaMobile: true),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _ProgressSection(
                    title: 'Home Address',
                    expanded: _addressExpanded,
                    onToggle: () =>
                        setState(() => _addressExpanded = !_addressExpanded),
                    children: [
                      _field(_house, 'House number'),
                      _field(_street, 'Street'),
                      _field(_city, 'City'),
                      _field(_zip, 'Zip code', type: TextInputType.number),
                      _field(_state, 'State'),
                      _field(_country, 'Country', readOnly: true),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _register,
                          child: const Text('Register'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.go(Routes.landing),
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
    bool indiaMobile = false,
    bool readOnly = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: type,
          textCapitalization: capitalization,
          readOnly: readOnly,
          enableInteractiveSelection: !readOnly,
          maxLength: indiaMobile ? 10 : null,
          inputFormatters:
              indiaMobile ? [FilteringTextInputFormatter.digitsOnly] : null,
          onChanged: readOnly ? null : (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            prefixText: indiaMobile ? '+91  ' : null,
            suffixIcon: readOnly ? const Icon(Icons.lock_outline) : null,
            counterText: indiaMobile ? '' : null,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            contentPadding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
          ),
          validator: validator ??
              (value) {
                if (indiaMobile &&
                    !RegExp(r'^[6-9]\d{9}$').hasMatch(value ?? '')) {
                  return 'Enter a valid 10-digit Indian mobile number';
                }
                return _required(value, label.toLowerCase());
              },
        ),
      );
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({
    required this.title,
    required this.expanded,
    this.enabled = true,
    this.completed = false,
    required this.onToggle,
    required this.children,
  });

  final String title;
  final bool expanded;
  final bool enabled;
  final bool completed;
  final VoidCallback? onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = context.tones;
    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    enabled
                        ? (completed ? Icons.check_circle : Icons.edit_outlined)
                        : Icons.lock_outline,
                    color: !enabled
                        ? theme.colorScheme.outline
                        : completed
                            ? tones.success
                            : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        if (!enabled)
                          Text(
                            'Complete and verify the previous section to continue.',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  Icon(expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(children: children),
            ),
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }
}
