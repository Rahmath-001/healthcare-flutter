import 'package:flutter/foundation.dart';

/// Moderation state.
///
/// Ratings are moderated before publication. Search filters by rating, so an
/// unmoderated channel would be a direct lever on which doctors get seen.
enum RatingStatus {
  pendingModeration('PENDING_MODERATION'),
  published('PUBLISHED'),
  hidden('HIDDEN'),
  removed('REMOVED');

  const RatingStatus(this.wire);

  final String wire;

  /// An unknown state is treated as awaiting review, never as published — the
  /// safe default for something search ranks on.
  static RatingStatus fromWire(String? wire) => RatingStatus.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => RatingStatus.pendingModeration,
      );

  String get label => switch (this) {
        RatingStatus.pendingModeration => 'Awaiting review',
        RatingStatus.published => 'Published',
        RatingStatus.hidden => 'Hidden',
        RatingStatus.removed => 'Removed',
      };
}

/// A patient's rating of one completed appointment.
///
/// The spec lets search filter by rating but never says where a rating comes
/// from. These are the rules being introduced to close that gap: one rating per
/// completed appointment, editable for 14 days, moderated before it is shown.
@immutable
class Rating {
  const Rating({
    required this.id,
    required this.appointmentId,
    required this.doctorName,
    required this.stars,
    required this.createdAt,
    required this.status,
    this.comment,
    this.editedAt,
    this.providerReply,
    this.providerRepliedAt,
    this.replyStatus,
  });

  final String id;
  final String appointmentId;
  final String doctorName;
  final int stars;
  final DateTime createdAt;
  final RatingStatus status;
  final String? comment;
  final DateTime? editedAt;

  /// The doctor's public answer, if they have written one.
  ///
  /// Doctors could not respond at all before this. A rating is the one thing
  /// about a provider that search ranks on and that the provider cannot touch —
  /// an unfair one stood unanswered forever, and the only alternative was
  /// asking an operator to hide a rating that was merely unflattering.
  final String? providerReply;
  final DateTime? providerRepliedAt;

  /// A reply is public, so it is moderated on the same terms as the rating.
  ///
  /// Null when there is no reply. Never assume published: a reply naming a
  /// patient's condition would otherwise be a disclosure the moderation queue
  /// existed to prevent, published by the person with the most incentive to
  /// argue.
  final RatingStatus? replyStatus;

  bool get hasReply =>
      providerReply != null && providerReply!.trim().isNotEmpty;

  /// A reply is visible to patients only once it clears moderation.
  bool get replyIsVisible => hasReply && replyStatus == RatingStatus.published;

  /// One reply per rating, and only to something the public can see.
  ///
  /// Replying to a hidden or removed rating would surface, in the reply, the
  /// substance of a rating a moderator took down.
  bool get canReply =>
      !hasReply &&
      (status == RatingStatus.published ||
          status == RatingStatus.pendingModeration);

  factory Rating.fromJson(Map<String, dynamic> json) => Rating(
        id: json['id'] as String,
        appointmentId: json['appointmentId'] as String,
        doctorName: json['doctorName'] as String,
        stars: (json['stars'] as num).toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        status: RatingStatus.fromWire(json['status'] as String?),
        comment: json['comment'] as String?,
        editedAt: json['editedAt'] == null
            ? null
            : DateTime.parse(json['editedAt'] as String).toLocal(),
        providerReply: json['providerReply'] as String?,
        providerRepliedAt: json['providerRepliedAt'] == null
            ? null
            : DateTime.parse(json['providerRepliedAt'] as String).toLocal(),
        replyStatus: json['replyStatus'] == null
            ? null
            : RatingStatus.fromWire(json['replyStatus'] as String?),
      );

  Rating copyWith({
    int? stars,
    String? comment,
    DateTime? editedAt,
    RatingStatus? status,
    String? providerReply,
    DateTime? providerRepliedAt,
    RatingStatus? replyStatus,
  }) =>
      Rating(
        id: id,
        appointmentId: appointmentId,
        doctorName: doctorName,
        stars: stars ?? this.stars,
        createdAt: createdAt,
        status: status ?? this.status,
        comment: comment ?? this.comment,
        editedAt: editedAt ?? this.editedAt,
        providerReply: providerReply ?? this.providerReply,
        providerRepliedAt: providerRepliedAt ?? this.providerRepliedAt,
        replyStatus: replyStatus ?? this.replyStatus,
      );

  static const editWindow = Duration(days: 14);
  static const maxCommentLength = 500;

  /// Shorter than a rating on purpose. A reply is a right of response, not a
  /// second review — and a doctor with 500 characters and a grievance will use
  /// them to relitigate a consultation in public.
  static const maxReplyLength = 300;

  bool get canEdit =>
      DateTime.now().difference(createdAt) < editWindow &&
      status != RatingStatus.removed;

  Duration get editWindowRemaining {
    final left = editWindow - DateTime.now().difference(createdAt);
    return left.isNegative ? Duration.zero : left;
  }
}
