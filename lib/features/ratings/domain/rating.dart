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
  });

  final String id;
  final String appointmentId;
  final String doctorName;
  final int stars;
  final DateTime createdAt;
  final RatingStatus status;
  final String? comment;
  final DateTime? editedAt;

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
      );

  Rating copyWith({
    int? stars,
    String? comment,
    DateTime? editedAt,
    RatingStatus? status,
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
      );

  static const editWindow = Duration(days: 14);
  static const maxCommentLength = 500;

  bool get canEdit =>
      DateTime.now().difference(createdAt) < editWindow &&
      status != RatingStatus.removed;

  Duration get editWindowRemaining {
    final left = editWindow - DateTime.now().difference(createdAt);
    return left.isNegative ? Duration.zero : left;
  }
}
