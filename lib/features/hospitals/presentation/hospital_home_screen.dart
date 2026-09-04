import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../shared/widgets/async_view.dart';
import '../../providers_search/presentation/doctor_search_screen.dart';
import '../domain/hospital.dart';
import 'hospital_controller.dart';

/// The read-only workspace for a provisioned hospital administrator.
///
/// Hospital verification and clinician approval are operations workflows. This
/// screen reports the organisation's live, approved data and network; it never
/// implies that a hospital administrator can approve a provider or alter an
/// audited registration from a phone.
class HospitalHomeScreen extends ConsumerWidget {
  const HospitalHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Hospital workspace')),
        body: AsyncView<HospitalDirectoryEntry>(
          value: ref.watch(myHospitalProvider),
          onRetry: () => ref.invalidate(myHospitalProvider),
          data: (hospital) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myHospitalProvider);
              ref.invalidate(hospitalDoctorsProvider(hospital.id));
              await ref.read(myHospitalProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _HospitalSummary(hospital: hospital),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push(Routes.hospitalManage),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('Manage organisation and providers'),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Provider network',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Only clinicians approved by MiDoctor operations appear here.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                AsyncView(
                  value: ref.watch(hospitalDoctorsProvider(hospital.id)),
                  onRetry: () =>
                      ref.invalidate(hospitalDoctorsProvider(hospital.id)),
                  data: (doctors) => doctors.isEmpty
                      ? const _ProviderNetworkEmptyState()
                      : Column(
                          children: [
                            for (final doctor in doctors)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: DoctorCard(doctor: doctor),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
                const _SupportNotice(),
              ],
            ),
          ),
        ),
      );
}

class _HospitalSummary extends StatelessWidget {
  const _HospitalSummary({required this.hospital});

  final HospitalDirectoryEntry hospital;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: scheme.primaryContainer,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.surface,
                  foregroundColor: scheme.primary,
                  child: const Icon(Icons.local_hospital_outlined, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hospital.name, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Verified organisation',
                              style: theme.textTheme.labelLarge,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Published location', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.location_on_outlined, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${hospital.address}\n${hospital.city}, ${hospital.state} ${hospital.postalCode}\n${hospital.country}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderNetworkEmptyState extends StatelessWidget {
  const _ProviderNetworkEmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.groups_outlined, size: 30, color: scheme.primary),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No approved providers yet'),
                  SizedBox(height: 4),
                  Text(
                    'Providers will appear after their affiliation and credentials are reviewed by MiDoctor operations.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportNotice extends StatelessWidget {
  const _SupportNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
            'Organisation updates and provider affiliations are submitted for MiDoctor review before they reach the public directory.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
