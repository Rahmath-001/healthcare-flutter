import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../../providers_search/domain/doctor.dart';
import '../domain/appointment.dart';
import 'appointments_controller.dart';

class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointments = ref.watch(patientAppointmentsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.navAppointments),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Past'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.go(Routes.doctorSearch),
          icon: const Icon(Icons.add),
          label: const Text('Book'),
        ),
        body: AsyncView<List<Appointment>>(
          value: appointments,
          onRetry: () => ref.invalidate(patientAppointmentsProvider),
          data: (all) => TabBarView(
            children: [
              _AppointmentList(
                items: all.where((a) => a.status.isUpcoming).toList()
                  ..sort((a, b) => a.start.compareTo(b.start)),
                emptyTitle: 'No upcoming appointments',
                emptyMessage: 'Book a consultation to see it here.',
                onRefresh: () =>
                    ref.refresh(patientAppointmentsProvider.future),
              ),
              _AppointmentList(
                items: all.where((a) => a.status.isPast).toList(),
                emptyTitle: 'No past appointments',
                onRefresh: () =>
                    ref.refresh(patientAppointmentsProvider.future),
              ),
              _AppointmentList(
                items: all.where((a) => a.status.isCancelled).toList(),
                emptyTitle: 'No cancelled appointments',
                onRefresh: () =>
                    ref.refresh(patientAppointmentsProvider.future),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({
    required this.items,
    required this.emptyTitle,
    required this.onRefresh,
    this.emptyMessage,
  });

  final List<Appointment> items;
  final String emptyTitle;
  final String? emptyMessage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.event_note_outlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => AppointmentCard(appointment: items[i]),
      ),
    );
  }
}

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    this.showPatientName = false,
  });

  final Appointment appointment;

  /// Provider-side lists show the patient rather than the doctor.
  final bool showPatientName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = appointment;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/patient/appointments/${a.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      showPatientName ? a.patientName : a.doctor.name,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  StatusChip(
                    label: a.status.label,
                    color: _statusColor(theme, a.status),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                showPatientName
                    ? (a.reasonForVisit ?? 'No reason given')
                    : a.doctor.specialtyLabel,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule,
                      size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(Fmt.dateTime(a.start),
                      style: theme.textTheme.bodyMedium),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    switch (a.mode) {
                      ConsultationMode.inPerson => Icons.person_outline,
                      ConsultationMode.video => Icons.videocam_outlined,
                      ConsultationMode.audio => Icons.call_outlined,
                    },
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  // Expanded and ellipsised: a hospital name is unbounded and
                  // overflowed this row by ~115px on a normal phone, which a
                  // widget test caught.
                  Expanded(
                    child: Text(
                      a.mode == ConsultationMode.inPerson
                          ? '${a.mode.label} · ${a.doctor.hospital.name}'
                          : a.mode.label,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Text('#${a.referenceCode}', style: theme.textTheme.bodySmall),
                ],
              ),
              if (a.canJoinConsultation) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context
                        .push('/patient/consultation/${a.consultationId}'),
                    icon: const Icon(Icons.videocam),
                    label: const Text('Join consultation'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(ThemeData theme, AppointmentStatus status) {
    if (status.isCancelled) return theme.colorScheme.error;
    if (status.isPast) return theme.colorScheme.outline;
    return theme.colorScheme.primary;
  }
}
