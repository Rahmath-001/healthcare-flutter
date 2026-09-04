import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/async_view.dart';
import '../../providers_search/presentation/doctor_search_screen.dart';
import '../domain/hospital.dart';
import 'hospital_controller.dart';

/// Public, patient-safe presentation of one approved hospital.
class HospitalDetailScreen extends ConsumerWidget {
  const HospitalDetailScreen({
    super.key,
    required this.hospitalId,
    this.publicBrowse = false,
  });

  final String hospitalId;
  final bool publicBrowse;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Hospital details')),
        body: AsyncView<HospitalDirectoryEntry>(
          value: ref.watch(hospitalByIdProvider(hospitalId)),
          onRetry: () => ref.invalidate(hospitalByIdProvider(hospitalId)),
          data: (hospital) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(hospitalByIdProvider(hospitalId));
              ref.invalidate(hospitalDoctorsProvider(hospitalId));
              await ref.read(hospitalByIdProvider(hospitalId).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _PublicHospitalHeader(hospital: hospital),
                const SizedBox(height: 24),
                Text(
                  'Approved providers',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Clinicians shown here have an active MiDoctor approval.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                AsyncView(
                  value: ref.watch(hospitalDoctorsProvider(hospitalId)),
                  onRetry: () =>
                      ref.invalidate(hospitalDoctorsProvider(hospitalId)),
                  data: (doctors) => doctors.isEmpty
                      ? const _PublicProviderEmptyState()
                      : Column(
                          children: [
                            for (final doctor in doctors)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: DoctorCard(
                                  doctor: doctor,
                                  publicBrowse: publicBrowse,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _PublicHospitalHeader extends StatelessWidget {
  const _PublicHospitalHeader({required this.hospital});

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
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.surface,
                  foregroundColor: scheme.primary,
                  child: const Icon(Icons.local_hospital_outlined, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hospital.name, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 17,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'MiDoctor approved',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.location_on_outlined, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Location', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        '${hospital.address}\n${hospital.city}, ${hospital.state} ${hospital.postalCode}\n${hospital.country}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicProviderEmptyState extends StatelessWidget {
  const _PublicProviderEmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.person_search_outlined, size: 30, color: scheme.primary),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Provider network is being set up'),
                  SizedBox(height: 4),
                  Text(
                    'No affiliated provider is currently available to book through MiDoctor.',
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
