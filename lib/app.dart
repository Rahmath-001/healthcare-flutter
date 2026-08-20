import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
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
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0E8388),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF0E8388),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      builder: (context, child) => Column(
        children: [
          const OfflineBanner(),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}
