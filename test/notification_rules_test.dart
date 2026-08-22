import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/features/notifications/domain/notification.dart';

/// The delivery rules, client side.
///
/// These are stated twice — here and in `functions/src/api/notifications/send.ts`
/// — because the client needs them to render an honest preference screen and
/// the server needs them because it is what actually decides. Two copies of a
/// rule drift, so both are tested against the same cases and any divergence
/// shows up as one suite passing while the other fails.
void main() {
  DateTime at(int hour) => DateTime(2026, 8, 23, hour);

  group('quiet hours', () {
    const night = QuietHours(startHour: 22, endHour: 7);

    test('wrap past midnight', () {
      // The case a naive `hour >= start && hour < end` gets exactly backwards.
      expect(night.contains(at(23)), isTrue);
      expect(night.contains(at(2)), isTrue);
      expect(night.contains(at(6)), isTrue);
    });

    test('are open during the day', () {
      expect(night.contains(at(7)), isFalse);
      expect(night.contains(at(15)), isFalse);
      expect(night.contains(at(21)), isFalse);
    });

    test('handle a same-day window', () {
      const siesta = QuietHours(startHour: 13, endHour: 16);
      expect(siesta.contains(at(14)), isTrue);
      expect(siesta.contains(at(12)), isFalse);
      expect(siesta.contains(at(16)), isFalse);
    });

    test('an equal start and end means disabled, not silent all day', () {
      const off = QuietHours(startHour: 0, endHour: 0);
      expect(off.isDisabled, isTrue);
      expect(off.contains(at(3)), isFalse);
    });
  });

  group('what the preferences allow', () {
    const prefs = NotificationPreferences(
      enabled: {
        NotificationKind.appointmentReminder,
        NotificationKind.prescriptionIssued,
      },
      quietHours: QuietHours.defaults,
    );

    test('an enabled kind during the day', () {
      expect(
        prefs.allows(NotificationKind.appointmentReminder, at: at(10)),
        isTrue,
      );
    });

    test('an ordinary kind is held during quiet hours', () {
      expect(
        prefs.allows(NotificationKind.appointmentReminder, at: at(23)),
        isFalse,
      );
    });

    test('a kind that was turned off never arrives', () {
      expect(prefs.allows(NotificationKind.recordReady, at: at(10)), isFalse);
    });

    test('an appointment change arrives at 3am anyway', () {
      expect(
        prefs.allows(NotificationKind.appointmentChanged, at: at(3)),
        isTrue,
      );
    });

    test('a mandatory kind cannot be silenced by emptying the set', () {
      // The failure this guards is a patient opting out of the only warning
      // that their consultation is not happening.
      const none = NotificationPreferences(
        enabled: {},
        quietHours: QuietHours.defaults,
      );
      expect(
        none.allows(NotificationKind.appointmentChanged, at: at(15)),
        isTrue,
      );
      expect(none.allows(NotificationKind.accountUpdate, at: at(15)), isTrue);
      // But everything else still respects it.
      expect(
        none.allows(NotificationKind.prescriptionIssued, at: at(15)),
        isFalse,
      );
    });

    test('the defaults do not list mandatory kinds', () {
      // Listing them would imply the toggle means something. The preference
      // screen renders them as fixed rows for the same reason.
      final defaults = NotificationPreferences.defaults;
      expect(defaults.enabled,
          isNot(contains(NotificationKind.appointmentChanged)));
      expect(defaults.enabled, isNot(contains(NotificationKind.accountUpdate)));
      expect(defaults.enabled, contains(NotificationKind.appointmentReminder));
    });
  });

  group('wire mapping', () {
    test('round-trips every kind', () {
      for (final kind in NotificationKind.values) {
        expect(NotificationKind.fromWire(kind.wire), kind);
      }
    });

    test('an unknown kind is shown, not dropped', () {
      // A server that starts sending a new kind should still reach the user.
      // Falling back to a kind that is mandatory means it is never silently
      // filtered on the way in.
      final unknown = NotificationKind.fromWire('SOMETHING_NEW');
      expect(unknown, NotificationKind.accountUpdate);
      expect(unknown.isMandatory, isTrue);
    });
  });

  group('mandatory and quiet-hour flags agree', () {
    test('every mandatory kind also bypasses quiet hours', () {
      // A kind that cannot be switched off but is held until 7am is a rule
      // that contradicts itself: it claims to be urgent and then waits.
      for (final kind in NotificationKind.values.where((k) => k.isMandatory)) {
        expect(
          kind.bypassesQuietHours,
          isTrue,
          reason: '${kind.wire} is mandatory but respects quiet hours',
        );
      }
    });
  });
}
