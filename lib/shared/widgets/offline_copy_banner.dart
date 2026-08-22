import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/clinical_cache.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../l10n/l10n.dart';
import '../formatters.dart';

/// Says, above a list, that it is a stored copy rather than a live one.
///
/// The whole justification for caching clinical data rests on this widget
/// existing. An app that silently renders last night's appointment list as
/// though it were today's has not added offline support — it has added a wrong
/// answer delivered confidently, which for a list somebody plans their day
/// around is worse than an error message.
///
/// Warning-toned rather than error-toned: nothing has failed. The data is real,
/// it is simply older than the user might assume, and that distinction is what
/// the colour is carrying.
class OfflineCopyBanner extends ConsumerWidget {
  const OfflineCopyBanner({super.key, required this.cacheKey});

  final String cacheKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cachedAt = ref.watch(offlineCacheStatusProvider)[cacheKey];
    if (cachedAt == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tones = context.tones;
    final l10n = context.l10n;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, 0),
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: tones.warningContainer,
        borderRadius: Radii.smAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 18, color: tones.onWarningContainer),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.offlineCopy(Fmt.relative(cachedAt)),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: tones.onWarningContainer),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.offlineCopyBody,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: tones.onWarningContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
