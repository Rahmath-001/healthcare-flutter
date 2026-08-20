/// The telemedicine consent gate, as a single source of truth.
///
/// This exists because the consent *record* has to prove which words the
/// patient agreed to, not merely that they tapped a checkbox. The server stores
/// a SHA-256 of [text] together with [version]; if the copy on screen and the
/// copy that gets hashed can drift apart, the record proves nothing.
///
/// So the screen renders [points] and nothing else, and [text] is assembled
/// from the same list. Editing the wording is therefore a deliberate act with a
/// version bump, rather than a typo fix that silently invalidates every consent
/// record taken before it.
///
/// Required by the MoHFW Telemedicine Practice Guidelines. This copy is
/// **LEGAL COPY**: it must not be machine-translated, and a translated locale
/// needs its own reviewed version string. See `lib/l10n/README.md`.
abstract final class TelemedicineConsent {
  /// Bump on **any** change to [points] or [agreement].
  ///
  /// Dated rather than sequential so a stored hash can be traced to a release
  /// without a lookup table.
  static const version = '2026-08-20.en.1';

  static const locale = 'en';

  static const points = <String>[
    'This consultation is not recorded. No video or audio is saved.',
    'Chat messages, the doctor’s notes and any prescription are kept as part '
        'of your medical record.',
    'Some medicines cannot be prescribed remotely. Your doctor may ask you to '
        'visit in person.',
    'Telemedicine is not for emergencies. If this is urgent, go to the nearest '
        'hospital.',
  ];

  static const agreement =
      'I consent to this teleconsultation and confirm the information I give '
      'will be accurate.';

  /// The canonical string that gets hashed.
  ///
  /// Newline-joined and never reordered — the hash is over bytes, so a cosmetic
  /// change to the separator would invalidate every prior record just as surely
  /// as a change to the words.
  static String get text => [...points, agreement].join('\n');
}
