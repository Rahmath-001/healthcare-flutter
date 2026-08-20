import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/doctor.dart';
import 'doctor_search_controller.dart';

class DoctorDetailScreen extends ConsumerWidget {
  const DoctorDetailScreen({super.key, required this.doctorId});

  final String doctorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorByIdProvider(doctorId));

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.doctorTitle)),
      body: AsyncView<Doctor>(
        value: doctor,
        onRetry: () => ref.invalidate(doctorByIdProvider(doctorId)),
        data: (d) => _Body(doctor: d),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.doctor});

  final Doctor doctor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 36,
                    child: Text(
                      doctor.name.split(' ').last[0],
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(doctor.name, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          doctor.specialtyLabel,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: theme.colorScheme.primary),
                        ),
                        const SizedBox(height: 4),
                        Text(doctor.qualification,
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        StarRating(
                          rating: doctor.rating,
                          count: doctor.ratingCount,
                          size: 15,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Registration number is shown prominently, not buried. The
              // Telemedicine Practice Guidelines require the patient to be able
              // to see who is treating them and verify their registration.
              Card(
                margin: EdgeInsets.zero,
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.l10n.doctorMedicalRegistration,
                                style: theme.textTheme.bodySmall),
                            const SizedBox(height: 2),
                            Text(
                              doctor.registrationNumber,
                              style: theme.textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _StatsRow(doctor: doctor),
              const SizedBox(height: 20),

              if (doctor.bio != null) ...[
                Text(context.l10n.doctorAbout,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(doctor.bio!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 20),
              ],

              Text(context.l10n.doctorPractisesAt,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.local_hospital_outlined),
                  title: Text(doctor.hospital.name),
                  subtitle: Text(
                    [doctor.hospital.address, doctor.hospital.city]
                        .whereType<String>()
                        .join(', '),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(context.l10n.doctorLanguages,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: doctor.languages
                    .map((l) => Chip(
                          label: Text(l),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 20),

              Text(context.l10n.doctorConsultationFees,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: doctor.modes.map((m) {
                    return ListTile(
                      dense: true,
                      leading: Icon(switch (m) {
                        ConsultationMode.inPerson => Icons.person_outline,
                        ConsultationMode.video => Icons.videocam_outlined,
                        ConsultationMode.audio => Icons.call_outlined,
                      }),
                      title: Text(m.label),
                      trailing: Text(
                        Fmt.rupees(doctor.feeFor(m)),
                        style: theme.textTheme.titleSmall,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () =>
                    context.push('${Routes.doctorSearch}/${doctor.id}/book'),
                icon: const Icon(Icons.calendar_month),
                label: Text(context.l10n.actionBook),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.doctor});

  final Doctor doctor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(label,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center),
            ],
          ),
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            stat('${doctor.yearsExperience}', 'Years experience'),
            stat('${doctor.ratingCount}', 'Patient ratings'),
            stat(Fmt.rupees(doctor.videoFeeInr), 'Video consult'),
          ],
        ),
      ),
    );
  }
}
