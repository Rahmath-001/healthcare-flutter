import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../appointments/presentation/appointments_controller.dart';
import '../domain/patient_timeline.dart';

/// One patient's history with this doctor, in one column.
///
/// Composed on the client from what the provider can already read, rather than
/// from a new "give me everything about this patient" endpoint. That is a
/// deliberate constraint: an endpoint shaped like that would be one
/// authorization mistake away from being a patient-history API, and it would
/// need its own consent check that could drift from the one the records
/// endpoint already has.
final patientTimelineProvider =
    FutureProvider.family<PatientTimeline, String>((ref, patientId) async {
  final appointments = await ref.watch(providerAppointmentsProvider.future);
  final mine = appointments.where((a) => a.patientId == patientId).toList();

  final name = mine.isEmpty ? '' : mine.first.patientName;
  final entries = <TimelineEntry>[];

  for (final a in mine) {
    entries.add(TimelineEntry(
      kind: TimelineKind.appointment,
      at: a.start,
      title: a.mode.label,
      subtitle: a.status.label,
      targetId: a.id,
    ));

    // Derived from the appointment rather than fetched: the flag is already on
    // it, and a prescription list scoped to "this doctor and this patient" is
    // a query nothing else needs.
    if (a.hasPrescription) {
      entries.add(TimelineEntry(
        kind: TimelineKind.prescription,
        at: a.start,
        title: 'Prescription issued',
        targetId: a.id,
      ));
    }
  }

  // Notes, one appointment at a time. Only for consultations that happened —
  // asking about a cancelled booking is a round trip that can only ever
  // answer "none".
  final noteRepo = ref.watch(consultationNoteRepositoryProvider);
  for (final a in mine.where((a) => a.status.isPast)) {
    final note = await noteRepo.forAppointment(a.id);
    if (note != null) {
      entries.add(TimelineEntry(
        kind: TimelineKind.note,
        at: note.writtenAt,
        title: 'Consultation note',
        subtitle: note.hasAddenda ? 'With addenda' : null,
        targetId: a.id,
      ));
    }
  }

  // The patient's own records, which need a live grant. A refusal is an
  // answer, not an error: it is reported as "no access" rather than failing
  // the whole screen, because the doctor's own acts above are still theirs to
  // see.
  var hasGrant = true;
  try {
    final records =
        await ref.watch(recordsRepositoryProvider).listGranted(patientId);
    for (final r in records) {
      entries.add(TimelineEntry(
        kind: TimelineKind.sharedRecord,
        at: r.recordedAt,
        title: r.title,
        subtitle: r.type.label,
        targetId: r.id,
      ));
    }
  } on Failure catch (f) {
    if (f.code == 'NO_CONSENT' || f.kind == FailureKind.forbidden) {
      hasGrant = false;
    } else {
      rethrow;
    }
  }

  return PatientTimeline(
    patientId: patientId,
    patientName: name,
    entries: entries,
    hasActiveGrant: hasGrant,
  );
});

class PatientTimelineScreen extends ConsumerWidget {
  const PatientTimelineScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = ref.watch(patientTimelineProvider(patientId));
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(timeline.value?.patientName.isNotEmpty ?? false
            ? timeline.value!.patientName
            : l10n.timelineTitle),
      ),
      body: AsyncView<PatientTimeline>(
        value: timeline,
        onRetry: () => ref.invalidate(patientTimelineProvider(patientId)),
        skeleton: const SkeletonList(rows: 3),
        data: (t) => t.isEmpty && !t.hasActiveGrant
            ? EmptyState(
                icon: Icons.lock_outline,
                title: l10n.timelineNoAccess,
                message: l10n.timelineNoAccessBody,
              )
            : _Timeline(timeline: t),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.timeline});

  final PatientTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final days = timeline.byDay;

    var index = 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Insets.md,
        Insets.gutter,
        Insets.xxl,
      ),
      children: [
        // Stated, never inferred from an empty list. "They have not shared
        // anything" and "your access has expired" are different facts, and
        // showing the second as the first invites a doctor to conclude a
        // patient has no history.
        if (!timeline.hasActiveGrant)
          FadeSlideIn(
            index: index++,
            child: _GrantBanner(name: timeline.patientName),
          ),

        for (final entry in days.entries) ...[
          const SizedBox(height: Insets.md),
          FadeSlideIn(
            index: index++,
            child: Text(
              Fmt.date(entry.key),
              style: theme.textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: Insets.xs),
          for (final e in entry.value)
            FadeSlideIn(
              key: ValueKey('${e.kind}-${e.targetId}-${e.at}'),
              index: index++,
              child: _EntryTile(entry: e),
            ),
        ],

        const SizedBox(height: Insets.lg),
        Text(l10n.timelineFootnote, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _GrantBanner extends StatelessWidget {
  const _GrantBanner({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = context.tones;

    return Card(
      margin: EdgeInsets.zero,
      color: tones.warningContainer,
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, color: tones.onWarningContainer, size: 20),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Text(
                context.l10n.timelineGrantExpired(name),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: tones.onWarningContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = context.tones;

    final (IconData icon, Color tone) = switch (entry.kind) {
      TimelineKind.appointment => (Icons.event_outlined, tones.info),
      TimelineKind.note => (Icons.notes_outlined, tones.neutral),
      TimelineKind.prescription => (Icons.receipt_long_outlined, tones.success),
      TimelineKind.sharedRecord => (Icons.folder_shared_outlined, tones.info),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: tone.withValues(alpha: 0.14),
        child: Icon(icon, size: 18, color: tone),
      ),
      title: Text(entry.title, style: theme.textTheme.titleSmall),
      subtitle: Text(
        [
          if (entry.subtitle != null) entry.subtitle!,
          Fmt.time(entry.at),
        ].join(' · '),
        style: theme.textTheme.bodySmall,
      ),
      onTap: entry.targetId == null ? null : () => _open(context),
    );
  }

  void _open(BuildContext context) {
    switch (entry.kind) {
      case TimelineKind.appointment:
      case TimelineKind.prescription:
        context.push(Routes.appointmentDetail(entry.targetId!));
      case TimelineKind.note:
        context.push(Routes.consultationNote(entry.targetId!));
      case TimelineKind.sharedRecord:
        context.push(Routes.recordDetail(entry.targetId!));
    }
  }
}
