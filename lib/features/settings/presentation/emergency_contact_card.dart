import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_palette.dart';
import '../../../l10n/l10n.dart';
import 'account_controller.dart';

/// The emergency contact, with a way to actually reach them.
///
/// The app has asked every patient for a next of kin since onboarding shipped,
/// stored the name and number, and **read them back nowhere**. Collecting
/// somebody's emergency contact and then having no path to it is worse than not
/// asking: it implies a capability — that in a crisis this app can reach the
/// person you named — which did not exist.
///
/// One tap dials. It does not place the call: `tel:` hands the number to the
/// dialer with it typed in, and the user presses the button. An app that
/// autodials from a card someone brushed past is a phone that rings a relative
/// at 3am for no reason.
class EmergencyContactCard extends ConsumerWidget {
  const EmergencyContactCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(patientProfileProvider).value;
    final name = profile?.emergencyContactName;
    final phone = profile?.emergencyContactPhone;

    // Nothing to show rather than an empty card. The edit-profile screen is
    // where it is added, and duplicating that prompt here would put two
    // competing calls to action on the same tab.
    if (name == null || name.trim().isEmpty) return const SizedBox.shrink();

    final tones = context.tones;
    final l10n = context.l10n;
    final canCall = phone != null && phone.trim().isNotEmpty;

    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: tones.dangerContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.emergency_share_outlined,
              size: 20, color: tones.danger),
        ),
        title: Text(name),
        subtitle: Text(
          canCall
              ? '${l10n.editProfileEmergencyContact} · $phone'
              : l10n.editProfileEmergencyContact,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: canCall
            ? IconButton(
                tooltip: l10n.emergencyCall,
                icon: Icon(Icons.call, color: tones.success),
                onPressed: () => _dial(context, phone),
              )
            : null,
      ),
    );
  }

  Future<void> _dial(BuildContext context, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.emergencyCallFailed;

    // Strips spaces and punctuation: `tel:` is tolerant of most of it, but a
    // stored "+91 98123 45678" fails on some Android dialers.
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);

    try {
      final launched = await launchUrl(uri);
      if (!launched) messenger.showSnackBar(SnackBar(content: Text(failed)));
    } catch (_) {
      // A device with no dialer — a tablet, an emulator — rather than a fault
      // the user did anything to cause.
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }
}
