import '../../../l10n/l10n.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/files/blob_client.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../data/prescription_pdf.dart';
import '../domain/prescription.dart';

final prescriptionsProvider = FutureProvider<List<Prescription>>((ref) async {
  return ref.watch(prescriptionRepositoryProvider).listForPatient();
});

final prescriptionByIdProvider =
    FutureProvider.family<Prescription, String>((ref, id) async {
  return ref.watch(prescriptionRepositoryProvider).byId(id);
});

class PrescriptionsScreen extends ConsumerWidget {
  const PrescriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prescriptions = ref.watch(prescriptionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.prescriptionsTitle)),
      body: AsyncView<List<Prescription>>(
        value: prescriptions,
        onRetry: () => ref.invalidate(prescriptionsProvider),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No prescriptions yet',
              message: 'Prescriptions your doctor issues will appear here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(prescriptionsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _PrescriptionCard(prescription: list[i]),
            ),
          );
        },
      ),
    );
  }
}

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({required this.prescription});

  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = prescription;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/patient/prescriptions/${p.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(p.diagnosis ?? context.l10n.prescriptionTitle,
                        style: theme.textTheme.titleMedium),
                  ),
                  StatusChip(
                    label: p.isValid ? 'Valid' : p.status.name,
                    tone: p.isValid ? Tone.success : Tone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${p.providerName} · ${Fmt.date(p.issuedAt)}',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              ...p.items.take(3).map((i) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.medication_outlined,
                            size: 15, color: theme.colorScheme.outline),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(i.summary,
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  )),
              if (p.items.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('+${p.items.length - 3} more',
                      style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full prescription, laid out as the legal document it is.
///
/// Provider name, qualification and registration number are snapshots taken at
/// issue time, so this renders exactly as issued even if the doctor later edits
/// their profile.
class PrescriptionDetailScreen extends ConsumerWidget {
  const PrescriptionDetailScreen({super.key, required this.prescriptionId});

  final String prescriptionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prescription = ref.watch(prescriptionByIdProvider(prescriptionId));

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.prescriptionTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.prescriptionShare,
            icon: const Icon(Icons.ios_share),
            onPressed: prescription.value == null
                ? null
                : () => _sharePdf(ref, prescription.value!),
          ),
          IconButton(
            tooltip: context.l10n.prescriptionPrint,
            icon: const Icon(Icons.print_outlined),
            onPressed: prescription.value == null
                ? null
                : () => _printPdf(ref, prescription.value!),
          ),
        ],
      ),
      body: AsyncView<Prescription>(
        value: prescription,
        onRetry: () => ref.invalidate(prescriptionByIdProvider(prescriptionId)),
        data: (p) => _Detail(prescription: p),
      ),
    );
  }

  /// FR-RX-003: downloadable PDF.
  ///
  /// Hands the file to the platform share sheet, which is how a patient
  /// actually gets it to a pharmacy — WhatsApp, email, or Files.
  static Future<void> _sharePdf(WidgetRef ref, Prescription p) async {
    await Printing.sharePdf(
      bytes: await _bytes(ref, p),
      filename: 'MiDoctor-${p.verificationCode}.pdf',
    );
  }

  static Future<void> _printPdf(WidgetRef ref, Prescription p) async {
    await Printing.layoutPdf(onLayout: (_) async => _bytes(ref, p));
  }

  /// The server's frozen document if there is one, otherwise a local render.
  ///
  /// The order matters and is the whole point of this method. The server
  /// generates the PDF from the stored prescription and writes it write-once,
  /// so it is the copy a pharmacist can check against the verification code.
  /// The local renderer produces something that *looks* the same but is
  /// composed on the device — fine to read, not evidence of anything — and it
  /// exists because a patient with no signal still needs to be able to show a
  /// prescription at a counter.
  static Future<Uint8List> _bytes(WidgetRef ref, Prescription p) async {
    try {
      final official =
          await ref.read(prescriptionRepositoryProvider).officialPdf(p.id);
      if (official != null) {
        return await ref.read(blobClientProvider).get(url: official.url);
      }
    } on Failure {
      // Falls through to the local render: a patient standing at a pharmacy
      // counter needs a document more than they need the better one.
    }
    return Uint8List.fromList(await PrescriptionPdf.build(p));
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.prescription});

  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = prescription;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.providerName, style: theme.textTheme.titleMedium),
                Text(p.providerQualification, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                // Mandatory on every prescription under NMC rules.
                Text('Reg. No. ${p.providerRegistrationNumber}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Patient', style: theme.textTheme.bodySmall),
                          Text(p.patientName,
                              style: theme.textTheme.bodyMedium),
                          Text('${p.patientAge} · ${p.patientGender}',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Issued', style: theme.textTheme.bodySmall),
                        Text(Fmt.date(p.issuedAt),
                            style: theme.textTheme.bodyMedium),
                        Text(p.verificationCode,
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (p.diagnosis != null) ...[
          Text('Diagnosis', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(p.diagnosis!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
        ],
        Text('Medicines', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < p.items.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text('${i + 1}'),
                  ),
                  title: Text('${p.items[i].drugName} ${p.items[i].strength}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.items[i].genericName,
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 2),
                      Text(
                        '${p.items[i].frequency} · ${p.items[i].durationDays} '
                        'day${p.items[i].durationDays == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (p.items[i].instructions != null)
                        Text(p.items[i].instructions!,
                            style: theme.textTheme.bodySmall),
                    ],
                  ),
                  isThreeLine: true,
                ),
              ],
            ],
          ),
        ),
        if (p.advice != null) ...[
          const SizedBox(height: 20),
          Text('Advice', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(p.advice!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 20),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.qr_code_2,
                    size: 36, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pharmacy verification',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        'A pharmacist can confirm this prescription with code '
                        '${p.verificationCode}.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Retained until ${Fmt.date(p.retainedUntil)} as required by medical '
          'record rules.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
