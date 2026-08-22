import 'package:meta/meta.dart';

/// A doctor's clinical note on a consultation.
///
/// ## Why this exists
///
/// The consent every patient agrees to before a video call says, in
/// [TelemedicineConsent.points]:
///
/// > "Chat messages, **the doctor's notes** and any prescription are kept as
/// > part of your medical record."
///
/// That was not true. There was no way for a provider to write a note at all —
/// the only record-write scope in the app was `records:write_own`, which is the
/// patient's. The exact wording of that consent is hashed into the consent
/// record server-side, so it is an attestation, and it was attesting to
/// something the product could not do. The Telemedicine Practice Guidelines
/// also require the practitioner to keep a record of the consultation.
///
/// ## Written once, amended by addendum, never edited
///
/// A clinical note is evidence of what a clinician thought at a point in time.
/// Editing one silently rewrites the past — and the times a note most needs
/// changing are exactly the times somebody has an interest in the earlier
/// version disappearing. So [body] is fixed at the moment of writing, and a
/// correction is an [addenda] entry with its own timestamp. That is how paper
/// notes work, and for the same reason.
@immutable
class ConsultationNote {
  const ConsultationNote({
    required this.id,
    required this.appointmentId,
    required this.authorName,
    required this.authorRegistrationNumber,
    required this.writtenAt,
    required this.body,
    this.addenda = const [],
  });

  final String id;
  final String appointmentId;

  /// Snapshots, like a prescription's: the note must read as it was signed even
  /// after the doctor edits their profile.
  final String authorName;
  final String authorRegistrationNumber;

  final DateTime writtenAt;

  /// The clinical note. Immutable once written.
  final String body;

  /// Corrections and additions, in the order they were made.
  final List<NoteAddendum> addenda;

  static const maxBodyLength = 4000;
  static const maxAddendumLength = 2000;

  /// The last time anything was added, for sorting and for "updated" labels.
  DateTime get lastUpdatedAt =>
      addenda.isEmpty ? writtenAt : addenda.last.writtenAt;

  bool get hasAddenda => addenda.isNotEmpty;

  factory ConsultationNote.fromJson(Map<String, dynamic> json) =>
      ConsultationNote(
        id: json['id'] as String,
        appointmentId: json['appointmentId'] as String,
        authorName: json['authorName'] as String? ?? '',
        authorRegistrationNumber:
            json['authorRegistrationNumber'] as String? ?? '',
        writtenAt: DateTime.parse(json['writtenAt'] as String).toLocal(),
        body: json['body'] as String? ?? '',
        addenda: ((json['addenda'] as List<dynamic>?) ?? const [])
            .map((e) => NoteAddendum.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  ConsultationNote copyWith({List<NoteAddendum>? addenda}) => ConsultationNote(
        id: id,
        appointmentId: appointmentId,
        authorName: authorName,
        authorRegistrationNumber: authorRegistrationNumber,
        writtenAt: writtenAt,
        body: body,
        addenda: addenda ?? this.addenda,
      );
}

/// A correction or addition to a note that has already been written.
@immutable
class NoteAddendum {
  const NoteAddendum({
    required this.body,
    required this.authorName,
    required this.writtenAt,
  });

  final String body;
  final String authorName;
  final DateTime writtenAt;

  factory NoteAddendum.fromJson(Map<String, dynamic> json) => NoteAddendum(
        body: json['body'] as String? ?? '',
        authorName: json['authorName'] as String? ?? '',
        writtenAt: DateTime.parse(json['writtenAt'] as String).toLocal(),
      );

  Map<String, dynamic> toJson() => {
        'body': body,
        'authorName': authorName,
        'writtenAt': writtenAt.toUtc().toIso8601String(),
      };
}
