import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/hospital.dart';
import 'hospital_controller.dart';

/// The hospital-admin work area. It collects proposals; it never alters an
/// already-verified public organisation or provider record from the handset.
class HospitalManageScreen extends ConsumerStatefulWidget {
  const HospitalManageScreen({super.key});

  @override
  ConsumerState<HospitalManageScreen> createState() =>
      _HospitalManageScreenState();
}

class _HospitalManageScreenState extends ConsumerState<HospitalManageScreen> {
  final _profileKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _postalCode = TextEditingController();
  final _providerId = TextEditingController();
  bool _profileSubmitting = false;
  bool _providerSubmitting = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _postalCode.dispose();
    _providerId.dispose();
    super.dispose();
  }

  void _fillIfUntouched(HospitalDirectoryEntry hospital) {
    if (_name.text.isNotEmpty) return;
    _name.text = hospital.name;
    _address.text = hospital.address;
    _city.text = hospital.city;
    _state.text = hospital.state;
    _postalCode.text = hospital.postalCode;
  }

  Future<void> _submitProfile() async {
    if (!_profileKey.currentState!.validate()) return;
    setState(() => _profileSubmitting = true);
    try {
      await ref.read(hospitalRepositoryProvider).submitProfileChange(
            name: _name.text.trim(),
            address: _address.text.trim(),
            city: _city.text.trim(),
            state: _state.text.trim(),
            postalCode: _postalCode.text.trim(),
          );
      ref.invalidate(hospitalManagementRequestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Organisation update sent for MiDoctor review.'),
        ));
      }
    } on Failure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) setState(() => _profileSubmitting = false);
    }
  }

  Future<void> _requestProvider() async {
    final id = _providerId.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the provider’s MiDoctor ID.')),
      );
      return;
    }
    setState(() => _providerSubmitting = true);
    try {
      await ref.read(hospitalRepositoryProvider).requestAffiliation(id);
      _providerId.clear();
      ref.invalidate(hospitalManagementRequestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Provider affiliation sent for MiDoctor review.'),
        ));
      }
    } on Failure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) setState(() => _providerSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hospital = ref.watch(myHospitalProvider);
    final requests = ref.watch(hospitalManagementRequestsProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage hospital'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Organisation'),
              Tab(text: 'Provider network'),
            ],
          ),
        ),
        body: hospital.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: FilledButton(
              onPressed: () => ref.invalidate(myHospitalProvider),
              child: const Text('Try again'),
            ),
          ),
          data: (value) {
            _fillIfUntouched(value);
            return TabBarView(
              children: [
                _OrganisationForm(
                  formKey: _profileKey,
                  name: _name,
                  address: _address,
                  city: _city,
                  state: _state,
                  postalCode: _postalCode,
                  submitting: _profileSubmitting,
                  onSubmit: _submitProfile,
                  requests: requests,
                ),
                _ProviderNetworkForm(
                  providerId: _providerId,
                  submitting: _providerSubmitting,
                  onSubmit: _requestProvider,
                  requests: requests,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OrganisationForm extends StatelessWidget {
  const _OrganisationForm({
    required this.formKey,
    required this.name,
    required this.address,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.submitting,
    required this.onSubmit,
    required this.requests,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController name;
  final TextEditingController address;
  final TextEditingController city;
  final TextEditingController state;
  final TextEditingController postalCode;
  final bool submitting;
  final VoidCallback onSubmit;
  final AsyncValue<List<HospitalManagementRequest>> requests;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _ReviewNotice(
            text:
                'These details are currently published. Submit a change for MiDoctor operations to verify before the public directory is updated.',
          ),
          const SizedBox(height: 20),
          Form(
            key: formKey,
            child: Column(
              children: [
                _RequiredField(controller: name, label: 'Hospital name'),
                const SizedBox(height: 14),
                _RequiredField(
                  controller: address,
                  label: 'Published address',
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                _RequiredField(controller: city, label: 'City'),
                const SizedBox(height: 14),
                _RequiredField(controller: state, label: 'State'),
                const SizedBox(height: 14),
                _RequiredField(
                  controller: postalCode,
                  label: 'Postal code',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: submitting ? null : onSubmit,
                    icon: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: const Text('Submit for review'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('Organisation requests',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _RequestList(requests: requests, kind: 'PROFILE_CHANGE'),
        ],
      );
}

class _ProviderNetworkForm extends StatelessWidget {
  const _ProviderNetworkForm({
    required this.providerId,
    required this.submitting,
    required this.onSubmit,
    required this.requests,
  });

  final TextEditingController providerId;
  final bool submitting;
  final VoidCallback onSubmit;
  final AsyncValue<List<HospitalManagementRequest>> requests;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _ReviewNotice(
            text:
                'Request only a provider who has agreed to join your organisation. MiDoctor verifies the affiliation and credentials before it appears publicly.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: providerId,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'Provider’s MiDoctor ID',
              helperText: 'Use the ID supplied by the provider; do not enter a patient record number.',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Request affiliation review'),
            ),
          ),
          const SizedBox(height: 28),
          Text('Provider requests',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _RequestList(requests: requests, kind: 'PROVIDER_AFFILIATION'),
        ],
      );
}

class _RequiredField extends StatelessWidget {
  const _RequiredField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Enter $label.'
            : null,
      );
}

class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _RequestList extends StatelessWidget {
  const _RequestList({required this.requests, required this.kind});

  final AsyncValue<List<HospitalManagementRequest>> requests;
  final String kind;

  @override
  Widget build(BuildContext context) => AsyncView<List<HospitalManagementRequest>>(
        value: requests,
        onRetry: () =>
            ProviderScope.containerOf(context).invalidate(hospitalManagementRequestsProvider),
        data: (items) {
          final visible = items.where((request) => request.kind == kind).toList();
          if (visible.isEmpty) {
            return Text(
              kind == 'PROFILE_CHANGE'
                  ? 'No organisation changes have been submitted.'
                  : 'No provider affiliations are awaiting review.',
            );
          }
          return Column(
            children: [
              for (final request in visible)
                Card(
                  child: ListTile(
                    leading: Icon(request.isPending
                        ? Icons.schedule_outlined
                        : request.status == 'APPROVED'
                            ? Icons.verified_outlined
                            : Icons.error_outline),
                    title: Text(request.providerName ?? request.title),
                    subtitle: Text(
                      '${request.status[0]}${request.status.substring(1).toLowerCase()} · ${request.requestedAt.toLocal().toString().substring(0, 16)}'
                      '${request.rejectionReason == null ? '' : '\n${request.rejectionReason}'}',
                    ),
                  ),
                ),
            ],
          );
        },
      );
}
