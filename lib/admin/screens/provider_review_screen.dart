import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../core/error/failure.dart';
import '../../core/files/blob_client.dart';
import '../../core/session/user_role.dart';
import '../../features/credentials/domain/credential.dart';
import '../../features/hospitals/domain/hospital.dart';
import '../../features/hospitals/presentation/hospital_controller.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/async_view.dart';
import '../admin_app.dart';
import '../data/operations_repository.dart';
import '../providers/operations_providers.dart';
import '../router/admin_router.dart';

/// One applicant, and the decision.
///
/// The layout puts the document viewer beside the checklist rather than behind
/// a tab, because the reviewer's actual task is comparing a name on a
/// certificate against a name on a form — and a decision made from memory of a
/// document in another tab is a worse decision.
class ProviderReviewScreen extends ConsumerStatefulWidget {
  const ProviderReviewScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<ProviderReviewScreen> createState() =>
      _ProviderReviewScreenState();
}

class _ProviderReviewScreenState extends ConsumerState<ProviderReviewScreen> {
  ReviewDocument? _open;
  Uint8List? _bytes;
  bool _loadingDocument = false;
  bool _busy = false;

  Future<void> _openDocument(ReviewDocument document) async {
    setState(() {
      _open = document;
      _bytes = null;
      _loadingDocument = true;
    });

    try {
      final repo = ref.read(operationsRepositoryProvider);
      // The URL is minted per open and the open is logged server-side. A page
      // load is not a disclosure; looking at someone's certificate is.
      final url = await repo.documentUrl(document.id);
      final bytes = await ref.read(blobClientProvider).get(url: url);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loadingDocument = false;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _loadingDocument = false);
      _toast(f.message);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(providerDossierProvider(widget.userId));
      ref.invalidate(reviewQueueProvider);
      if (!mounted) return;
      _toast(done);
    } on Failure catch (f) {
      if (!mounted) return;
      _toast(f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decideDocument(ReviewDocument document, bool accept) async {
    RejectionReasonCode? reason;
    String? note;

    if (!accept) {
      final outcome = await showDialog<(RejectionReasonCode, String?)>(
        context: context,
        builder: (_) => const _RejectDocumentDialog(),
      );
      if (outcome == null) return;
      reason = outcome.$1;
      note = outcome.$2;
    }

    await _run(
      () => ref.read(operationsRepositoryProvider).decideDocument(
            document.id,
            accept: accept,
            reasonCode: reason,
            note: note,
          ),
      accept ? 'Document accepted.' : 'Document rejected.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final dossier = ref.watch(providerDossierProvider(widget.userId));
    final scopes = ref.watch(operatorScopesProvider);

    return AsyncView<ProviderDossier>(
      value: dossier,
      onRetry: () => ref.invalidate(providerDossierProvider(widget.userId)),
      data: (d) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(dossier: d, onBack: () => context.go(AdminRoutes.queue)),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 420,
                    child: _Checklist(
                      dossier: d,
                      busy: _busy,
                      canDecide: scopes.canDecideProviders,
                      openId: _open?.id,
                      onOpen: _openDocument,
                      onDecide: _decideDocument,
                      onApprove: () => _approve(d),
                      onReject: () => _reject(d),
                      onClaim: () => _run(
                        () => ref
                            .read(operationsRepositoryProvider)
                            .claimForReview(d.userId),
                        'Picked up for review.',
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _DocumentPane(
                      document: _open,
                      bytes: _bytes,
                      loading: _loadingDocument,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(ProviderDossier d) async {
    final profile = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ApproveDialog(dossier: d),
    );
    if (profile == null) return;

    await _run(
      () => ref
          .read(operationsRepositoryProvider)
          .approveProvider(d.userId, profile: profile),
      'Approved. They can now see patients.',
    );
  }

  Future<void> _reject(ProviderDossier d) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectApplicationDialog(),
    );
    if (reason == null) return;

    await _run(
      () => ref
          .read(operationsRepositoryProvider)
          .rejectProvider(d.userId, reason: reason),
      'Application rejected.',
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.dossier, required this.onBack});

  final ProviderDossier dossier;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to queue',
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dossier.displayName ?? 'Unnamed applicant',
              style: theme.textTheme.titleLarge,
            ),
            Text(
              [
                dossier.providerStatus.label,
                if (dossier.email != null) dossier.email!,
                if (dossier.phone != null) dossier.phone!,
              ].join('  ·  '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({
    required this.dossier,
    required this.busy,
    required this.canDecide,
    required this.openId,
    required this.onOpen,
    required this.onDecide,
    required this.onApprove,
    required this.onReject,
    required this.onClaim,
  });

  final ProviderDossier dossier;
  final bool busy;
  final bool canDecide;
  final String? openId;
  final void Function(ReviewDocument) onOpen;
  final void Function(ReviewDocument, bool accept) onDecide;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      children: [
        Card(
          child: Column(
            children: [
              _Row(
                label: 'Registration number',
                value: dossier.registrationNumber ?? 'Not provided',
                ok: dossier.registrationNumber != null,
              ),
              const Divider(height: 1),
              _Row(
                label: 'Two-factor',
                value: dossier.mfaEnrolled ? 'Enrolled' : 'Not enrolled',
                ok: dossier.mfaEnrolled,
              ),
              const Divider(height: 1),
              _Row(
                label: 'Account',
                value: dossier.accountStatus.label,
                ok: dossier.accountStatus == AccountStatus.active,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Text('Documents', style: theme.textTheme.titleMedium),
        ),
        for (final document in dossier.documents)
          Card(
            color: openId == document.id
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          document.kind.label,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        document.status.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: switch (document.status) {
                            CredentialReviewStatus.accepted =>
                              theme.colorScheme.primary,
                            CredentialReviewStatus.rejected =>
                              theme.colorScheme.error,
                            _ => theme.colorScheme.onSurfaceVariant,
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${document.fileName ?? 'File'} · '
                    '${(document.sizeBytes / 1024).toStringAsFixed(0)} KB · '
                    '${Fmt.date(document.uploadedAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (document.reasonCode != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      document.reasonCode!.label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed:
                            document.hasFile ? () => onOpen(document) : null,
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: Text(
                          document.hasFile ? 'Open' : 'No file',
                        ),
                      ),
                      const Spacer(),
                      if (canDecide) ...[
                        TextButton(
                          onPressed: busy || !document.hasFile
                              ? null
                              : () => onDecide(document, false),
                          child: Text(
                            'Reject',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                        const SizedBox(width: 4),
                        FilledButton.tonal(
                          onPressed: busy || !document.hasFile
                              ? null
                              : () => onDecide(document, true),
                          child: const Text('Accept'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (dossier.providerStatus == ProviderStatus.submitted)
          OutlinedButton.icon(
            onPressed: busy ? null : onClaim,
            icon: const Icon(Icons.pan_tool_alt_outlined),
            label: const Text('Pick this up for review'),
          ),
        if (canDecide) ...[
          const SizedBox(height: 12),
          if (!dossier.isApprovable)
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Not ready to approve',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    for (final item in dossier.outstanding)
                      Text('• $item', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  child: Text(
                    'Reject application',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  // Enabled only when every gate is satisfied. The server
                  // re-checks; this stops a reviewer wasting a click.
                  onPressed: busy || !dossier.isApprovable ? null : onApprove,
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.ok});

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        ok ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        color: ok ? scheme.primary : scheme.outline,
      ),
      title: Text(label),
      trailing: Text(value),
    );
  }
}

/// The document itself.
class _DocumentPane extends StatelessWidget {
  const _DocumentPane({
    required this.document,
    required this.bytes,
    required this.loading,
  });

  final ReviewDocument? document;
  final Uint8List? bytes;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (document == null) {
      return const Card(
        child: EmptyState(
          icon: Icons.description_outlined,
          title: 'No document open',
          message: 'Choose a document on the left to read it here.',
        ),
      );
    }
    if (loading) {
      return const Card(child: Center(child: CircularProgressIndicator()));
    }
    if (bytes == null) {
      return const Card(
        child: EmptyState(
          icon: Icons.error_outline,
          title: 'Could not open',
          message: 'The document could not be fetched. Try again.',
        ),
      );
    }

    return Card(
      child: document!.contentType == 'application/pdf'
          ? PdfPreview(
              build: (_) => bytes!,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              // A reviewer reads it here; downloading it puts a doctor's
              // identity document into a laptop's Downloads folder.
              allowSharing: false,
              allowPrinting: false,
            )
          : InteractiveViewer(
              maxScale: 8,
              child: Center(child: Image.memory(bytes!)),
            ),
    );
  }
}

class _RejectDocumentDialog extends StatefulWidget {
  const _RejectDocumentDialog();

  @override
  State<_RejectDocumentDialog> createState() => _RejectDocumentDialogState();
}

class _RejectDocumentDialogState extends State<_RejectDocumentDialog> {
  RejectionReasonCode? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject this document'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The doctor sees this reason, so it has to be something they can '
              'act on. A structured code rather than free text, so it can be '
              'shown in their own language.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<RejectionReasonCode>(
              initialValue: _reason,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: [
                for (final code in RejectionReasonCode.values)
                  DropdownMenuItem(value: code, child: Text(code.label)),
              ],
              onChanged: (v) => setState(() => _reason = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _reason == null
              ? null
              : () => Navigator.of(context).pop(
                    (
                      _reason!,
                      _note.text.trim().isEmpty ? null : _note.text.trim()
                    ),
                  ),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

class _RejectApplicationDialog extends StatefulWidget {
  const _RejectApplicationDialog();

  @override
  State<_RejectApplicationDialog> createState() =>
      _RejectApplicationDialogState();
}

class _RejectApplicationDialogState extends State<_RejectApplicationDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject this application'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'They can correct the problem and submit again. Say what needs '
              'to change.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              autofocus: true,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _reason.text.trim().length < 10
              ? null
              : () => Navigator.of(context).pop(_reason.text.trim()),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

/// Collects the directory profile that approval publishes.
///
/// Approval is what puts a doctor in front of patients, so this is where the
/// public listing is composed — fee, specialty, hospital. It is deliberately a
/// reviewer's decision rather than the doctor's own free text.
class _ApproveDialog extends ConsumerStatefulWidget {
  const _ApproveDialog({required this.dossier});

  final ProviderDossier dossier;

  @override
  ConsumerState<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends ConsumerState<_ApproveDialog> {
  final _specialtyCode = TextEditingController();
  final _specialtyName = TextEditingController();
  final _qualification = TextEditingController();
  final _fee = TextEditingController();
  final _videoFee = TextEditingController();
  final _years = TextEditingController();
  final _languages = TextEditingController();
  final Set<String> _modes = <String>{};
  String? _hospitalId;

  @override
  void dispose() {
    for (final c in [
      _specialtyCode,
      _specialtyName,
      _qualification,
      _fee,
      _videoFee,
      _years,
      _languages,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _specialtyCode.text.trim().isNotEmpty &&
      _specialtyName.text.trim().isNotEmpty &&
      _qualification.text.trim().isNotEmpty &&
      _hospitalId != null &&
      int.tryParse(_fee.text) != null &&
      int.tryParse(_videoFee.text) != null &&
      _languages.text.trim().isNotEmpty &&
      _modes.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final hospitals = ref.watch(hospitalDirectoryProvider).value ??
        const <HospitalDirectoryEntry>[];
    final selectedHospital =
        hospitals.where((hospital) => hospital.id == _hospitalId).firstOrNull;
    return AlertDialog(
      title: const Text('Approve and publish'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This publishes ${widget.dossier.displayName ?? 'this doctor'} '
                'to the patient directory and lets them start consulting.',
              ),
              const SizedBox(height: 16),
              _field(_qualification, 'Qualification'),
              _pair(
                _field(_specialtyCode, 'Specialty code'),
                _field(_specialtyName, 'Specialty name'),
              ),
              DropdownButtonFormField<String>(
                value: _hospitalId,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Approved hospital'),
                hint: const Text('Choose an approved hospital'),
                items: [
                  for (final hospital in hospitals)
                    DropdownMenuItem(
                      value: hospital.id,
                      child: Text('${hospital.name} · ${hospital.city}'),
                    ),
                ],
                onChanged: hospitals.isEmpty
                    ? null
                    : (value) => setState(() => _hospitalId = value),
              ),
              if (hospitals.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 12),
                  child: Text(
                    'No approved hospitals are available. Review a real hospital application before publishing this provider.',
                  ),
                )
              else
                const SizedBox(height: 12),
              _pair(
                _field(_fee, 'In-person fee (₹)', number: true),
                _field(_videoFee, 'Video fee (₹)', number: true),
              ),
              _field(_years, 'Years of experience', number: true),
              _field(_languages, 'Languages (comma separated)'),
              Text('Consultation modes',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final mode in const <(String, String)>[
                    ('VIDEO', 'Video'),
                    ('AUDIO', 'Audio'),
                    ('IN_PERSON', 'In person'),
                  ])
                    FilterChip(
                      label: Text(mode.$2),
                      selected: _modes.contains(mode.$1),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _modes.add(mode.$1);
                        } else {
                          _modes.remove(mode.$1);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !_valid
              ? null
              : () => Navigator.of(context).pop(<String, dynamic>{
                    'qualification': _qualification.text.trim(),
                    'specialties': [
                      {
                        'code': _specialtyCode.text.trim().toUpperCase(),
                        'name': _specialtyName.text.trim(),
                      }
                    ],
                    'hospital': {
                      'id': selectedHospital!.id,
                      'name': selectedHospital.name,
                      'city': selectedHospital.city,
                      'address': selectedHospital.address,
                    },
                    'consultationFeeInr': int.parse(_fee.text),
                    'videoFeeInr': int.parse(_videoFee.text),
                    'yearsExperience': int.tryParse(_years.text) ?? 0,
                    'modes': _modes.toList(growable: false),
                    'languages': _languages.text
                        .split(',')
                        .map((value) => value.trim())
                        .where((value) => value.isNotEmpty)
                        .toList(growable: false),
                  }),
          child: const Text('Approve'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : null,
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _pair(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ],
      );
}
