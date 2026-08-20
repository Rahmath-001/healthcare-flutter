import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/feature_providers.dart';
import '../../../core/router/routes.dart';
import '../../../shared/formatters.dart';
import '../../appointments/domain/appointment.dart';
import '../../consent/domain/consent.dart';
import '../../providers_search/domain/doctor.dart';

/// Booking confirmation, and the one place a record-sharing grant is offered
/// as part of the booking flow.
///
/// The share step is opt-in and entirely skippable: booking must succeed when
/// the patient shares nothing. Offering it here rather than mid-consultation is
/// what makes the grant useful — the doctor can prepare beforehand.
class BookingConfirmedScreen extends ConsumerStatefulWidget {
  const BookingConfirmedScreen({super.key, required this.appointment});

  final Appointment appointment;

  @override
  ConsumerState<BookingConfirmedScreen> createState() =>
      _BookingConfirmedScreenState();
}

class _BookingConfirmedScreenState
    extends ConsumerState<BookingConfirmedScreen> {
  bool _shareRecords = false;
  bool _sharing = false;

  Future<void> _finish() async {
    if (_shareRecords) {
      setState(() => _sharing = true);
      final a = widget.appointment;
      try {
        await ref.read(consentRepositoryProvider).grant(
              providerId: a.doctor.id,
              providerName: a.doctor.name,
              providerSpecialty: a.doctor.specialtyLabel,
              scopeKind: ConsentScopeKind.allRecords,
              purpose: ConsentPurpose.consultation,
              // Window matches the appointment: opens an hour before and
              // closes 48 hours after, so follow-up notes are still possible
              // without the grant lingering.
              duration: a.start.difference(DateTime.now()) +
                  const Duration(hours: 49),
              appointmentReference: a.referenceCode,
            );
      } catch (_) {
        // Sharing is optional; a failure here must never block the booking
        // that has already succeeded.
      } finally {
        if (mounted) setState(() => _sharing = false);
      }
    }
    if (mounted) context.go(Routes.patientAppointments);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final theme = Theme.of(context);

    return PopScope(
      // The appointment is already created; going "back" into the slot picker
      // would misrepresent that.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 24),
                    Center(
                      child: Icon(Icons.check_circle,
                          size: 72, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 16),
                    Text('Appointment confirmed',
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Reference ${a.referenceCode}',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: Text(a.doctor.name),
                            subtitle: Text(a.doctor.specialtyLabel),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.schedule),
                            title: Text(Fmt.dateTime(a.start)),
                            subtitle: Text(Fmt.duration(a.duration)),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Icon(switch (a.mode) {
                              ConsultationMode.inPerson => Icons.person_outline,
                              ConsultationMode.video => Icons.videocam_outlined,
                              ConsultationMode.audio => Icons.call_outlined,
                            }),
                            title: Text(a.mode.label),
                            subtitle: a.mode == ConsultationMode.inPerson
                                ? Text(a.doctor.hospital.name)
                                : const Text('Join from the app'),
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
                    const SizedBox(height: 20),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: _shareRecords,
                            onChanged: (v) => setState(() => _shareRecords = v),
                            secondary: const Icon(Icons.folder_shared_outlined),
                            title: Text('Share your records with '
                                '${a.doctor.name}'),
                            subtitle: const Text(
                              'Optional. Access ends 48 hours after your '
                              'appointment, and you can revoke it at any time.',
                            ),
                          ),
                          if (_shareRecords)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 15,
                                      color: theme.colorScheme.outline),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'You will see every time this doctor '
                                      'opens one of your records.',
                                      style: theme.textTheme.bodySmall,
                                    ),
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
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _sharing ? null : _finish,
                    child: _sharing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Text('Done'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
