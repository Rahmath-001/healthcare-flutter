import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

/// Full-width filled button with built-in loading state.
///
/// Height, shape and type now come from `filledButtonTheme`, so this and a bare
/// `FilledButton` are the same button. It used to hard-code 52 and a 16pt
/// label, which is why the primary action on the login screen was visibly
/// taller and heavier than the primary action on the booking screen.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: AnimatedSwitcher(
          // The label and the spinner cross-fade rather than cutting, so a
          // fast round trip does not read as the button flickering.
          duration: Motion.of(context, Motion.fast),
          child: loading
              ? SizedBox(
                  key: const ValueKey('loading'),
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    // Explicit: the indicator theme paints it `primary`, which
                    // on a primary-filled button is invisible.
                    color: scheme.onPrimary,
                  ),
                )
              : Row(
                  key: const ValueKey('label'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20),
                      const SizedBox(width: Insets.sm),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
