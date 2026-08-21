import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Full-width outlined "Continue with Google" button with loading state.
///
/// Sized by `outlinedButtonTheme` so it matches [PrimaryButton] and
/// [AppleButton] exactly — the three stack directly on top of each other on
/// the login screen, where a 2px height difference is the most visible defect
/// on the page.
class GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;

  const GoogleButton({
    super.key,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const Icon(Icons.g_mobiledata, size: 28),
        label: Text(
          context.l10n.authContinueWithGoogle,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
