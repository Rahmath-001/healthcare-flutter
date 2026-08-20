import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<RecordFilter>(
              segments: RecordFilter.values
                  .map((f) => ButtonSegment(value: f, label: Text(f.label)))
                  .toList(),
              selected: {filter},
              onSelectionChanged: (s) =>
                  ref.read(recordFilterProvider.notifier).set(s.first),
            ),
          ),
          Expanded(
            child: AsyncView<List<MedicalRecord>>(
              value: records,
              onRetry: () => ref.invalidate(ownRecordsProvider),
              data: (all) {
                final filtered = all.where(filter.matches).toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.folder_open_outlined,
                    title: context.l10n.recordsEmpty,
                    message: context.l10n.recordsEmptyBody,
                    action: FilledButton.icon(
                      onPressed: () => context.push(Routes.recordUpload),
                      icon: const Icon(Icons.upload_file),
                      label: Text(context.l10n.recordsUploadOne),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(ownRecordsProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => RecordTile(record: filtered[i]),
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

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: r.isReadable
            ? (onTap ?? () => context.push(Routes.recordDetail(r.id)))
            : null,
        leading: CircleAvatar(
          backgroundColor:
              theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          child: Icon(_iconFor(r.type), color: theme.colorScheme.primary),
        ),
        title: Text(r.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${r.type.label} · ${Fmt.date(r.recordedAt)}',
              style: theme.textTheme.bodySmall,
            ),
            if (r.issuedByName != null)
              Text(r.issuedByName!, style: theme.textTheme.bodySmall),
            // A record is not readable until scanning completes. Saying so is
            // better than a tile that simply refuses to open.
            if (!r.isReadable) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Expanded, because this sits inside a ListTile subtitle and
                  // the message is longer than the tile is wide — it overflowed
                  // by ~190px before a widget test caught it.
                  Expanded(
                    child: Text(
                      r.scanStatus == ScanStatus.pending
                          ? context.l10n.recordsChecking
                          : context.l10n.recordScanFailed,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: Text(r.sizeLabel, style: theme.textTheme.bodySmall),
        isThreeLine: r.issuedByName != null || !r.isReadable,
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
