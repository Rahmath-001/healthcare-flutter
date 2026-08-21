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
import '../domain/medical_record.dart';
import 'records_controller.dart';

class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(ownRecordsProvider);
    final filter = ref.watch(recordFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.recordsTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.recordsWhoCanSee,
            icon: const Icon(Icons.shield_outlined),
            onPressed: () => context.push(Routes.sharing),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.recordUpload),
        icon: const Icon(Icons.upload_file),
        label: Text(context.l10n.actionUpload),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.sm,
              Insets.lg,
              Insets.md,
            ),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<RecordFilter>(
                segments: RecordFilter.values
                    .map((f) => ButtonSegment(value: f, label: Text(f.label)))
                    .toList(),
                selected: {filter},
                // The checkmark shifts every label sideways when a segment is
                // picked, which on three short segments reads as the whole
                // control jumping.
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    ref.read(recordFilterProvider.notifier).set(s.first),
              ),
            ),
          ),
          Expanded(
            child: AsyncView<List<MedicalRecord>>(
              value: records,
              onRetry: () => ref.invalidate(ownRecordsProvider),
              skeleton: const SkeletonList(
                count: 5,
                rows: 2,
                padding: EdgeInsets.fromLTRB(
                  Insets.lg,
                  0,
                  Insets.lg,
                  Insets.fabSafeBottom,
                ),
              ),
              data: (all) {
                final filtered = all.where(filter.matches).toList()
                  // Newest first. A medical record list is read from the top
                  // for "what happened most recently", never from the bottom.
                  ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.folder_open_outlined,
                    title: context.l10n.recordsEmpty,
                    message: context.l10n.recordsEmptyBody,
                    action: FilledButton.icon(
                      onPressed: () => context.push(Routes.recordUpload),
                      icon: const Icon(Icons.upload_file, size: 20),
                      label: Text(context.l10n.recordsUploadOne),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => ref.refresh(ownRecordsProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.lg,
                      0,
                      Insets.lg,
                      Insets.fabSafeBottom,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Insets.md - 2),
                    // Keyed by record: the segmented filter rewrites this
                    // list in place, and an unkeyed stateful child would
                    // inherit the previous occupant's animation state.
                    itemBuilder: (_, i) => FadeSlideIn(
                      key: ValueKey(filtered[i].id),
                      index: i,
                      child: RecordTile(record: filtered[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class RecordTile extends StatelessWidget {
  const RecordTile({super.key, required this.record, this.onTap});

  final MedicalRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = record;
    final readable = r.isReadable;

    return PressableScale(
      enabled: readable,
      child: Card(
        child: InkWell(
          onTap: readable
              ? (onTap ?? () => context.push(Routes.recordDetail(r.id)))
              : null,
          child: Padding(
            padding: const EdgeInsets.all(Insets.md + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: Radii.smAll,
                  ),
                  child: Icon(
                    _iconFor(r.type),
                    size: 22,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          r.type.label,
                          Fmt.date(r.recordedAt),
                          if (r.issuedByName != null) r.issuedByName!,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // A record is not readable until scanning completes.
                      // Saying so is better than a tile that simply refuses to
                      // open — a dead tap has no explanation attached to it.
                      if (!readable) ...[
                        const SizedBox(height: Insets.sm),
                        StatusChip(
                          // Short forms: the full sentence belongs on the
                          // record detail screen, where there is room to say
                          // what to do about it. A chip is a label, not a
                          // paragraph.
                          label: r.scanStatus == ScanStatus.pending
                              ? context.l10n.recordsCheckingShort
                              : context.l10n.recordScanFailedShort,
                          tone: r.scanStatus == ScanStatus.pending
                              ? Tone.warning
                              : Tone.danger,
                          icon: r.scanStatus == ScanStatus.pending
                              ? Icons.hourglass_top
                              : Icons.error_outline,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      r.sizeLabel,
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(height: Insets.sm),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: readable
                          ? theme.colorScheme.outline
                          : Colors.transparent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(RecordType type) => switch (type) {
        RecordType.labReport => Icons.science_outlined,
        RecordType.scan => Icons.monitor_heart_outlined,
        RecordType.xray => Icons.broken_image_outlined,
        RecordType.prescription => Icons.receipt_long_outlined,
        RecordType.dischargeSummary => Icons.local_hospital_outlined,
        RecordType.vaccination => Icons.vaccines_outlined,
        RecordType.other => Icons.description_outlined,
      };
}
