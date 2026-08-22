import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../domain/medication_schedule.dart';
import 'medications_controller.dart';

/// What to take today, and what the patient says they took.
///
/// The screen is organised by *time of day* rather than by medicine, because
/// that is the question being asked: somebody standing at the kitchen counter
/// at 8am wants one list of what to swallow now, not four prescriptions to
/// cross-reference.
class MedicationsScreen extends ConsumerWidget {
  const MedicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(medicationDayProvider);
    final value = ref.watch(medicationDayProviderFamily(day));
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.medsTitle)),
      body: Column(
        children: [
          _DayBar(day: day),
          Expanded(
            child: AsyncView<MedicationDay>(
              value: value,
              onRetry: () => ref.invalidate(medicationDayProviderFamily(day)),
              skeleton: const SkeletonList(rows: 4),
              data: (medDay) => medDay.isEmpty
                  ? EmptyState(
                      icon: Icons.medication_outlined,
                      title: l10n.medsEmpty,
                      message: l10n.medsEmptyBody,
                    )
                  : _DayView(medDay: medDay),
            ),
          ),
        ],
      ),
    );
  }
}

/// Moves between days, and refuses to go past today.
///
/// Backwards only matters: a patient catching up on last night's tablet is
/// doing the honest thing, and there is nothing truthful to record about
/// tomorrow.
class _DayBar extends ConsumerWidget {
  const _DayBar({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = day == today;

    void move(int days) {
      Haptics.selection();
      ref.read(medicationDayProvider.notifier).shift(days);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.sm,
        vertical: Insets.xs,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.medsPreviousDay,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => move(-1),
          ),
          Expanded(
            child: Text(
              isToday ? l10n.medsToday : Fmt.date(day),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: l10n.medsNextDay,
            icon: const Icon(Icons.chevron_right),
            onPressed: isToday ? null : () => move(1),
          ),
        ],
      ),
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({required this.medDay});

  final MedicationDay medDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = context.tones;
    final l10n = context.l10n;

    String slotLabel(DoseSlot slot) => switch (slot) {
          DoseSlot.morning => l10n.medsSlotMorning,
          DoseSlot.afternoon => l10n.medsSlotAfternoon,
          DoseSlot.evening => l10n.medsSlotEvening,
          DoseSlot.night => l10n.medsSlotNight,
        };

    var index = 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Insets.sm,
        Insets.gutter,
        Insets.xxl,
      ),
      children: [
        if (medDay.dueCount > 0)
          FadeSlideIn(
            index: index++,
            child: _ProgressCard(
              taken: medDay.takenCount,
              due: medDay.dueCount,
            ),
          ),

        for (final entry in medDay.bySlot.entries) ...[
          const SizedBox(height: Insets.md),
          FadeSlideIn(
            index: index++,
            child: _SlotHeader(
              label: slotLabel(entry.key),
              at: DateTime(
                medDay.day.year,
                medDay.day.month,
                medDay.day.day,
                entry.key.defaultHour,
              ),
            ),
          ),
          for (final dose in entry.value)
            FadeSlideIn(
              key: ValueKey(dose.id),
              index: index++,
              child: _DoseTile(dose: dose),
            ),
        ],

        if (medDay.unscheduled.isNotEmpty) ...[
          const SizedBox(height: Insets.lg),
          FadeSlideIn(
            index: index++,
            child: SectionHeader(title: l10n.medsUnscheduled),
          ),
          FadeSlideIn(
            index: index++,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: Text(
                l10n.medsUnscheduledBody,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          for (final course in medDay.unscheduled)
            FadeSlideIn(
              key: ValueKey('unscheduled-${course.id}'),
              index: index++,
              child: _UnscheduledTile(course: course),
            ),
        ],

        if (medDay.finished.isNotEmpty) ...[
          const SizedBox(height: Insets.lg),
          FadeSlideIn(
            index: index++,
            child: SectionHeader(title: l10n.medsFinished),
          ),
          for (final course in medDay.finished)
            FadeSlideIn(
              key: ValueKey('finished-${course.id}'),
              index: index++,
              child: Opacity(
                opacity: 0.7,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.check_circle_outline, color: tones.neutral),
                  title: Text(course.item.drugName),
                  subtitle: Text(l10n.medsFinishedOn(Fmt.date(course.endsOn))),
                ),
              ),
            ),
        ],

        const SizedBox(height: Insets.lg),
        // Said on the screen rather than buried in a help page: a figure that
        // looks like a clinical measurement has to carry who is claiming it.
        Text(l10n.medsSelfReported, style: theme.textTheme.bodySmall),
        const SizedBox(height: Insets.xs),
        Text(l10n.medsTimesAreOurs, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// A time-of-day heading with the hour beside it.
///
/// Not `SectionHeader`, because the hour is the app's guess at an ordinary day
/// rather than anything the doctor wrote, and it has to read as a quieter
/// class of information than the heading it sits next to.
class _SlotHeader extends StatelessWidget {
  const _SlotHeader({required this.label, required this.at});

  final String label;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xs),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          const SizedBox(width: Insets.sm),
          Text(Fmt.time(at), style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.taken, required this.due});

  final int taken;
  final int due;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = context.tones;
    final l10n = context.l10n;
    final done = taken >= due;

    return Card(
      color: done ? tones.successContainer : theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Row(
          children: [
            Icon(
              done ? Icons.task_alt : Icons.medication_liquid_outlined,
              color:
                  done ? tones.onSuccessContainer : theme.colorScheme.primary,
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Text(
                done ? l10n.medsAllDone : l10n.medsProgress(taken, due),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: done ? tones.onSuccessContainer : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One medicine at one time of day.
class _DoseTile extends ConsumerStatefulWidget {
  const _DoseTile({required this.dose});

  final ScheduledDose dose;

  @override
  ConsumerState<_DoseTile> createState() => _DoseTileState();
}

class _DoseTileState extends ConsumerState<_DoseTile> {
  bool _busy = false;

  Future<void> _set(DoseOutcome? outcome) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await markDose(ref, widget.dose, outcome: outcome);
      if (outcome == DoseOutcome.taken) Haptics.success();
    } on Failure catch (f) {
      Haptics.warning();
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = context.tones;
    final l10n = context.l10n;
    final dose = widget.dose;
    final item = dose.course.item;
    final canMark = dose.canMarkAt(DateTime.now());

    final (Color leadingColor, IconData icon) = switch (dose.outcome) {
      DoseOutcome.taken => (tones.success, Icons.check_circle),
      DoseOutcome.skipped => (tones.warning, Icons.remove_circle_outline),
      null => (theme.colorScheme.outline, Icons.radio_button_unchecked),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      // Tapping the row is the whole interaction: tick it, and tap again to
      // take it back.
      onTap: canMark && !_busy
          ? () =>
              _set(dose.outcome == DoseOutcome.taken ? null : DoseOutcome.taken)
          : null,
      leading: _busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          : Icon(icon, color: leadingColor),
      title: Text(
        '${item.drugName} ${item.strength}',
        style: theme.textTheme.titleSmall?.copyWith(
          decoration: dose.outcome == DoseOutcome.skipped
              ? TextDecoration.lineThrough
              : null,
        ),
      ),
      subtitle: Text(
        [
          item.form,
          if (item.instructions != null && item.instructions!.isNotEmpty)
            item.instructions!,
          l10n.medsDaysLeft(dose.course.daysRemainingOn(dose.day)),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: dose.outcome == null
          ? TextButton(
              onPressed:
                  canMark && !_busy ? () => _set(DoseOutcome.skipped) : null,
              child: Text(l10n.medsSkip),
            )
          : TextButton(
              onPressed: _busy ? null : () => _set(null),
              child: Text(l10n.medsUndo),
            ),
    );
  }
}

/// A medicine with no clock behind it — as-needed, or an instruction the app
/// will not turn into times without guessing.
class _UnscheduledTile extends StatelessWidget {
  const _UnscheduledTile({required this.course});

  final MedicationCourse course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final item = course.item;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.info_outline),
      title: Text('${item.drugName} ${item.strength}',
          style: theme.textTheme.titleSmall),
      // The doctor's own words, verbatim. This is the case the app declined to
      // interpret, so putting anything else here would be inventing the very
      // instruction it refused to guess at.
      subtitle: Text(
        course.schedule.asNeeded ? l10n.medsAsNeeded : item.frequency,
      ),
      trailing: Text(
        l10n.medsDaysLeft(course.daysRemainingOn(DateTime.now())),
        style: theme.textTheme.labelSmall,
      ),
    );
  }
}
