import '../../../core/fixtures/fixture_backend.dart';
import '../domain/rating.dart';

abstract class RatingsRepository {
  Future<List<Rating>> listOwn();

  /// One rating per completed appointment. The server enforces uniqueness on
  /// appointment_id, so a duplicate surfaces as a conflict.
  Future<Rating> submit({
    required String appointmentId,
    required String doctorName,
    required int stars,
    String? comment,
  });

  Future<Rating> edit(String id, {required int stars, String? comment});

  /// Ratings for the signed-in provider, so they can see and answer them.
  Future<List<Rating>> listForProvider();

  /// The doctor's public answer to a rating.
  ///
  /// Enters moderation like the rating itself. A reply is public text written
  /// by the party with the most incentive to argue, and one naming a patient's
  /// condition would be a disclosure published past the queue that exists to
  /// catch it.
  Future<Rating> reply(String id, {required String reply});
}

class FixtureRatingsRepository implements RatingsRepository {
  FixtureRatingsRepository({
    this.latency = const Duration(milliseconds: 300),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  @override
  Future<List<Rating>> listOwn() async {
    await Future<void>.delayed(latency);
    return _backend.ratings();
  }

  @override
  Future<Rating> submit({
    required String appointmentId,
    required String doctorName,
    required int stars,
    String? comment,
  }) async {
    await Future<void>.delayed(latency);

    // Never published on creation, whatever the content: search ranks doctors
    // on this number, so the moderation queue is the point.
    return _backend.addRating(
      Rating(
        id: 'rt-${DateTime.now().millisecondsSinceEpoch}',
        appointmentId: appointmentId,
        doctorName: doctorName,
        stars: stars,
        createdAt: DateTime.now(),
        status: RatingStatus.pendingModeration,
        comment: comment,
      ),
    );
  }

  @override
  Future<Rating> edit(String id, {required int stars, String? comment}) async {
    await Future<void>.delayed(latency);
    return _backend.editRating(id, stars: stars, comment: comment);
  }

  /// The fixture has one doctor persona, so this is the same set seen from the
  /// other side — the useful shape for exercising the provider screen without
  /// inventing a second practice's reviews.
  @override
  Future<List<Rating>> listForProvider() async {
    await Future<void>.delayed(latency);
    return _backend.ratings();
  }

  @override
  Future<Rating> reply(String id, {required String reply}) async {
    await Future<void>.delayed(latency);
    return _backend.replyToRating(id, reply: reply);
  }
}
