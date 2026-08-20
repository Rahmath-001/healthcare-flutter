import 'package:flutter/material.dart';

/// Shown while the session is being restored from the stored refresh token.
///
/// Deliberately minimal: it exists so the app never flashes the login screen at
/// a user who is in fact signed in.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: 'app-logo',
              child: Icon(Icons.health_and_safety,
                  size: 72, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}
