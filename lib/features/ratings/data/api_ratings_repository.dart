import '../../../core/network/api_client.dart';
import '../domain/rating.dart';
import 'ratings_repository.dart';

/// Ratings against the MiDoctor API.
///
/// Nothing here can publish. A submitted or edited rating enters moderation
/// server-side, because search ranks doctors on this number and an unmoderated
/// channel is a direct lever on who gets seen.
class ApiRatingsRepository implements RatingsRepository {
  ApiRatingsRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Rating>> listOwn() async {
    final json = await _api.get<List<dynamic>>('/v1/ratings');
    return json
        .map((e) => Rating.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<Rating> submit({
    required String appointmentId,
    required String doctorName,
    required int stars,
    String? comment,
  }) async {
    // `doctorName` is part of the contract but not sent: the server snapshots
    // it from the directory, so a client cannot attribute a rating elsewhere.
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/ratings',
      body: {
        'appointmentId': appointmentId,
        'stars': stars,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      },
    );
    return Rating.fromJson(json);
  }

  @override
  Future<Rating> edit(String id, {required int stars, String? comment}) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/v1/ratings/$id',
      body: {
        'stars': stars,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      },
    );
    return Rating.fromJson(json);
  }
}
