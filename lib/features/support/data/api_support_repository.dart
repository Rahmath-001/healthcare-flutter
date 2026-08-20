import '../../../core/network/api_client.dart';
import '../domain/support_ticket.dart';
import 'support_repository.dart';

/// Support tickets against the MiDoctor API.
///
/// Mobile holds `support:ticket_create` only, so there is no queue and no
/// assignment surface here — the agent side is a different client.
class ApiSupportRepository implements SupportRepository {
  ApiSupportRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<SupportTicket>> listOwn() async {
    final json = await _api.get<List<dynamic>>('/v1/support/tickets');
    return json
        .map((e) => SupportTicket.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<SupportTicket> create({
    required String subject,
    required TicketCategory category,
    required String body,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/support/tickets',
      body: {
        'subject': subject,
        'category': category.wire,
        'body': body,
      },
    );
    return SupportTicket.fromJson(json);
  }

  @override
  Future<SupportTicket> reply(String ticketId, String body) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/support/tickets/$ticketId/replies',
      body: {'body': body},
    );
    return SupportTicket.fromJson(json);
  }
}
