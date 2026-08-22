import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../../appointments/domain/appointment.dart';
import '../../appointments/presentation/appointments_controller.dart';
import '../../providers_search/domain/doctor.dart';

/// The provider's working screen: who they are seeing today, in order.
class ProviderTodayScreen extends ConsumerWidget {
  const ProviderTodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(providerTodayProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.navToday),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                Fmt.date(DateTime.now()),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: AsyncView<List<Appointment>>(
        value: today,
        onRetry: () => ref.invalidate(providerAppointmentsProvider),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.free_breakfast_outlined,
              title: context.l10n.providerNothingToday,
              message: 'Appointments booked for today will appear here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(providerAppointmentsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _ProviderAppointmentCard(
                appointment: list[i],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProviderAppointmentCard extends StatelessWidget {
  const _ProviderAppointmentCard({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = appointment;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  child: Text(a.patientName[0]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.patientName, style: theme.textTheme.titleSmall),
                      Text(
                        '${Fmt.time(a.start)} · ${Fmt.duration(a.duration)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  label: a.status.label,
                  tone: a.status.isCancelled
                      ? Tone.danger
                      : a.status.isPast
                          ? Tone.neutral
                          : Tone.success,
                ),
              ],
            ),
            if (a.reasonForVisit != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    Text(a.reasonForVisit!, style: theme.textTheme.bodySmall),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (a.canJoinConsultation)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.push(
                        Routes.providerConsultation(a.consultationId ?? ''),
                      ),
                      icon: Icon(
                        a.mode == ConsultationMode.audio
                            ? Icons.call
                            : Icons.videocam,
                        size: 18,
                      ),
                      label: Text(context.l10n.providerStart),
                    ),
                  ),
                if (a.canJoinConsultation) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push(Routes.providerPrescribe(a.id)),
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text(context.l10n.providerPrescribe),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Patients who have shared records with this provider.
///
/// Deliberately not "all my patients": a provider sees a patient's records only
/// through a live consent grant, so this list is the set of active grants, not
/// a directory.
class ProviderPatientsScreen extends ConsumerWidget {
  const ProviderPatientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointments = ref.watch(providerAppointmentsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.navPatients)),
      body: AsyncView<List<Appointment>>(
        value: appointments,
        onRetry: () => ref.invalidate(providerAppointmentsProvider),
        data: (list) {
          // Keyed by id, not by name: two patients can share a name, and
          // merging two people's care under one heading is the worst failure
          // a clinical list has.
          final patients = <String, Appointment>{};
          for (final a in list) {
            patients.putIfAbsent(a.patientId, () => a);
          }
          if (patients.isEmpty) {
            return EmptyState(
              icon: Icons.folder_shared_outlined,
              title: context.l10n.providerPatientsNone,
              message: 'Patients you consult with will appear here.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: patients.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final a = patients.values.elementAt(i);
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: CircleAvatar(child: Text(a.patientName[0])),
                  title: Text(a.patientName),
                  subtitle: Text(
                    'Last seen ${Fmt.relative(a.start)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.push(Routes.providerPatient(a.patientId)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
