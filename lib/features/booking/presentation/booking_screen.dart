import '../../../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/providers.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../../appointments/domain/appointment.dart';
import '../../providers_search/domain/doctor.dart';
import '../../providers_search/presentation/doctor_search_controller.dart';
import '../data/booking_repository.dart';
import 'booking_controller.dart';

class BookingScreen extends ConsumerWidget {
  const BookingScreen({super.key, required this.doctorId});

  final String doctorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorByIdProvider(doctorId));

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.actionBook)),
      body: AsyncView<Doctor>(
        value: doctor,
        onRetry: () => ref.invalidate(doctorByIdProvider(doctorId)),
        data: (d) => _BookingBody(doctor: d),
      ),
    );
  }
}

class _BookingBody extends ConsumerStatefulWidget {
  const _BookingBody({required this.doctor});

  final Doctor doctor;

  @override
  ConsumerState<_BookingBody> createState() => _BookingBodyState();
}

class _BookingBodyState extends ConsumerState<_BookingBody> {
  final _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Default to a mode the doctor actually offers, rather than assuming video.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(bookingControllerProvider.notifier)
          .selectMode(widget.doctor.modes.first);
    });
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final session = ref.read(currentSessionProvider);
    final notifier = ref.read(bookingControllerProvider.notifier);

    try {
      final appointment = await notifier.confirm(
        doctor: widget.doctor,
        patientName: session?.greetingName ?? 'You',
        reasonForVisit:
            _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      );
      if (!mounted) return;
      context.pushReplacement('/patient/booking-confirmed', extra: appointment);
    } on Failure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      // A lost race means the slot list on screen is stale.
      ref.invalidate(slotsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookingControllerProvider);
    final theme = Theme.of(context);
    final date = state.selectedDate ?? DateTime.now();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _DoctorSummary(doctor: widget.doctor, mode: state.mode),
              const SizedBox(height: 20),
              Text(context.l10n.searchMode, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: widget.doctor.modes
                    .map((m) => ChoiceChip(
                          label: Text('${m.label}  ·  '
                              '${Fmt.rupees(widget.doctor.feeFor(m))}'),
                          selected: state.mode == m,
                          onSelected: (_) => ref
                              .read(bookingControllerProvider.notifier)
                              .selectMode(m),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 20),
              Text(context.l10n.bookingSelectDate,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _DateStrip(
                selected: date,
                onSelect: (d) =>
                    ref.read(bookingControllerProvider.notifier).selectDate(d),
              ),
              const SizedBox(height: 20),
              Text(context.l10n.bookingAvailableTimes,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _SlotGrid(
                query: SlotQuery(
                  doctorId: widget.doctor.id,
                  date: date,
                  mode: state.mode,
                ),
                selected: state.selectedSlot,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _reasonCtrl,
                maxLines: 3,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: context.l10n.bookingReasonOptional,
                  hintText: context.l10n.bookingSymptomsHint,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        if (state.selectedSlot != null)
          _ConfirmBar(
            doctor: widget.doctor,
            state: state,
            onConfirm: _confirm,
          ),
      ],
    );
  }
}

class _DoctorSummary extends StatelessWidget {
  const _DoctorSummary({required this.doctor, required this.mode});

  final Doctor doctor;
  final ConsultationMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              child: Text(doctor.name.split(' ').last[0]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doctor.name, style: theme.textTheme.titleSmall),
                  Text(doctor.specialtyLabel, style: theme.textTheme.bodySmall),
                  Text('Reg. ${doctor.registrationNumber}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selected, required this.onSelect});

  final DateTime selected;
  final void Function(DateTime) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();

    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // A rolling 30-day window, matching the slot materialiser's horizon.
        itemCount: 30,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final date = DateTime(today.year, today.month, today.day + i);
          final isSelected = date.day == selected.day &&
              date.month == selected.month &&
              date.year == selected.year;

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelect(date),
            child: Container(
              width: 60,
              decoration: BoxDecoration(
                color: isSelected ? theme.colorScheme.primary : null,
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    Fmt.weekday(date),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isSelected ? theme.colorScheme.onPrimary : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isSelected ? theme.colorScheme.onPrimary : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SlotGrid extends ConsumerWidget {
  const _SlotGrid({required this.query, required this.selected});

  final SlotQuery query;
  final AppointmentSlot? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(slotsProvider(query));

    return AsyncView<List<AppointmentSlot>>(
      value: slots,
      onRetry: () => ref.invalidate(slotsProvider(query)),
      loading: const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              icon: Icons.event_busy_outlined,
              title: context.l10n.bookingNoSlotsOnDay,
              message: 'Try another date.',
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: list.map((slot) {
            final isSelected = selected?.id == slot.id;
            return ChoiceChip(
              label: Text(Fmt.time(slot.start)),
              selected: isSelected,
              // A taken slot stays visible but unselectable, so the day still
              // reads as "busy" rather than "empty".
              onSelected: slot.isAvailable
                  ? (_) => ref
                      .read(bookingControllerProvider.notifier)
                      .selectSlot(slot)
                  : null,
            );
          }).toList(),
        );
      },
    );
  }
}

/// Bottom bar showing the hold countdown and the confirm action.
class _ConfirmBar extends StatefulWidget {
  const _ConfirmBar({
    required this.doctor,
    required this.state,
    required this.onConfirm,
  });

  final Doctor doctor;
  final BookingState state;
  final Future<void> Function() onConfirm;

  @override
  State<_ConfirmBar> createState() => _ConfirmBarState();
}

class _ConfirmBarState extends State<_ConfirmBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Drives the visible hold countdown.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slot = widget.state.selectedSlot!;
    final hold = widget.state.hold;
    final expired = hold?.isExpired ?? false;

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Fmt.dateTime(slot.start),
                            style: theme.textTheme.titleSmall),
                        Text(
                          '${widget.state.mode.label} · '
                          '${Fmt.rupees(widget.doctor.feeFor(widget.state.mode))}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (hold != null && !expired)
                    StatusChip(
                      label: 'Held ${Fmt.countdown(hold.remaining)}',
                      color: theme.colorScheme.primary,
                      icon: Icons.timer_outlined,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (expired)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Your hold on this slot expired. Please pick a time again.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              // Payments are deferred, so this states plainly that nothing is
              // being charged. FR-BOOK-003 is relaxed until a provider is wired.
              if (!BookingPolicy.requiresPayment())
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 15, color: theme.colorScheme.outline),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'No payment is taken now. Pay at the clinic or when '
                          'billing goes live.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: widget.state.isBooking || expired
                      ? null
                      : widget.onConfirm,
                  child: widget.state.isBooking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Text(context.l10n.bookingConfirm),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
