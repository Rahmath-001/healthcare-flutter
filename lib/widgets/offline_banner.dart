import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/service_providers.dart';

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Assume online until proven otherwise, so the banner never flashes during
    // the first frame while connectivity is still being determined.
    final online = ref.watch(isOnlineProvider).value ?? true;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      offset: online ? const Offset(0, -1) : Offset.zero,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: online ? 0 : null,
        color: Colors.red.shade700,
        width: double.infinity,
        child: const SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'You are offline',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
