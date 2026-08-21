import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/files/file_picker_service.dart';
import '../../../core/router/routes.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/credential.dart';
import 'credentials_controller.dart';

/// Provider verification checklist.
///
/// Three gates must all pass before submission: every document present, a
/// council registration number, and MFA enrolled. MFA is part of the gate
/// because an approved provider can issue prescriptions and read patient
/// records — the account must be hard to take over *before* it gains those
/// powers, not after.
class CredentialsScreen extends ConsumerWidget {
  const CredentialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklist = ref.watch(verificationChecklistProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.credentialsGetVerified)),
      body: AsyncView<VerificationChecklist>(
        value: checklist,
        onRetry: () => ref.invalidate(verificationChecklistProvider),
        data: (c) => _Body(checklist: c),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.checklist});

  final VerificationChecklist checklist;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      refreshChecklist(ref);
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload(CredentialKind kind) async {
    final repo = ref.read(credentialsRepositoryProvider);

    // Identity is verified through DigiLocker, never by uploading an ID
    // document. There is deliberately no file path for this credential kind.
    if (kind.isDigiLocker) {
      await _run(repo.verifyIdentityWithDigiLocker);
      return;
    }

    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _SourceSheet(),
    );
    if (source == null) return;

    final picker = ref.read(filePickerServiceProvider);
    final PickedFile? picked;
    try {
      picked = source == 'camera'
          ? await picker.captureWithCamera()
          : await picker.pickDocument();
      if (picked == null) return;
      picker.validate(picked, maxBytes: FilePickerService.maxCredentialBytes);
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }

    final file = picked;
    await _run(() => repo.uploadDocument(
          kind: kind,
          fileName: file.name,
          sizeBytes: file.sizeBytes,
          file: file,
        ));
  }

  Future<void> _editRegistrationNumber() async {
    final controller =
        TextEditingController(text: widget.checklist.registrationNumber ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.credentialsRegistrationNumberLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: context.l10n.credentialsRegistrationHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'We verify this against the NMC or State Medical Council '
              'register. It also appears on every prescription you issue.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(context.l10n.actionSave),
          ),
        ],
      ),
    );

    if (value == null) return;
    await _run(() =>
        ref.read(credentialsRepositoryProvider).setRegistrationNumber(value));
  }

  Future<void> _submit() async {
    await _run(ref.read(credentialsRepositoryProvider).submitForReview);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.credentialsSubmittedForReview)),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.checklist;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              LinearProgressIndicator(
                value: c.completedCount / VerificationChecklist.totalSteps,
              ),
              const SizedBox(height: 8),
              Text(
                '${c.completedCount} of ${VerificationChecklist.totalSteps} '
                'steps complete',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Text(context.l10n.credentialsStepDocuments,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...c.credentials.map((cred) => _CredentialTile(
                    credential: cred,
                    busy: _busy,
                    onUpload: () => _upload(cred.kind),
                  )),
              const SizedBox(height: 24),
              Text(context.l10n.credentialsStepRegistration,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(
                    c.hasRegistrationNumber
                        ? Icons.check_circle
                        : Icons.badge_outlined,
                    color: c.hasRegistrationNumber
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  title: Text(context.l10n.credentialsCouncilRegistration),
                  subtitle: Text(
                    c.registrationNumber ?? 'Not provided yet',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _editRegistrationNumber,
                ),
              ),
              const SizedBox(height: 24),
              Text(context.l10n.credentialsStepMfa,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(
                    c.mfaEnrolled
                        ? Icons.check_circle
                        : Icons.security_outlined,
                    color: c.mfaEnrolled ? theme.colorScheme.primary : null,
                  ),
                  title: Text(context.l10n.credentialsAuthenticatorApp),
                  subtitle: Text(
                    c.mfaEnrolled
                        ? 'Enabled'
                        : 'Required before you can see patients',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy
                      ? null
                      : () async {
                          await context.push(Routes.providerMfa);
                          if (context.mounted) refreshChecklist(ref);
                        },
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline,
                      size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your documents are encrypted and only seen by the '
                      'MiDoctor verification team. We never store a copy of '
                      'your Aadhaar.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: c.canSubmit && !_busy ? _submit : null,
                child: Text(
                  c.canSubmit
                      ? 'Submit for review'
                      : 'Complete all steps to submit',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CredentialTile extends StatelessWidget {
  const _CredentialTile({
    required this.credential,
    required this.busy,
    required this.onUpload,
  });

  final ProviderCredential credential;
  final bool busy;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = credential;
    final done = c.isProvided;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.upload_file_outlined,
                  color: done ? theme.colorScheme.primary : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(c.kind.label, style: theme.textTheme.titleSmall),
                ),
                StatusChip(
                  label: c.status.label,
                  tone: switch (c.status) {
                    CredentialReviewStatus.accepted => Tone.success,
                    CredentialReviewStatus.rejected => Tone.danger,
                    _ => Tone.neutral,
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(c.kind.helpText, style: theme.textTheme.bodySmall),

            // A rejection is always explained with a reason code, so the
            // provider knows exactly what to fix (FR-PROV-003).
            if (c.reasonCode != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(c.reasonCode!.label,
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ],

            if (c.fileName != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined,
                      size: 15, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      c.fileName!,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (c.uploadedAt != null)
                    Text(Fmt.relative(c.uploadedAt!),
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ],

            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onUpload,
                icon: Icon(
                  c.kind.isDigiLocker
                      ? Icons.verified_user_outlined
                      : Icons.upload,
                  size: 18,
                ),
                label: Text(
                  c.kind.isDigiLocker
                      ? (done
                          ? 'Re-verify with DigiLocker'
                          : 'Verify with DigiLocker')
                      : (done ? 'Replace document' : 'Upload document'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where a credential document comes from. Certificates are usually paper, so
/// the camera is offered first.
class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(context.l10n.credentialsTakePhoto),
            subtitle: Text(context.l10n.credentialsPaperCertificate),
            onTap: () => Navigator.of(context).pop('camera'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: Text(context.l10n.credentialsChooseFile),
            subtitle: Text(context.l10n.credentialsFileTypes),
            onTap: () => Navigator.of(context).pop('file'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
