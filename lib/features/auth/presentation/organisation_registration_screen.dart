import 'package:flutter/material.dart';

/// Captures the hospital/lab/home-health fields shown in the client wireframe.
/// Organisation requests are local demo data until a backend endpoint exists.
class OrganisationRegistrationScreen extends StatefulWidget {
  const OrganisationRegistrationScreen({super.key, required this.type});

  final String type;

  @override
  State<OrganisationRegistrationScreen> createState() =>
      _OrganisationRegistrationScreenState();
}

class _OrganisationRegistrationScreenState
    extends State<OrganisationRegistrationScreen> {
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
      _mobile.text.trim().length >= 8;

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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.type} registration request saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = '${widget.type} Registration';
    return Scaffold(
      appBar: AppBar(title: const Text('MiDoctor')),
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
                  _field(_mobile, 'Mobile number', type: TextInputType.phone),
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
                  TextFormField(
                    controller: _country,
                    decoration: const InputDecoration(labelText: 'Country'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your country'
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                      child: FilledButton(
                          onPressed: _submit, child: const Text('Register'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
          {TextInputType? type}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: type,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Enter $label' : null,
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
                        ? (completed
                            ? Icons.check_circle_outline
                            : Icons.edit_outlined)
                        : Icons.lock_outline,
                    color: enabled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
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
