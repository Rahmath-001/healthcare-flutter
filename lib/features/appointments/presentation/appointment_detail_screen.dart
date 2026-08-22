import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../../providers_search/domain/doctor.dart';
import '../domain/appointment.dart';
import 'queue_card.dart';
import 'reschedule_sheet.dart';
import 'appointments_controller.dart';

class AppointmentDetailScreen extends ConsumerWidget {
  const AppointmentDetailScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointment = ref.watch(appointmentByIdProvider(appointmentId));

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.appointmentDetailTitle)),
      body: AsyncView<Appointment>(
        value: appointment,
        onRetry: () => ref.invalidate(appointmentByIdProvider(appointmentId)),
        data: (a) => _Body(appointment: a),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.appointment});

  final Appointment appointment;

  static Future<void> _reschedule(
    BuildContext context,
    WidgetRef ref,
    Appointment appointment,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    final moved = await showRescheduleSheet(context, appointment);
    if (!moved) return;

    // Re-read rather than trusting the appointment captured above: the sheet
    // has already refreshed the providers, and the whole point of the message
    // is to state the *new* time.
    final updated = await ref.read(
      appointmentByIdProvider(appointment.id).future,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.rescheduleDone(Fmt.dateTime(updated.start)))),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CancelSheet(appointment: appointment),
    );
    if (reason == null) return;

    try {
      await cancelAppointment(ref, appointment.id, reason: reason);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.appointmentCancelled)),
        );
      }
    } on Failure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final a = appointment;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(a.doctor.name, style: theme.textTheme.headlineSmall),
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
        const SizedBox(height: 4),
        Text(a.doctor.specialtyLabel, style: theme.textTheme.bodyLarge),
        Text('Reg. ${a.doctor.registrationNumber}',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 20),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.confirmation_number_outlined),
                title: Text(context.l10n.appointmentReference),
                subtitle: Text(a.referenceCode),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(context.l10n.appointmentWhen),
                subtitle: Text(
                  '${Fmt.dateTime(a.start)} · ${Fmt.duration(a.duration)}',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(switch (a.mode) {
                  ConsultationMode.inPerson => Icons.person_outline,
                  ConsultationMode.video => Icons.videocam_outlined,
                  ConsultationMode.audio => Icons.call_outlined,
                }),
                title: Text(context.l10n.appointmentType),
                subtitle: Text(
                  a.mode == ConsultationMode.inPerson
                      ? '${a.mode.label} at ${a.doctor.hospital.name}'
                      : a.mode.label,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(Fmt.rupees(a.feeInr)),
                subtitle: Text(a.paymentStatus.label),
              ),
            ],
          ),
        ),
        if (a.reasonForVisit != null) ...[
          const SizedBox(height: 20),
          Text(context.l10n.appointmentReasonForVisit,
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(a.reasonForVisit!, style: theme.textTheme.bodyMedium),
        ],
        if (a.cancellationReason != null) ...[
          const SizedBox(height: 20),
          Text(context.l10n.appointmentCancellationReason,
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(a.cancellationReason!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 24),
        if (QueueCard.appliesTo(a)) ...[
          QueueCard(appointment: a),
          const SizedBox(height: 12),
        ],
        if (a.canJoinConsultation)
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () =>
                  context.push('/patient/consultation/${a.consultationId}'),
              icon: const Icon(Icons.videocam),
              label: Text(context.l10n.actionJoin),
            ),
          ),
        if (a.hasPrescription) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/patient/prescriptions'),
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(context.l10n.appointmentViewPrescription),
            ),
          ),
        ],
        if (a.canRate) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/patient/rate/${a.id}'),
              icon: const Icon(Icons.star_outline),
              label: Text(context.l10n.appointmentRate),
            ),
          ),
        ],
        // Offered above Cancel on purpose. Someone who cannot make their time
        // usually wants a different one, not none — and a cancel button
        // reached first is a slot returned to the pool and a consultation that
        // never happens.
        if (a.canReschedule) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => _reschedule(context, ref, a),
              icon: const Icon(Icons.event_repeat_outlined),
              label: Text(context.l10n.rescheduleAction),
            ),
          ),
        ],
        if (a.canCancel) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => _cancel(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              icon: const Icon(Icons.close),
              label: Text(context.l10n.appointmentCancelConfirm),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.appointment});

  final Appointment appointment;

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final _reasonCtrl = TextEditingController();
  String? _selected;

  static const _reasons = [
    'I am no longer available at this time',
    'I booked with a different doctor',
    'My symptoms have resolved',
    'I need a different consultation type',
    'Other',
  ];

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.appointment;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.appointmentCancelConfirm,
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          // States the cancellation policy plainly at the moment of decision.
          // The spec defines no policy, so this is the provisional rule and the
          // single place to change it.
          Text(
            a.isFreeCancellation
                ? 'This is more than 24 hours before your appointment, so '
                    'there is no cancellation charge.'
                : 'This is within 24 hours of your appointment. A '
                    'cancellation fee may apply once billing is enabled.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          RadioGroup<String>(
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
            child: Column(
              children: _reasons
                  .map((r) => RadioListTile<String>(
                        value: r,
                        title: Text(r),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ))
                  .toList(),
            ),
          ),
          if (_selected == 'Other')
            TextField(
              controller: _reasonCtrl,
              autofocus: true,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: context.l10n.appointmentTellUsWhy,
                border: const OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.appointmentKeepIt),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _selected == null
                      ? null
                      : () => Navigator.of(context).pop(
                            _selected == 'Other'
                                ? (_reasonCtrl.text.trim().isEmpty
                                    ? 'Other'
                                    : _reasonCtrl.text.trim())
                                : _selected,
                          ),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                  child: Text(context.l10n.appointmentCancelIt),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
