import 'package:flutter/material.dart';

/// Full-width "Continue with Apple" button with a loading state.
///
/// Apple's Human Interface Guidelines constrain this button far more than a
/// generic OAuth one: it must carry the Apple logo, use the exact wording
/// "Continue with Apple" (or "Sign in with Apple"), and be black on light
/// backgrounds / white on dark ones. It must also be no less prominent than
/// the other sign-in options, which is why it matches [GoogleButton]'s height
/// and full width rather than being tucked away as a text link.
class AppleButton extends StatelessWidget {
  const AppleButton({super.key, required this.onPressed, this.loading = false});

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? Colors.white : Colors.black;
    final foreground = isDark ? Colors.black : Colors.white;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.6),
          disabledForegroundColor: foreground.withValues(alpha: 0.8),
        ),
        icon: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: foreground,
                ),
              )
            : const Icon(Icons.apple, size: 26),
        label: const Text(
          'Continue with Apple',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
