import '../../core/error/failure.dart';
import '../../core/fixtures/fixture_backend.dart';
import '../../core/fixtures/provider_application.dart';
import '../../core/session/user_role.dart';
import '../../features/credentials/domain/credential.dart';
import '../../features/consent/domain/consent.dart';
import '../../features/ratings/domain/rating.dart';
import '../../features/support/domain/support_ticket.dart';
import '../admin_app.dart';
import 'operations_repository.dart';

/// The operator console against the shared fixture backend.
///
/// The console had no fixture mode at all — it was wired straight to the API,
/// so it could not be opened without a deployed backend and a hand-minted admin
/// token. That made the one screen nobody can demo the one screen that gates
/// every doctor.
///
/// It reads and writes the *same* store the mobile app does, which is what
/// makes the two halves one product: a doctor who submits credentials on their
/// phone appears in this queue, approving them here changes what that doctor
/// sees, and a rating a patient leaves turns up in moderation.
class FixtureOperationsRepository implements OperationsRepository {
  FixtureOperationsRepository({
    this.latency = const Duration(milliseconds: 300),
    FixtureBackend? backend,
    Set<String> scopes = const {'*:*'},
  })  : _backend = backend ?? FixtureBackend.shared,
        _scopes = scopes;

  final Duration latency;
  final FixtureBackend _backend;

  /// What the caller may see.
  ///
  /// Held here rather than read in a widget, because the server decides this
  /// from the token and a count that reaches the client and is merely hidden
  /// has already leaked.
  final Set<String> _scopes;

  Future<void> get _wait => Future<void>.delayed(latency);

  // --- provider verification ----------------------------------------------

