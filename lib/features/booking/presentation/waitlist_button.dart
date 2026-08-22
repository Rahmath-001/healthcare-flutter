import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/haptics.dart';
import '../../providers_search/domain/doctor.dart';
import '../domain/waitlist.dart';

final waitlistProvider = FutureProvider<List<WaitlistEntry>>((ref) async {
  return ref.watch(bookingRepositoryProvider).waitlist();
});

/// "Tell me when a slot opens", for a doctor with nothing free.
///
/// Shown where the disappointment happens — on the empty slot grid — rather
/// than filed away in a menu. Someone who has just found no free times is the
/// only person who wants this, and they want it now.
class WaitlistButton extends ConsumerStatefulWidget {
  const WaitlistButton({
    super.key,
    required this.doctor,
    required this.mode,
    this.preferredDate,
  });

  final Doctor doctor;
  final ConsultationMode mode;

  /// The day they were looking at, or null for "any day".
  final DateTime? preferredDate;

  @override
  ConsumerState<WaitlistButton> createState() => _WaitlistButtonState();
}

class _WaitlistButtonState extends ConsumerState<WaitlistButton> {
  bool _busy = false;

  WaitlistEntry? _existing(List<WaitlistEntry> entries) {
    for (final e in entries) {
      if (!e.isActive) continue;
      if (e.doctorId != widget.doctor.id) continue;
      if (e.mode != widget.mode) continue;
      final a = e.preferredDate;
      final b = widget.preferredDate;
      final sameDay = (a == null && b == null) ||
          (a != null &&
              b != null &&
              a.year == b.year &&
              a.month == b.month &&
              a.day == b.day);
      if (sameDay) return e;
    }
    return null;
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(waitlistProvider);
      Haptics.success();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } on Failure catch (f) {
      Haptics.warning();
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final entries =
        ref.watch(waitlistProvider).value ?? const <WaitlistEntry>[];
    final existing = _existing(entries);

    if (existing != null) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: Insets.sm),
              Flexible(child: Text(l10n.waitlistOn)),
            ],
          ),
          const SizedBox(height: Insets.xs),
          Text(
            existing.preferredDate == null
                ? l10n.waitlistAnyDay
                : l10n.waitlistForDay(Fmt.date(existing.preferredDate!)),
            style: theme.textTheme.labelSmall,
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(
                      () => ref
                          .read(bookingRepositoryProvider)
                          .leaveWaitlist(existing.id),
                      l10n.waitlistLeave,
                    ),
            child: Text(l10n.waitlistLeave),
          ),
        ],
      );
    }

    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _run(
                    () => ref.read(bookingRepositoryProvider).joinWaitlist(
                          doctor: widget.doctor,
                          mode: widget.mode,
                          preferredDate: widget.preferredDate,
                        ),
                    l10n.waitlistJoined,
                  ),
          icon: const Icon(Icons.notifications_active_outlined, size: 18),
          label: Text(l10n.waitlistJoin),
        ),
        const SizedBox(height: Insets.sm),
        // Said before they join, not after. Someone who believes a slot is
        // being held for them will not hurry, and will be angry when it has
        // gone.
        Text(
          l10n.waitlistNote,
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
