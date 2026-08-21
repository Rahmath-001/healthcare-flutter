import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/service_providers.dart';
import '../core/theme/app_palette.dart';
import '../core/theme/app_tokens.dart';
import '../l10n/l10n.dart';

/// The strip that appears above the whole app when the device loses network.
///
/// Warning-toned, not red. Being offline is a condition, not a failure: the app
/// has done nothing wrong and neither has the user, and spending the error
/// colour on it leaves nothing louder for the states that are actually broken.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Assume online until proven otherwise, so the banner never flashes during
    // the first frame while connectivity is still being determined.
    final online = ref.watch(isOnlineProvider).value ?? true;
    final tones = context.tones;
    final theme = Theme.of(context);

    return AnimatedSize(
      duration: Motion.of(context, Motion.normal),
      curve: online ? Motion.exit : Motion.enter,
      alignment: Alignment.bottomCenter,
      child: online
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                color: tones.warningContainer,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Insets.lg,
                      vertical: Insets.sm + 2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wifi_off,
                          color: tones.onWarningContainer,
                          size: 18,
                        ),
                        const SizedBox(width: Insets.sm),
                        Flexible(
                          child: Text(
                            context.l10n.offline,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: tones.onWarningContainer,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
