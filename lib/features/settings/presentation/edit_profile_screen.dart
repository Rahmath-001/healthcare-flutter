import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/patient_profile.dart';
import 'account_controller.dart';

/// Patient profile editing.
///
/// The RBAC matrix grants Patient "Update Own Profile" but the spec defines no
/// module for it, so there was previously nowhere to exercise that permission.
///
/// These fields are clinical (blood group, allergies, chronic conditions) and
/// live server-side in `patient_profiles`. They were previously written to
/// plaintext SharedPreferences, which is why that data is purged on upgrade.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  BloodGroup? _bloodGroup;
  Gender? _gender;
  DateTime? _dob;
  bool _saving = false;
  bool _loaded = false;

  /// Fills the form from the server's copy exactly once.
  ///
  /// Guarded because this runs from `build`, which reruns on every keystroke —
  /// without the flag it would overwrite whatever the user is typing.
  void _hydrate(PatientProfile p) {
    if (_loaded) return;
    _loaded = true;
    _nameCtrl.text = p.displayName ?? '';
    _allergiesCtrl.text = p.allergies.join(', ');
    _conditionsCtrl.text = p.chronicConditions.join(', ');
    _emergencyNameCtrl.text = p.emergencyContactName ?? '';
    _emergencyPhoneCtrl.text = p.emergencyContactPhone ?? '';
    _dob = p.dateOfBirth;
    _gender = p.gender;
    _bloodGroup = p.bloodGroup;
  }

  /// Splits a comma-separated field into the list the API expects.
  static List<String> _items(String raw) => raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _allergiesCtrl.dispose();
    _conditionsCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: context.l10n.editProfileDateOfBirth,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  /// Persists via `PUT /v1/me`. Deliberately not cached locally: this is
  /// clinical data and does not belong on the device.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await ref.read(accountRepositoryProvider).updateProfile(
            PatientProfileDraft(
              displayName: _nameCtrl.text.trim(),
              dateOfBirth: _dob,
              gender: _gender,
              bloodGroup: _bloodGroup,
              allergies: _items(_allergiesCtrl.text),
              chronicConditions: _items(_conditionsCtrl.text),
              emergencyContactName: _emergencyNameCtrl.text.trim(),
              emergencyContactPhone: _emergencyPhoneCtrl.text.trim(),
            ),
          );
      ref.invalidate(patientProfileProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.editProfileUpdated)),
      );
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(patientProfileProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.editProfileTitle)),
      body: AsyncView<PatientProfile>(
        value: profile,
        onRetry: () => ref.invalidate(patientProfileProvider),
        data: (p) {
          _hydrate(p);
          return _form(context);
        },
      ),
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: context.l10n.editProfileFullName,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v ?? '').trim().length < 2
                        ? context.l10n.editProfileNameRequired
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.cake_outlined),
                      title: Text(context.l10n.editProfileDateOfBirth),
                      subtitle: Text(
                        _dob == null
                            ? context.l10n.onboardingNotSet
                            : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickDob,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(context.l10n.editProfileGender,
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: Gender.values
                        .map((g) => ChoiceChip(
                              label: Text(g.label),
                              selected: _gender == g,
                              onSelected: (_) => setState(() => _gender = g),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  Text(context.l10n.editProfileBloodGroup,
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: BloodGroup.values
                        .map((b) => ChoiceChip(
                              label: Text(b.label),
                              selected: _bloodGroup == b,
                              onSelected: (_) =>
                                  setState(() => _bloodGroup = b),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  // `autocorrect` and `enableSuggestions` are off on both
                  // clinical fields, and this is not a nicety. Android and iOS
                  // learn words typed into an ordinary field and keep them in
                  // the user's personal dictionary, where they resurface as
                  // keyboard suggestions in *other* apps. Typing "Sertraline"
                  // or an HIV medication here would otherwise leak a diagnosis
                  // into every messaging app on the phone — a disclosure with
                  // no consent record and no way to revoke it.
                  TextFormField(
                    controller: _allergiesCtrl,
                    maxLines: 2,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: context.l10n.editProfileAllergies,
                      hintText: context.l10n.editProfileAllergiesHint,
                      helperText: context.l10n.editProfileAllergiesHelp,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _conditionsCtrl,
                    maxLines: 2,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: context.l10n.editProfileConditions,
                      hintText: context.l10n.editProfileConditionsHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(context.l10n.editProfileEmergencyContact,
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emergencyNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: context.l10n.editProfileContactName,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emergencyPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: context.l10n.editProfilePhone,
                      prefixText: '+91 ',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 15, color: theme.colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Allergies and conditions are part of your medical '
                          'record. A doctor sees them only for a consultation '
                          'you have booked with them.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Text(context.l10n.editProfileSaveChanges),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
