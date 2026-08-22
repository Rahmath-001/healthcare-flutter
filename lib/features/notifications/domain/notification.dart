import 'package:meta/meta.dart';

/// What a notification is about.
///
/// A closed set, because each kind decides three separate things: which
/// preference toggle silences it, where tapping it goes, and — most
/// importantly — whether it may be delivered outside quiet hours. A free-text
/// "type" string would make all three decisions unenforceable.
enum NotificationKind {
  /// "Your appointment is tomorrow at 4:30 PM."
  appointmentReminder,

  /// The doctor or the clinic moved or cancelled it. Always urgent: the patient
  /// may otherwise travel to a consultation that is not happening.
  appointmentChanged,

  /// A prescription was issued from a consultation.
  prescriptionIssued,

  /// A doctor asked for access to records. Actionable, and time-boxed.
  consentRequested,

  /// An uploaded record finished scanning and can now be opened.
  recordReady,

  /// A completed consultation can be rated.
  ratingRequested,

  /// Account or verification news — provider approved, rejected, suspended.
  accountUpdate;

  static NotificationKind fromWire(String? value) => switch (value) {
        'APPOINTMENT_REMINDER' => NotificationKind.appointmentReminder,
        'APPOINTMENT_CHANGED' => NotificationKind.appointmentChanged,
        'PRESCRIPTION_ISSUED' => NotificationKind.prescriptionIssued,
        'CONSENT_REQUESTED' => NotificationKind.consentRequested,
        'RECORD_READY' => NotificationKind.recordReady,
        'RATING_REQUESTED' => NotificationKind.ratingRequested,
        // An unknown kind is shown rather than dropped. A server that starts
        // sending a new kind should reach the user with it, and "account
        // update" is the one bucket that is never wrong about urgency.
        _ => NotificationKind.accountUpdate,
      };

  String get wire => switch (this) {
        NotificationKind.appointmentReminder => 'APPOINTMENT_REMINDER',
        NotificationKind.appointmentChanged => 'APPOINTMENT_CHANGED',
        NotificationKind.prescriptionIssued => 'PRESCRIPTION_ISSUED',
        NotificationKind.consentRequested => 'CONSENT_REQUESTED',
        NotificationKind.recordReady => 'RECORD_READY',
        NotificationKind.ratingRequested => 'RATING_REQUESTED',
        NotificationKind.accountUpdate => 'ACCOUNT_UPDATE',
      };

  /// Whether this kind may wake someone at 3am.
  ///
  /// Only two things qualify: an appointment that changed under them, and an
  /// account state that stops them working. Everything else waits for morning.
  /// This is the rule quiet hours are enforced against, and it lives on the
  /// domain rather than in the sender so both the client preview and the server
  /// answer it identically.
  bool get bypassesQuietHours =>
      this == NotificationKind.appointmentChanged ||
      this == NotificationKind.accountUpdate;

  /// Whether the user is allowed to turn this off.
  ///
  /// An appointment being cancelled and an account being suspended are not
  /// marketing. Silencing them would let someone opt out of the only warning
  /// that their consultation is not happening, so the preference screen renders
  /// these as fixed rather than as a toggle set to on.
  bool get isMandatory =>
      this == NotificationKind.appointmentChanged ||
      this == NotificationKind.accountUpdate;
}

/// One notification, as the patient or provider sees it.
///
/// ## The rule that matters most here
///
/// **Neither [title] nor [body] may contain clinical content.** A notification
/// is rendered on a lock screen, mirrored to a paired watch and smart speaker,
/// and read by anyone holding the phone. "Your prescription is ready" is fine.
/// "Your Sertraline prescription is ready" is a disclosure to whoever picked
/// the phone up, with no consent record and no way to withdraw it.
///
/// The server composes these strings and is the enforcement point; the client
/// carries the same rule so that a locally-composed preview cannot diverge. The
/// detail lives behind the tap, inside the app, behind authentication and
/// `ProtectedScreen`.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.targetId,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  /// The appointment, prescription, record or consent request this is about.
  ///
  /// An id and nothing else. Resolving it into something displayable is the
  /// app's job, after the tap, on an authenticated screen.
  final String? targetId;

  bool get isRead => readAt != null;

  AppNotification copyWith({DateTime? readAt}) => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
        targetId: targetId,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        kind: NotificationKind.fromWire(json['kind'] as String?),
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        readAt: json['readAt'] == null
            ? null
            : DateTime.parse(json['readAt'] as String).toLocal(),
        targetId: json['targetId'] as String?,
      );
}

/// Quiet hours, in the user's local time.
///
/// Stored as two hours-of-day rather than instants because it is a recurring
/// window, and it deliberately supports wrapping past midnight — 22:00 to 07:00
/// is the useful case and the one a naive `start < end` comparison gets wrong.
@immutable
class QuietHours {
  const QuietHours({required this.startHour, required this.endHour});

  /// 22:00–07:00. Chosen rather than "off by default" because a health app
  /// that pings at 3am gets its notifications disabled wholesale, and then the
  /// one message that mattered never arrives either.
  static const defaults = QuietHours(startHour: 22, endHour: 7);

  final int startHour;
  final int endHour;

  bool get isDisabled => startHour == endHour;

  /// Whether [at] falls inside the window.
  ///
  /// Handles the wrap: with 22–07, both 23:00 and 02:00 are quiet.
  bool contains(DateTime at) {
    if (isDisabled) return false;
    final hour = at.hour;
    if (startHour < endHour) return hour >= startHour && hour < endHour;
    return hour >= startHour || hour < endHour;
  }

  factory QuietHours.fromJson(Map<String, dynamic> json) => QuietHours(
        startHour: (json['startHour'] as num?)?.toInt() ?? 22,
        endHour: (json['endHour'] as num?)?.toInt() ?? 7,
      );

  Map<String, dynamic> toJson() => {
        'startHour': startHour,
        'endHour': endHour,
      };
}

/// Which kinds this user wants, and when they will accept them.
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    required this.enabled,
    required this.quietHours,
  });

  /// Everything on. Mandatory kinds are not listed because they cannot be off.
  static NotificationPreferences get defaults => NotificationPreferences(
        enabled: NotificationKind.values.where((k) => !k.isMandatory).toSet(),
        quietHours: QuietHours.defaults,
      );

  final Set<NotificationKind> enabled;
  final QuietHours quietHours;

  /// Whether [kind] may be delivered at [at].
  ///
  /// The single decision function. Both the server sender and the client's
  /// preference preview call it, so "will I get this?" has exactly one answer.
  bool allows(NotificationKind kind, {required DateTime at}) {
    if (kind.isMandatory) {
      // Mandatory kinds ignore both the toggle and the window. An appointment
      // cancelled at 6am is worth waking someone for; finding out at 9am that
      // they travelled for nothing is not.
      return true;
    }
    if (!enabled.contains(kind)) return false;
    if (kind.bypassesQuietHours) return true;
    return !quietHours.contains(at);
  }

  NotificationPreferences copyWith({
    Set<NotificationKind>? enabled,
    QuietHours? quietHours,
  }) =>
      NotificationPreferences(
        enabled: enabled ?? this.enabled,
        quietHours: quietHours ?? this.quietHours,
      );

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        enabled: ((json['enabled'] as List<dynamic>?) ?? const [])
            .map((e) => NotificationKind.fromWire(e as String?))
            .toSet(),
        quietHours: QuietHours.fromJson(
          (json['quietHours'] as Map<String, dynamic>?) ?? const {},
        ),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled.map((k) => k.wire).toList(),
        'quietHours': quietHours.toJson(),
      };
}
