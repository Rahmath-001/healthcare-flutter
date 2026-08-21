import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../providers_search/domain/doctor.dart';
import '../domain/appointment.dart';
import 'appointments_controller.dart';

class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointments = ref.watch(patientAppointmentsProvider);
    final l10n = context.l10n;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.navAppointments),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.appointmentsUpcoming),
              Tab(text: l10n.appointmentsPast),
              Tab(text: l10n.appointmentsCancelledTab),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.go(Routes.doctorSearch),
          icon: const Icon(Icons.add),
          label: Text(l10n.actionBookShort),
        ),
        body: AsyncView<List<Appointment>>(
          value: appointments,
          onRetry: () => ref.invalidate(patientAppointmentsProvider),
          skeleton: const SkeletonList(count: 4, rows: 3),
          data: (all) => TabBarView(
            children: [
              _AppointmentList(
                items: all.where((a) => a.status.isUpcoming).toList()
                  ..sort((a, b) => a.start.compareTo(b.start)),
                emptyTitle: l10n.appointmentsNoUpcoming,
                emptyMessage: l10n.appointmentsNoUpcomingBody,
                emptyAction: FilledButton(
                  onPressed: () => context.go(Routes.doctorSearch),
                  child: Text(l10n.actionBook),
                ),
                onRefresh: () =>
                    ref.refresh(patientAppointmentsProvider.future),
              ),
              _AppointmentList(
                // Most recent first: a past list read oldest-first buries the
                // consultation someone is actually looking for — usually the
                // last one — under everything that came before it.
                items: all.where((a) => a.status.isPast).toList()
                  ..sort((a, b) => b.start.compareTo(a.start)),
                emptyTitle: l10n.appointmentsNoPast,
                onRefresh: () =>
                    ref.refresh(patientAppointmentsProvider.future),
              ),
              _AppointmentList(
                items: all.where((a) => a.status.isCancelled).toList()
                  ..sort((a, b) => b.start.compareTo(a.start)),
                emptyTitle: l10n.appointmentsNoCancelled,
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
    this.emptyAction,
  });

  final List<Appointment> items;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      // Still refreshable. An empty list is the state most likely to be wrong
      // — it is what a failed sync looks like — so pull-to-refresh has to
      // work here or the user's only recourse is to kill the app.
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: EmptyState(
                icon: Icons.event_note_outlined,
                title: emptyTitle,
                message: emptyMessage,
                action: emptyAction,
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          Insets.lg,
          Insets.lg,
          Insets.fabSafeBottom,
        ),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: Insets.md),
        // Keyed by appointment, not by position. `FadeSlideIn` is stateful,
        // so without this Flutter matches elements positionally when the tab
        // switches and hands row 3's finished animation controller to a
        // different appointment — which arrives already faded in.
        itemBuilder: (_, i) => FadeSlideIn(
          key: ValueKey(items[i].id),
          index: i,
          child: AppointmentCard(appointment: items[i]),
        ),
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
    final joinable = a.canJoinConsultation;

    return PressableScale(
      child: Card(
        // A joinable consultation is the one card on this screen that is
        // time-critical, so it gets a brand-coloured edge rather than the
        // hairline every other card has. Colour is not the only signal — the
        // Join button below is — so this still works for a colour-blind user.
        shape: joinable
            ? RoundedRectangleBorder(
                borderRadius: Radii.mdAll,
                side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
              )
            : null,
        child: InkWell(
          onTap: () => context.push('${Routes.patientAppointments}/${a.id}'),
          child: Padding(
            padding: Insets.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        showPatientName ? a.patientName : a.doctor.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    StatusChip(
                      label: a.status.label,
                      tone: _statusTone(a.status),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  showPatientName
                      ? (a.reasonForVisit ??
                          context.l10n.appointmentNoReasonGiven)
                      : a.doctor.specialtyLabel,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Insets.md),
                _MetaRow(
                  icon: Icons.schedule,
                  // The absolute time, then how far away it is. Reading
                  // "Tomorrow, 9:00 AM" and "in 18 hours" together is what
                  // stops someone mis-reading a Tuesday slot as today's.
                  text: Fmt.dateTime(a.start),
                  trailing: a.status.isUpcoming ? Fmt.relative(a.start) : null,
                ),
                const SizedBox(height: Insets.sm - 2),
                _MetaRow(
                  icon: switch (a.mode) {
                    ConsultationMode.inPerson => Icons.person_outline,
                    ConsultationMode.video => Icons.videocam_outlined,
                    ConsultationMode.audio => Icons.call_outlined,
                  },
                  // A hospital name is unbounded and overflowed this row by
                  // ~115px on a normal phone, which a widget test caught.
                  text: a.mode == ConsultationMode.inPerson
                      ? '${a.mode.label} · ${a.doctor.hospital.name}'
                      : a.mode.label,
                  trailing: '#${a.referenceCode}',
                ),
                if (joinable) ...[
                  const SizedBox(height: Insets.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context
                          .push('/patient/consultation/${a.consultationId}'),
                      icon: const Icon(Icons.videocam, size: 20),
                      label: Text(context.l10n.actionJoin),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Tone _statusTone(AppointmentStatus status) {
    if (status.isCancelled) return Tone.danger;
    if (status.isPast) return Tone.neutral;
    return Tone.success;
  }
}

/// Icon, text, and an optional right-aligned value.
///
/// Every card in the app was building this row by hand with its own icon size
/// and gap, which is why the same metadata line sat two pixels differently on
/// Appointments and on Records.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text, this.trailing});

  final IconData icon;
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.outline),
        const SizedBox(width: Insets.sm - 2),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: Insets.sm),
          Text(
            trailing!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}
