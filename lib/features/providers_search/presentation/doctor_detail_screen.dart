import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/doctor.dart';
import 'doctor_search_controller.dart';

/// Doctor profile and expertise view from the client wireframe.
class DoctorDetailScreen extends ConsumerWidget {
  const DoctorDetailScreen({
    super.key,
    required this.doctorId,
    this.publicBrowse = false,
  });

  final String doctorId;
  final bool publicBrowse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorByIdProvider(doctorId));
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor Profile and Expertise')),
      body: AsyncView<Doctor>(
        value: doctor,
        onRetry: () => ref.invalidate(doctorByIdProvider(doctorId)),
        data: (value) => _DoctorProfile(
          doctor: value,
          publicBrowse: publicBrowse,
        ),
      ),
    );
  }
}

class _DoctorProfile extends StatelessWidget {
  const _DoctorProfile({required this.doctor, required this.publicBrowse});

  final Doctor doctor;
  final bool publicBrowse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 68,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.primary,
                  backgroundImage: doctor.photoUrl == null
                      ? null
                      : AssetImage(doctor.photoUrl!),
                  child: doctor.photoUrl == null
                      ? const Icon(Icons.person, size: 78)
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                doctor.name,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                doctor.specialtyLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text('About', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: .35),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    doctor.bio ?? 'Profile information is being updated.',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _ProfileDetails(doctor: doctor),
              const SizedBox(height: 12),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push(
                      publicBrowse
                          ? Routes.publicBooking(doctor.id)
                          : '${Routes.doctorSearch}/${doctor.id}/book',
                    ),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Book my appointment'),
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
          ),
        ),
      ],
    );
  }
}

class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({required this.doctor});

  final Doctor doctor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = <(String, String)>[
      ('Speciality', doctor.specialtyLabel),
      ('Experience', '${doctor.yearsExperience} years'),
      ('Location', '${doctor.hospital.city}, India'),
      ('Qualification', doctor.qualification),
      ('Hospital affiliation', doctor.hospital.name),
      ('Patient rating', '${doctor.rating.toStringAsFixed(1)} / 5'),
      ('Registration', doctor.registrationNumber),
      ('Consultation fee', Fmt.rupees(doctor.consultationFeeInr)),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          runSpacing: 16,
          children: facts
              .map(
                (fact) => SizedBox(
                  width: MediaQuery.sizeOf(context).width > 560
                      ? 250
                      : MediaQuery.sizeOf(context).width / 2 - 36,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fact.$1,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(fact.$2, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
