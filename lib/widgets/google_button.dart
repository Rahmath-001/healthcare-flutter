import 'package:flutter/material.dart';

/// Full-width outlined "Continue with Google" button with loading state.
class GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;

  const GoogleButton(
      {super.key, required this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const Icon(Icons.g_mobiledata, size: 28),
        label:
            const Text('Continue with Google', style: TextStyle(fontSize: 16)),
      ),
    );
  }
}