  @override
  Future<List<ProviderApplication>> reviewQueue() async {
    await _wait;
    // Oldest first: a queue sorted any other way is a queue where somebody
    // waits forever.
    final open = _backend
        .applications()
        .where((a) =>
            a.status == ProviderApplicationStatus.submitted ||
            a.status == ProviderApplicationStatus.underReview)
        .toList()
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));

    return open
        .map(
          (a) => ProviderApplication(
            userId: a.userId,
            providerStatus: a.status == ProviderApplicationStatus.underReview
                ? ProviderStatus.underReview
                : ProviderStatus.submitted,
            displayName: a.displayName,
            email: a.email,
            phone: a.phone,
            registrationNumber: a.registrationNumber,
            submittedAt: a.submittedAt,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<ProviderDossier> dossier(String userId) async {
    await _wait;
    final application = _backend.applicationById(userId);

    return ProviderDossier(
      userId: application.userId,
      providerStatus: switch (application.status) {
        ProviderApplicationStatus.submitted => ProviderStatus.submitted,
        ProviderApplicationStatus.underReview => ProviderStatus.underReview,
        ProviderApplicationStatus.approved => ProviderStatus.approved,
        ProviderApplicationStatus.rejected => ProviderStatus.rejected,
      },
      accountStatus: AccountStatus.active,
      mfaEnrolled: application.mfaEnrolled,
      displayName: application.displayName,
      email: application.email,
      phone: application.phone,
      registrationNumber: application.registrationNumber,
      documents: application.documents
          .map(
            (d) => ReviewDocument(
              id: d.id,
              kind: d.kind,
              status: d.status,
              // Identity comes from DigiLocker, so there is no file to open —
              // and the console has to say so rather than offer a dead button.
              hasFile: d.kind != CredentialKind.identityProof &&
                  d.status != CredentialReviewStatus.notSubmitted,
              contentType: (d.fileName ?? '').endsWith('.jpg')
                  ? 'image/jpeg'
                  : 'application/pdf',
              sizeBytes: 320 * 1024,
              uploadedAt: d.uploadedAt,
              fileName: d.fileName,
              reasonCode: d.reasonCode,
              reviewerNote: d.reviewerNote,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> claimForReview(String userId) async {
    await _wait;
    final application = _backend.applicationById(userId);
    if (application.status != ProviderApplicationStatus.submitted) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'This application is not waiting to be picked up.',
        code: 'NOT_AWAITING_REVIEW',
      );
    }
    _backend.updateApplication(
      application.copyWith(status: ProviderApplicationStatus.underReview),
    );
  }

  /// No object storage behind the fixture, so there is nothing to fetch.
  ///
  /// Refused loudly rather than returning a placeholder image: a reviewer who
  /// thinks they have read a degree certificate they have not read is worse
  /// than a reviewer who is told the viewer is unavailable.
  @override
  Future<String> documentUrl(String credentialId) async {
    await _wait;
    throw const Failure(
      kind: FailureKind.unknown,
      message: 'Document preview needs the real file store. Everything else '
          'on this screen works against sample data.',
      code: 'FIXTURE_NO_STORAGE',
    );
  }

  @override
  Future<void> decideDocument(
    String credentialId, {
    required bool accept,
    RejectionReasonCode? reasonCode,
    String? note,
  }) async {
    await _wait;

    for (final application in _backend.applications()) {
      final index =
          application.documents.indexWhere((d) => d.id == credentialId);
      if (index < 0) continue;

      final documents = [...application.documents];
      documents[index] = documents[index].copyWith(
        status: accept
            ? CredentialReviewStatus.accepted
            : CredentialReviewStatus.rejected,
        reasonCode: accept ? null : reasonCode,
        reviewerNote: note,
      );
      _backend.updateApplication(application.copyWith(documents: documents));
      return;
    }

    throw const Failure(
      kind: FailureKind.notFound,
      message: 'That document no longer exists.',
      code: 'DOCUMENT_NOT_FOUND',
    );
  }

  @override
  Future<void> approveProvider(
    String userId, {
    required Map<String, dynamic> profile,
  }) async {
    await _wait;
    final application = _backend.applicationById(userId);

    // The gate is re-derived here, not taken from the console's own view of it.
    if (!application.isApprovable) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Every document must be accepted, with a registration number '
            'and two-factor enrolled, before approval.',
        code: 'NOT_APPROVABLE',
      );
    }

    _backend.updateApplication(
      application.copyWith(status: ProviderApplicationStatus.approved),
    );
  }

  @override
  Future<void> rejectProvider(String userId, {required String reason}) async {
    await _wait;
    _backend.updateApplication(
      _backend
          .applicationById(userId)
          .copyWith(status: ProviderApplicationStatus.rejected),
    );
  }

  // --- accounts ------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> lookupUser(String userId) async {
    await _wait;

    // The one patient the fixture models, plus any provider in the queue.
    if (userId == 'u-patient') {
      final profile = _backend.profile();
      return {
        'userId': profile.userId,
        'role': 'PATIENT',
        'status': 'ACTIVE',
        'providerStatus': 'NOT_APPLICABLE',
        'displayName': profile.displayName,
        'email': profile.email,
        'phone': profile.phone,
      };
    }

    final application = _backend.applicationById(userId);
    return {
      'userId': application.userId,
      'role': 'PROVIDER',
      'status': 'ACTIVE',
      'providerStatus': application.status.wire,
      'displayName': application.displayName,
      'email': application.email,
      'phone': application.phone,
    };
  }

  /// Suspension is not modelled in the fixture store.
  ///
  /// Refused rather than silently succeeding, because a console that reports
  /// "account suspended" when nothing was suspended is the single most
  /// dangerous kind of mock.
  @override
  Future<void> suspendAccount(
    String userId, {
    required AccountStatus status,
    required String reason,
  }) async {
    await _wait;
    throw const Failure(
      kind: FailureKind.unknown,
      message: 'Suspension acts on real accounts and is disabled against '
          'sample data.',
      code: 'FIXTURE_READ_ONLY',
    );
  }

  @override
  Future<void> reactivateAccount(String userId) async {
    await _wait;
    throw const Failure(
      kind: FailureKind.unknown,
      message: 'Reactivation acts on real accounts and is disabled against '
          'sample data.',
      code: 'FIXTURE_READ_ONLY',
    );
  }

  @override
  Future<void> assignRole(String userId, UserRole role) async {
    await _wait;
    throw const Failure(
      kind: FailureKind.unknown,
      message: 'Role assignment acts on real accounts and is disabled against '
          'sample data.',
      code: 'FIXTURE_READ_ONLY',
    );
  }

  // --- ratings -------------------------------------------------------------

  @override
  Future<List<PendingRating>> pendingRatings() async {
    await _wait;
    return _backend
        .pendingRatings()
        .map(
          (r) => PendingRating(
            id: r.id,
            doctorId: r.appointmentId,
            doctorName: r.doctorName,
            stars: r.stars,
            createdAt: r.createdAt,
            comment: r.comment,
            editedAt: r.editedAt,
            providerReply: r.providerReply,
            replyStatus: r.replyStatus?.wire,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> moderateRating(String id, {required String status}) async {
    await _wait;
    _backend.moderateRating(
      id,
      switch (status) {
        'PUBLISHED' => RatingStatus.published,
        'HIDDEN' => RatingStatus.hidden,
        _ => RatingStatus.removed,
      },
    );
  }

  @override
  Future<void> moderateRatingReply(String id, {required String status}) async {
    await _wait;
    _backend.moderateRatingReply(
      id,
      switch (status) {
        'PUBLISHED' => RatingStatus.published,
        'HIDDEN' => RatingStatus.hidden,
        _ => RatingStatus.removed,
      },
    );
  }

  // --- support -------------------------------------------------------------

  @override
  Future<List<QueuedTicket>> ticketQueue({TicketStatus? status}) async {
    await _wait;
    return _backend
        .tickets()
        .where((t) => status == null || t.status == status)
        .map(
          (t) => QueuedTicket(
            id: t.id,
            reference: t.reference,
            subject: t.subject,
            category: t.category,
            status: t.status,
            updatedAt: t.updatedAt,
            messageCount: t.messages.length,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<SupportTicket> ticket(String id) async {
    await _wait;
    return _backend.ticketById(id);
  }

  @override
  Future<void> replyToTicket(String id, String body) async {
    await _wait;
    _backend.appendMessage(
      id,
      TicketMessage(
        id: 'tm-${DateTime.now().millisecondsSinceEpoch}',
        body: body,
        sentAt: DateTime.now(),
        isFromSupport: true,
        authorName: 'MiDoctor Support',
      ),
    );
  }

  @override
  Future<void> setTicketStatus(String id, TicketStatus status) async {
    await _wait;
    _backend.setTicketStatus(id, status);
  }

  // --- overview and audit ---------------------------------------------------

  @override
  Future<OperationsSummary> summary() async {
    await _wait;

    // Scoped here, not filtered in the widget. A support agent has no business
    // knowing how many doctors are awaiting verification, and a count that
    // reaches the client and is merely hidden has already leaked.
    final canReview = _scopes.canReviewProviders;
    final canReadTickets = _scopes.canReadTickets;

    final now = DateTime.now();
    Duration? since(DateTime? at) => at == null ? null : now.difference(at);

    final verification = _backend.verificationLoad();
    final moderation = _backend.moderationLoad();
    final support = _backend.supportLoad();

    return OperationsSummary(
      verification: canReview
          ? VerificationLoad(
              pending: verification.pending,
              oldestWaiting: since(verification.oldest),
            )
          : null,
      moderation: canReview
          ? ModerationLoad(
              pending: moderation.pending,
              oldestWaiting: since(moderation.oldest),
            )
          : null,
      support: canReadTickets
          ? SupportLoad(
              open: support.open,
              breachingSla: support.breaching,
              oldestWaiting: since(support.oldest),
            )
          : null,
    );
  }

  @override
  Future<List<AuditEvent>> auditTrail(String userId) async {
    await _wait;

    // Reading an access log is an access of its own, and the fixture records
    // it for the same reason the server does: an audit log whose readers are
    // not audited protects everybody except from the people holding it.
    final events = _backend.auditTrailFor(userId, operatorName: 'Operations');

    return events
        .map((e) => AuditEvent(
              id: e.id,
              actorName: e.actorName,
              actorRole: 'Provider',
              recordTitle: e.recordTitle,
              action: e.action == AccessAction.denied
                  ? 'denied'
                  : e.action == AccessAction.download
                      ? 'downloaded'
                      : 'viewed',
              at: e.at,
            ))
        .toList(growable: false);
  }
}
