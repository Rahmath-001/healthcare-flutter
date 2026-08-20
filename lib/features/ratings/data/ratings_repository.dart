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
}
