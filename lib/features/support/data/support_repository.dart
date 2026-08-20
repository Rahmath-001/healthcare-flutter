import '../../../core/fixtures/fixture_backend.dart';
import '../domain/support_ticket.dart';

abstract class SupportRepository {
  /// The caller's own tickets. Mobile holds `support:ticket_create` only, so
  /// there is deliberately no queue or assignment surface here.
  Future<List<SupportTicket>> listOwn();

  Future<SupportTicket> create({
    required String subject,
    required TicketCategory category,
    required String body,
  });

  Future<SupportTicket> reply(String ticketId, String body);
}

class FixtureSupportRepository implements SupportRepository {
  FixtureSupportRepository({
    this.latency = const Duration(milliseconds: 320),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  @override
  Future<List<SupportTicket>> listOwn() async {
    await Future<void>.delayed(latency);
    return _backend.tickets();
  }

  @override
  Future<SupportTicket> create({
    required String subject,
    required TicketCategory category,
    required String body,
  }) async {
    await Future<void>.delayed(latency);
    final now = DateTime.now();
    final stamp = now.millisecondsSinceEpoch;

    return _backend.addTicket(
      SupportTicket(
        id: 't-$stamp',
        reference: 'SUP-${stamp.toString().substring(7)}',
        subject: subject,
        category: category,
        status: TicketStatus.open,
        createdAt: now,
        updatedAt: now,
        messages: [
          TicketMessage(
            id: 'tm-$stamp',
            body: body,
            sentAt: now,
            isFromSupport: false,
            authorName: 'You',
          ),
        ],
      ),
    );
  }

  @override
  Future<SupportTicket> reply(String ticketId, String body) async {
    await Future<void>.delayed(latency);
    return _backend.appendMessage(
      ticketId,
      TicketMessage(
        id: 'tm-${DateTime.now().millisecondsSinceEpoch}',
        body: body,
        sentAt: DateTime.now(),
        isFromSupport: false,
        authorName: 'You',
      ),
    );
  }
}
