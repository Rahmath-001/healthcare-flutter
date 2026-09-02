import 'package:flutter/material.dart';

/// Full-width outlined Google sign-in button with loading state.
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
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const Text(
                'Google Sign in',
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}
