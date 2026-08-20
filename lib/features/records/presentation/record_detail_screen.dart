import '../../../l10n/l10n.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/files/blob_client.dart';
import '../../../core/security/screen_protection.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/medical_record.dart';
import 'records_controller.dart';

/// One record, resolved out of the patient's own list.
///
/// There is deliberately no `byId` on `RecordsRepository`: a record is only ever
/// reachable through a list the caller is already entitled to — their own, or
/// one resolved against a live consent grant. Deriving the detail from that list
/// keeps the entitlement check in exactly one place.
final recordByIdProvider =
    FutureProvider.family<MedicalRecord, String>((ref, id) async {
  final records = await ref.watch(ownRecordsProvider.future);
  for (final r in records) {
    if (r.id == id) return r;
  }
  throw const Failure(
    kind: FailureKind.notFound,
    message: 'That record is no longer available.',
    code: 'RECORD_NOT_FOUND',
  );
});

/// Removes a record the patient owns, then refreshes the list behind it.
Future<void> deleteRecord(WidgetRef ref, String id) async {
  await ref.read(recordsRepositoryProvider).delete(id);
  ref.invalidate(ownRecordsProvider);
}

class RecordDetailScreen extends ConsumerWidget {
  const RecordDetailScreen({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(recordByIdProvider(recordId));

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.recordDetailTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.recordDeleteTitle,
            icon: const Icon(Icons.delete_outline),
            onPressed: record.value == null
                ? null
                : () => _confirmDelete(context, ref, record.value!),
          ),
        ],
      ),
      body: AsyncView<MedicalRecord>(
        value: record,
        onRetry: () => ref.invalidate(recordByIdProvider(recordId)),
        data: (r) => _Detail(record: r),
      ),
    );
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    MedicalRecord record,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text(
          '"${record.title}" will be removed from your records, and any doctor '
          'you have shared it with will lose access to it.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.recordKeepIt),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await deleteRecord(ref, record.id);
      if (!context.mounted) return;
      context.pop();
    } on Failure catch (f) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.message)));
    }
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.record});

  final MedicalRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final r = record;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(r.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '${r.type.label} · ${Fmt.date(r.recordedAt)}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        if (!r.isReadable) ...[
          _ScanNotice(status: r.scanStatus),
          const SizedBox(height: 20),
        ],
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _Row(label: context.l10n.recordType, value: r.type.label),
              _Row(
                label: context.l10n.recordAddedBy,
                value: r.source == RecordSource.provider
                    ? (r.issuedByName ?? context.l10n.recordAddedByDoctor)
                    : context.l10n.recordAddedByYou,
              ),
              _Row(
                  label: context.l10n.recordTakenOn,
                  value: Fmt.date(r.recordedAt)),
              _Row(
                  label: context.l10n.recordUploaded,
                  value: Fmt.date(r.uploadedAt)),
              _Row(label: context.l10n.recordSize, value: r.sizeLabel),
              if (r.pageCount != null)
                _Row(label: context.l10n.recordPages, value: '${r.pageCount}'),
            ],
          ),
        ),
        if (r.notes != null && r.notes!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(context.l10n.recordYourNotes,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(r.notes!, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: r.isReadable ? () => _open(context, ref, r) : null,
          icon: const Icon(Icons.visibility_outlined),
          label: Text(context.l10n.recordOpenFile),
        ),
      ],
    );
  }

  /// Fetches the file and shows it **inside** the app.
  ///
  /// Handing the signed URL to an external browser would be one line, and would
  /// also carry the document straight out of `ProtectedScreen` — past
  /// `FLAG_SECURE`, into the browser's cache and its recents thumbnail. A
  /// record stays on this side of that boundary.
  static Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    MedicalRecord record,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final url =
          await ref.read(recordsRepositoryProvider).downloadUrl(record.id);
      final bytes = await ref.read(blobClientProvider).get(url: url);
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ProtectedScreen(
            child: _Viewer(record: record, bytes: bytes),
          ),
        ),
      );
    } on Failure catch (f) {
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }
}

/// Renders a fetched record without writing it to disk.
class _Viewer extends StatelessWidget {
  const _Viewer({required this.record, required this.bytes});

  final MedicalRecord record;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final isPdf = record.contentType == 'application/pdf';

    return Scaffold(
      appBar: AppBar(title: Text(record.title)),
      body: isPdf
          ? PdfPreview(
              build: (_) => bytes,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              // Sharing and printing would both copy the file out of the app.
              allowSharing: false,
              allowPrinting: false,
            )
          : InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: Image.memory(
                  bytes,
                  errorBuilder: (_, __, ___) => EmptyState(
                    icon: Icons.broken_image_outlined,
                    title: context.l10n.recordCannotDisplay,
                    message: context.l10n.recordCannotDisplayBody,
                  ),
                ),
              ),
            ),
    );
  }
}

class _ScanNotice extends StatelessWidget {
  const _ScanNotice({required this.status});

  final ScanStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, colour, text) = switch (status) {
      ScanStatus.pending => (
          Icons.hourglass_top_outlined,
          theme.colorScheme.tertiary,
          'This file is still being checked for viruses. It will open once the '
              'check finishes.',
        ),
      ScanStatus.infected => (
          Icons.gpp_bad_outlined,
          theme.colorScheme.error,
          'This file failed a virus check and cannot be opened or shared.',
        ),
      ScanStatus.failed => (
          Icons.error_outline,
          theme.colorScheme.error,
          'We could not check this file. Try uploading it again.',
        ),
      ScanStatus.clean => (Icons.check, theme.colorScheme.primary, ''),
    };

    return Card(
      margin: EdgeInsets.zero,
      color: colour.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colour),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
