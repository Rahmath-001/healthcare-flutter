import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/admin/data/fixture_operations_repository.dart';
import 'package:healthcare_mobile/core/fixtures/fixture_backend.dart';

/// The operator console's overview and access log.
///
/// The scope behaviour is the part worth testing hardest. A count that reaches
/// the client and is merely hidden by the UI has already left the building, so
/// the repository has to omit whole sections rather than zero them.
void main() {
  const fast = Duration.zero;

  setUp(FixtureBackend.resetShared);

  FixtureOperationsRepository repo(Set<String> scopes) =>
      FixtureOperationsRepository(latency: fast, scopes: scopes);

  group('the overview', () {
    test('an admin sees every queue', () async {
      final summary = await repo({'*:*'}).summary();

      expect(summary.verification, isNotNull);
      expect(summary.moderation, isNotNull);
      expect(summary.support, isNotNull);
      expect(summary.isEmpty, isFalse);
    });

    test('a support agent is not told the verification backlog', () async {
      // Not zeroed - absent. A support agent has no business knowing how many
      // doctors are awaiting verification.
      final summary = await repo({'support:ticket_read'}).summary();

      expect(summary.verification, isNull);
      expect(summary.moderation, isNull);
      expect(summary.support, isNotNull);
    });

    test('a supervisor is not told the support backlog', () async {
      final summary = await repo({'provider:review'}).summary();

      expect(summary.verification, isNotNull);
      expect(summary.support, isNull);
    });

    test('an operator with no queues gets nothing at all', () async {
      final summary = await repo({'profile:read'}).summary();
      expect(summary.isEmpty, isTrue);
    });

    test('it reports how long the oldest item has waited', () async {
      // The figure that matters more than the count: ten filed this morning is
      // a normal Tuesday, one filed three weeks ago is somebody who cannot
      // earn a living.
      final summary = await repo({'*:*'}).summary();

      if (summary.verification!.pending > 0) {
        expect(summary.verification!.oldestWaiting, isNotNull);
      } else {
        expect(summary.verification!.oldestWaiting, isNull);
      }
    });
  });

  group('the access log', () {
    test('it reads back, including refusals', () async {
      // A doctor repeatedly trying records they hold no grant for is the
      // pattern an audit log exists to surface. A log of successes only would
      // hide the one thing worth finding.
      final backend = FixtureBackend.shared;
      try {
        backend.recordsVisibleTo('d-no-grant');
      } catch (_) {
        // The denial is the point; the throw is expected.
      }

      final trail = await repo({'*:*'}).auditTrail('u-patient');
      expect(trail, isNotEmpty);
      expect(trail.any((e) => e.wasDenied), isTrue);
    });

    test('reading it is itself recorded', () async {
      // An audit log whose readers are not audited protects everybody except
      // from the people holding it.
      final r = repo({'*:*'});

      final first = await r.auditTrail('u-patient');
      final second = await r.auditTrail('u-patient');

      expect(second.length, first.length + 1,
          reason: 'the first read left an entry the second one sees');
      expect(second.first.recordTitle, 'Access log');
    });

    test('a refusal is distinguishable from a read', () async {
      final trail = await repo({'*:*'}).auditTrail('u-patient');
      for (final e in trail) {
        expect(e.wasDenied, e.action == 'denied');
      }
    });
  });
}
