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
  final _country = TextEditingController(text: 'India');

  @override
  void dispose() {
    _country.dispose();
    super.dispose();
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
              const Text('Register directly using your organisation contact details.'),
              const SizedBox(height: 24),
              _Section(
                title: 'Basic ${widget.type} Information',
                children: [
                  _field('${widget.type} name'),
                  _field('Registration number'),
                  _field('Email', type: TextInputType.emailAddress),
                  _field('Mobile number', type: TextInputType.phone),
                ],
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'Business Address',
                children: [
                  _field('Address'),
                  _field('City'),
                  _field('Zip code', type: TextInputType.number),
                  _field('State'),
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
                  Expanded(child: FilledButton(onPressed: _submit, child: const Text('Register'))),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, {TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          keyboardType: type,
          decoration: InputDecoration(labelText: label),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter $label'
              : null,
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
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
