import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/providers.dart';
import 'core/security/inactivity_timeout.dart';
import 'features/notifications/presentation/push_coordinator.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'widgets/offline_banner.dart';

class MiDoctorApp extends ConsumerWidget {
  const MiDoctorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'MiDoctor',
      debugShowCheckedModeBanner: false,
      routerConfig: router,

      // Hindi ships partially on purpose: keys it does not define fall back to
      // English. See lib/l10n/README.md — the consent and privacy strings are
      // legal copy and must be professionally translated before Hindi is
      // advertised as supported.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Wrapped above the router so the inactivity clock spans every route
      // rather than being re-armed by navigation. Inside the `builder`, so it
      // still sits below `ScaffoldMessenger` and can explain itself on the way
      // out.
      builder: (context, child) => InactivityTimeout(
        child: PushCoordinator(
          child: Column(
            children: [
              const _FixtureFallbackBanner(),
              const OfflineBanner(),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Makes the automatic outage fallback explicit. Sample records must never be
/// visually indistinguishable from a patient's own live records.
class _FixtureFallbackBanner extends ConsumerWidget {
  const _FixtureFallbackBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(backendModeProvider) != BackendMode.fallbackFixtures) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: ColoredBox(
        color: scheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.science_outlined, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Live services are unavailable. Showing sample data.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
