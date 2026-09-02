import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/feature_providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_palette.dart';
import '../domain/organisation_registration.dart';

/// Captures the hospital/lab/home-health fields shown in the client wireframe.
/// Submits a server-side review request, or uses a fixture receipt in fixture mode.
class OrganisationRegistrationScreen extends ConsumerStatefulWidget {
  const OrganisationRegistrationScreen({super.key, required this.type});

  final String type;

  @override
  ConsumerState<OrganisationRegistrationScreen> createState() =>
      _OrganisationRegistrationScreenState();
}

class _OrganisationRegistrationScreenState
    extends ConsumerState<OrganisationRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _registrationNumber = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _zip = TextEditingController();
  final _state = TextEditingController();
  final _country = TextEditingController(text: 'India');
  bool _basicExpanded = true;
  bool _businessUnlocked = false;
  bool _businessExpanded = false;
  bool _submitting = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _registrationNumber,
      _email,
      _mobile,
      _address,
      _city,
      _zip,
      _state,
      _country,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _basicDetailsValid =>
      _name.text.trim().isNotEmpty &&
      _registrationNumber.text.trim().isNotEmpty &&
      _email.text.contains('@') &&
      _mobile.text.trim().length == 10;

  void _continueToBusiness() {
    if (!_basicDetailsValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete the basic information first.')),
      );
      return;
    }
    setState(() {
      _basicExpanded = false;
      _businessUnlocked = true;
      _businessExpanded = true;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(organisationRegistrationRepositoryProvider).submit(
            OrganisationRegistrationDraft(
              type: OrganisationTypeWire.fromLabel(widget.type),
              name: _name.text,
              registrationNumber: _registrationNumber.text,
              email: _email.text,
              phone: '+91${_mobile.text}',
              address: _address.text,
              city: _city.text,
              postalCode: _zip.text,
              state: _state.text,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration request submitted for review.'),
        ),
      );
      context.go(Routes.landing);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not submit the request. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = '${widget.type} Registration';
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
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                  'Register directly using your organisation contact details.'),
              const SizedBox(height: 24),
              _Section(
                title: 'Basic ${widget.type} Information',
                expanded: _basicExpanded,
                completed: _businessUnlocked,
                onToggle: () =>
                    setState(() => _basicExpanded = !_basicExpanded),
                children: [
                  _field(_name, '${widget.type} name'),
                  _field(_registrationNumber, 'Registration number'),
                  _field(_email, 'Email', type: TextInputType.emailAddress),
                  _field(
                    _mobile,
                    'Mobile number',
                    type: TextInputType.phone,
                    indiaMobile: true,
                  ),
                  FilledButton(
                    onPressed: _continueToBusiness,
                    child: const Text('Continue to Business Address'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'Business Address',
                expanded: _businessExpanded,
                enabled: _businessUnlocked,
                onToggle: _businessUnlocked
                    ? () =>
                        setState(() => _businessExpanded = !_businessExpanded)
                    : null,
                children: [
                  _field(_address, 'Address'),
                  _field(_city, 'City'),
                  _field(_zip, 'Zip code', type: TextInputType.number),
                  _field(_state, 'State'),
                  _field(_country, 'Country', readOnly: true),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                      child: FilledButton(
                          onPressed: _submitting ? null : _submit,
                          child: Text(
                            _submitting ? 'Submitting…' : 'Register',
                          ))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () => context.go(Routes.landing),
                          child: const Text('Cancel'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? type,
    bool indiaMobile = false,
    bool readOnly = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: type,
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
          validator: (value) {
            if (indiaMobile && !RegExp(r'^[6-9]\d{9}$').hasMatch(value ?? '')) {
              return 'Enter a valid 10-digit Indian mobile number';
            }
            return value == null || value.trim().isEmpty
                ? 'Enter $label'
                : null;
          },
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({
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
                            'Complete the previous section to continue.',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
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
