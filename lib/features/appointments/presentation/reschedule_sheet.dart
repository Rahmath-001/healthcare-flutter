import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../booking/presentation/booking_controller.dart';
import '../domain/appointment.dart';
import 'appointments_controller.dart';

/// Moves an existing appointment to a different time with the same doctor.
///
/// Deliberately not "cancel, then book again". Cancelling first puts the old
/// slot back in the pool, so a patient who then loses the race for the new time
/// has lost the appointment they already had — and on a busy doctor that is not
/// a hypothetical. One call, and the server takes the new slot before it
/// releases the old one.
///
/// The mode is fixed to whatever was booked. Changing a video consultation into
/// an in-person one is a different appointment at a different fee, not a
/// reschedule, and offering it here would quietly turn a time change into a
/// price change.
Future<bool> showRescheduleSheet(
  BuildContext context,
  Appointment appointment,
) async {
  final moved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RescheduleSheet(appointment: appointment),
  );
  return moved ?? false;
}

class _RescheduleSheet extends ConsumerStatefulWidget {
  const _RescheduleSheet({required this.appointment});

  final Appointment appointment;

  @override
  ConsumerState<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends ConsumerState<_RescheduleSheet> {
  late DateTime _day = _dateOnly(widget.appointment.start);
  AppointmentSlot? _selected;
  bool _saving = false;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _confirm() async {
    final slot = _selected;
    if (slot == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    try {
      await rescheduleAppointment(
        ref,
        widget.appointment.id,
        start: slot.start,
        end: slot.end,
      );
      Haptics.success();
      navigator.pop(true);
    } on Failure catch (f) {
      // Stays open on failure. The most likely one is SLOT_TAKEN, and the
      // useful response to that is picking another time — which needs this
      // sheet still on screen.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _selected = null;
      });
      ref.invalidate(slotsProvider);
      Haptics.warning();
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final a = widget.appointment;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.gutter,
          0,
          Insets.gutter,
          Insets.gutter,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.rescheduleTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: Insets.xs),
            Text(
              l10n.rescheduleCurrent(Fmt.dateTime(a.start)),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Insets.lg),
            _DayStrip(
              selected: _day,
              onSelect: (d) {
                Haptics.selection();
                setState(() {
                  _day = d;
                  // A slot from the previous day must not survive the switch:
                  // confirming it would move the appointment to a time the
                  // user is no longer looking at.
                  _selected = null;
                });
              },
            ),
            const SizedBox(height: Insets.lg),
            SizedBox(
              height: 156,
              child: _SlotPicker(
                query: SlotQuery(
                  doctorId: a.doctor.id,
                  date: _day,
                  mode: a.mode,
                ),
                selected: _selected,
                currentStart: a.start,
                onSelect: (slot) {
                  Haptics.selection();
                  setState(() => _selected = slot);
                },
              ),
            ),
            const SizedBox(height: Insets.lg),
            Text(
              l10n.rescheduleHoldNote,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.md),
            FilledButton(
              onPressed: _selected == null || _saving ? null : _confirm,
              child: _saving
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Text(l10n.rescheduleConfirm),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rolling fortnight, matching what the picker can realistically show.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.selected, required this.onSelect});

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();

    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 14,
        separatorBuilder: (_, __) => const SizedBox(width: Insets.sm),
        itemBuilder: (_, i) {
          final date = DateTime(today.year, today.month, today.day + i);
          final isSelected = date.day == selected.day &&
              date.month == selected.month &&
              date.year == selected.year;

          return InkWell(
            borderRadius: Radii.mdAll,
            onTap: () => onSelect(date),
            child: Container(
              width: 58,
              decoration: BoxDecoration(
                color: isSelected ? theme.colorScheme.primary : null,
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
                borderRadius: Radii.mdAll,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    Fmt.weekday(date).toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    date.day.toString(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
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

class _SlotPicker extends ConsumerWidget {
  const _SlotPicker({
    required this.query,
    required this.selected,
    required this.currentStart,
    required this.onSelect,
  });

  final SlotQuery query;
  final AppointmentSlot? selected;

  /// The time this appointment already occupies, so it can be shown as such
  /// rather than as an ordinary free slot the patient might "pick" to no effect.
  final DateTime currentStart;

  final ValueChanged<AppointmentSlot> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<AppointmentSlot>>(
      value: ref.watch(slotsProvider(query)),
      onRetry: () => ref.invalidate(slotsProvider(query)),
      skeleton: const Padding(
        padding: EdgeInsets.only(top: Insets.sm),
        child: Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            Skeleton(width: 84, height: 36),
            Skeleton(width: 84, height: 36),
            Skeleton(width: 84, height: 36),
            Skeleton(width: 84, height: 36),
          ],
        ),
      ),
      data: (slots) {
        if (slots.isEmpty) {
          return EmptyState(
            icon: Icons.event_busy_outlined,
            title: context.l10n.rescheduleNoSlots,
            message: context.l10n.rescheduleNoSlotsBody,
          );
        }

        return SingleChildScrollView(
          child: Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: slots.map((slot) {
              final isCurrent = slot.start == currentStart;
              return ChoiceChip(
                label: Text(
                  isCurrent
                      ? context.l10n.rescheduleCurrentSlot(Fmt.time(slot.start))
                      : Fmt.time(slot.start),
                ),
                selected: selected?.id == slot.id,
                // A taken slot stays visible but unselectable, so the day reads
                // as "busy" rather than "empty". The appointment's own slot is
                // unselectable for the same reason it is labelled: moving
                // something to where it already is is not a move.
                onSelected: slot.isAvailable && !isCurrent
                    ? (_) => onSelect(slot)
                    : null,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
