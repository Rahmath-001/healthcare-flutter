import 'package:flutter/foundation.dart';

/// The outcome of an erasure request.
///
/// Erasure is not a delete, and the model says so out loud. Consent grants,
/// sessions and upcoming appointments go immediately; consultation notes and
/// prescriptions are medical records with a statutory retention period, so they
/// are held until [clinicalRetentionUntil] and destroyed then.
///
/// Carrying the date rather than hiding it is deliberate: the app tells the
/// patient exactly what survives and for how long, which is what the DPDP Act
/// asks of a notice and what a vague "your data has been deleted" would not be.
@immutable
class AccountDeletion {
  const AccountDeletion({required this.clinicalRetentionUntil});

  final DateTime clinicalRetentionUntil;

  factory AccountDeletion.fromJson(Map<String, dynamic> json) {
    return AccountDeletion(
      clinicalRetentionUntil:
          DateTime.parse(json['clinicalRetentionUntil'] as String).toLocal(),
    );
  }
}
