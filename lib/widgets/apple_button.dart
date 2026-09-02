import 'package:flutter/material.dart';

/// Full-width Apple sign-in button with a loading state.
///
/// It remains visually aligned with [GoogleButton] while keeping the product's
/// concise client-specified sign-in wording.
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
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.6),
          disabledForegroundColor: foreground.withValues(alpha: 0.8),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: foreground,
                ),
              )
            : const Text(
                'Apple Sign in',
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}
