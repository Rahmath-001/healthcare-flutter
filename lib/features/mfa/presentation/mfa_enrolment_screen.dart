import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/sensitive_clipboard.dart';

/// TOTP enrolment for providers.
///
/// TOTP rather than SMS, deliberately. The primary factor for most users here
/// is already an SMS OTP, so SMS-as-second-factor is not a second factor at
/// all; SIM-swap is a live threat in India; and TOTP is free, works offline and
/// runs on any handset.
class MfaEnrolmentScreen extends ConsumerStatefulWidget {
  const MfaEnrolmentScreen({super.key});

  @override
  ConsumerState<MfaEnrolmentScreen> createState() => _MfaEnrolmentScreenState();
}

class _MfaEnrolmentScreenState extends ConsumerState<MfaEnrolmentScreen> {
  final _codeCtrl = TextEditingController();

  String? _secret;
  bool _loading = true;
  bool _verifying = false;
  List<String>? _recoveryCodes;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    try {
      final result =
          await ref.read(credentialsRepositoryProvider).beginMfaEnrolment();
      if (mounted) {
        setState(() {
          _secret = result.secret;
          _loading = false;
        });
      }
    } on Failure catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _confirm() async {
    setState(() => _verifying = true);
    try {
      final codes = await ref
          .read(credentialsRepositoryProvider)
          .confirmMfaEnrolment(_codeCtrl.text);
      if (mounted) setState(() => _recoveryCodes = codes);
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_recoveryCodes == null
            ? 'Set up two-factor'
            : 'Save your recovery codes'),
        automaticallyImplyLeading: _recoveryCodes == null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _recoveryCodes != null
              ? _RecoveryCodes(codes: _recoveryCodes!)
              : _setupBody(),
    );
  }

  Widget _setupBody() {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Two-factor authentication is required before you can see '
            'patients. It protects your ability to issue prescriptions and '
            'read patient records.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text(context.l10n.mfaInstallApp, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            'Google Authenticator, Microsoft Authenticator or Authy all work.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Text(context.l10n.mfaAddKey, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // A QR code needs a rendering package; the manual key works
                  // in every authenticator and needs no dependency.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _secret ?? '',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 18,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final note = context.l10n.mfaClipboardCleared;
                      // The TOTP seed is an authentication factor. It goes to
                      // the clipboard because transcribing base32 by hand is
                      // how people give up on MFA — and it is taken back a
                      // minute later. See `SensitiveClipboard`.
                      await SensitiveClipboard.copy(_secret ?? '');
                      if (!mounted) return;
                      messenger.showSnackBar(SnackBar(content: Text(note)));
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(context.l10n.mfaCopyKey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(context.l10n.mfaEnterCode, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              counterText: '',
              border: OutlineInputBorder(),
              hintText: '000000',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed:
                  _codeCtrl.text.length == 6 && !_verifying ? _confirm : null,
              child: _verifying
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(context.l10n.mfaVerifyEnable),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoveryCodes extends StatelessWidget {
  const _RecoveryCodes({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(context.l10n.mfaIsOn,
                          style: theme.textTheme.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Save these recovery codes somewhere safe. Each one works '
                  'once, and they are the only way back into your account if '
                  'you lose your phone. We cannot show them again.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 20,
                      runSpacing: 12,
                      children: codes
                          .map((c) => SelectableText(
                                c,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 16,
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: codes.join('\n')));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.mfaRecoveryCopied)),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(context.l10n.mfaCopyAllCodes),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.mfaSavedThem),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
