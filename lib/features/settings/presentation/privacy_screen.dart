import '../../../l10n/l10n.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/service_providers.dart';
import '../../../shared/formatters.dart';

/// Data-protection controls.
///
/// Implements the data-principal rights the DPDP Act 2023 requires and the spec
/// never mentions: access, correction, portability, erasure, and a named
/// grievance route. Apple also requires in-app account deletion for any app
/// that lets you create an account.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _exporting = false;
  bool _deleting = false;

  /// DPDP s.11. Fetches the export and hands it to the platform share sheet,
  /// which is how a person actually keeps a file on a phone.
  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final json = await ref.read(accountRepositoryProvider).exportData();
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: Uint8List.fromList(utf8.encode(json)),
        filename: 'MiDoctor-my-data.json',
      );
    } on Failure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.privacyDeleteTitle),
        content: const Text(
          'Your profile, appointments and sharing permissions will be deleted, '
          'and every doctor will immediately lose access to your records.\n\n'
          'Consultation notes and prescriptions must be kept for 3 years under '
          'medical record rules, so those are retained and then deleted. They '
          'are not used for anything else.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.privacyKeepAccount),
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

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      // Severs the app's link to the user's Apple ID. Apple requires this on
      // account deletion, and it has to happen while the authorization code
      // from this session is still in memory. Best-effort: it never blocks
      // deletion, because failing to revoke an Apple token is not a reason to
      // refuse someone their erasure right.
      await ref.read(authServiceProvider).revokeAppleToken();

      final outcome =
          await ref.read(accountRepositoryProvider).requestDeletion();

      // The server has already destroyed every session; this clears the local
      // copy and drops the router back to the auth stack.
      await ref.read(sessionControllerProvider.notifier).signOutLocally();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Your account is deleted. Consultation notes and prescriptions are '
            'kept until ${Fmt.date(outcome.clinicalRetentionUntil)} because '
            'medical record rules require it, and are then destroyed.',
          ),
        ),
      );
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.privacyTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(context.l10n.privacyYourRights,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Under India’s Digital Personal Data Protection Act, you can see '
            'what we hold about you, correct it, take a copy elsewhere, and '
            'ask us to delete it.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: Text(context.l10n.privacyDownloadData),
                  subtitle: const Text(
                    'Profile, appointments, records and sharing history',
                  ),
                  trailing: _exporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _exporting ? null : _export,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(context.l10n.privacyCorrect),
                  subtitle: Text(context.l10n.privacyUpdateDetails),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.editProfile),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(context.l10n.privacyRetentionTitle,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _RetentionRow(
            label: 'Consultation notes and prescriptions',
            value: '3 years, as medical record rules require',
          ),
          const _RetentionRow(
            label: 'Video and audio consultations',
            value: 'Never recorded',
          ),
          const _RetentionRow(
            label: 'Chat messages from a consultation',
            value: 'Kept with your medical record',
          ),
          const _RetentionRow(
            label: 'Record access log',
            value: 'Kept so you can always audit who looked at what',
          ),
          const SizedBox(height: 20),
          Text(context.l10n.privacyGrievanceTitle,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Text(context.l10n.privacyGrievanceOfficer),
              subtitle: const Text('grievance@midoctor.in'),
            ),
          ),
          const SizedBox(height: 24),
          Text(context.l10n.privacyDangerZone,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.delete_forever_outlined,
                  color: theme.colorScheme.error),
              title: Text(context.l10n.privacyDeleteAccount,
                  style: TextStyle(color: theme.colorScheme.error)),
              subtitle: Text(context.l10n.privacyThisCannotBeUndone),
              trailing: _deleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : null,
              onTap: _deleting ? null : _deleteAccount,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Signed in as ${ref.watch(currentSessionProvider)?.greetingName ?? ''}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _RetentionRow extends StatelessWidget {
  const _RetentionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule, size: 15, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(value, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
