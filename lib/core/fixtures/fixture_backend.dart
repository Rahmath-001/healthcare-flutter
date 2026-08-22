import 'dart:async';
import 'dart:math';

import '../../features/appointments/domain/appointment.dart';
import '../../features/availability/domain/availability.dart';
import '../../features/booking/domain/waitlist.dart';
import '../../features/consent/domain/consent.dart';
import '../../features/consultation/domain/consultation_note.dart';
import '../../features/medications/domain/dose_mark.dart';
import '../../features/medications/domain/medication_schedule.dart';
import '../../features/notifications/domain/notification.dart';
import '../../features/credentials/domain/credential.dart';
import '../../features/prescriptions/data/prescription_repository.dart';
import '../../features/prescriptions/domain/prescription.dart';
import '../../features/prescriptions/domain/refill_request.dart';
import '../../features/providers_search/data/doctor_fixtures.dart';
import '../../features/providers_search/domain/doctor.dart';
import '../../features/ratings/domain/rating.dart';
import '../../features/records/domain/medical_record.dart';
import '../../features/settings/domain/patient_profile.dart';
import '../../features/support/domain/support_ticket.dart';
import '../error/failure.dart';
import 'fixture_seed.dart';
import 'provider_application.dart';

/// One in-memory backend behind every fixture repository.
///
/// The fixtures used to be independent: booking an appointment returned an
/// `Appointment` that the appointments list had never heard of, an uploaded
/// record stayed "checking…" forever because nothing ever finished the scan,
/// and a prescription written by a doctor never reached the patient who was
/// prescribed it. Each screen demoed correctly and the product did not work.
///
/// This is the thing that makes it work: a single store with the same
/// cross-feature consequences the server has. Book and it appears in your
/// appointments; complete a consultation and you can rate it; grant consent and
/// the doctor's patient list changes; submit credentials and an application
/// shows up in the operator console's queue.
///
/// It is deliberately *not* a mock in the test-double sense. It enforces the
/// same rules — slot exclusivity, consent expiry, the 14-day rating window, the
/// MoHFW drug lists, the verification gate — because a fixture that accepts
/// what the server rejects teaches the UI the wrong lessons.
class FixtureBackend {
  FixtureBackend._();

  /// The instance the app uses.
  ///
  /// Shared rather than per-repository, which is the entire point: two
  /// repositories holding separate copies of "the appointments" is how the
  /// old fixtures drifted.
  static FixtureBackend shared = FixtureBackend._().._seed();

  /// Fresh state, for tests that must not see each other's writes.
  static FixtureBackend fresh() => FixtureBackend._().._seed();

  /// Restores the shared instance to its seeded state.
  static void resetShared() => shared = fresh();

  final _random = Random();

  // --- collections ---------------------------------------------------------

  final List<Appointment> _appointments = [];
  final List<MedicalRecord> _records = [];
  final List<Prescription> _prescriptions = [];
  final List<RecordAccessGrant> _grants = [];
  final List<RecordAccessRequest> _requests = [];
  final List<RecordAccessEvent> _accessLog = [];
  final List<Rating> _ratings = [];
  final List<SupportTicket> _tickets = [];
  final List<AvailabilityRule> _rules = [];
  final List<AvailabilityException> _exceptions = [];
  final List<ProviderApplicationRecord> _applications = [];
  final List<AppNotification> _notifications = [];
  final List<RefillRequest> _refillRequests = [];
  final List<WaitlistEntry> _waitlist = [];
  final List<ConsultationNote> _notes = [];

  /// The dose log, keyed by the deterministic dose id.
  ///
  /// A map rather than a list so that marking the same dose twice is one
  /// entry, matching the server's PUT-on-a-derived-id contract. A list would
  /// let a double tap log two tablets.
  final Map<String, DoseMark> _doseMarks = {};
  NotificationPreferences _notificationPreferences =
      NotificationPreferences.defaults;

  /// The last device token registered. Sample data has no push service behind
  /// it, so this exists to prove the registration call happened rather than to
  /// deliver anything.
  String? _deviceToken;

  /// Slot ids that are booked or held, mapped to when a hold lapses.
  ///
  /// The same deterministic id the server uses (`<doctorId>__<startMillis>`),
  /// so the fixture reproduces the real no-double-booking behaviour rather than
  /// approximating it.
  final Map<String, DateTime?> _slotLocks = {};

  late PatientProfile _profile;
  late VerificationChecklist _checklist;

  /// Consultations that have captured telemedicine consent.
  final Set<String> _consentCaptured = {};

  /// Pending scans, so an upload can finish asynchronously the way a real one
  /// does rather than being instantly readable.
  final Map<String, Timer> _scans = {};

  // --- seeding -------------------------------------------------------------

  void _seed() {
    _profile = FixtureSeed.profile();
    _checklist = FixtureSeed.checklist();
    _appointments.addAll(FixtureSeed.appointments());
    _records.addAll(FixtureSeed.records());
    _prescriptions.addAll(FixtureSeed.prescriptions());
    _grants.addAll(FixtureSeed.grants());
    _requests.addAll(FixtureSeed.requests());
    _accessLog.addAll(FixtureSeed.accessLog());
    _ratings.addAll(FixtureSeed.ratings());
    _tickets.addAll(FixtureSeed.tickets());
    _rules.addAll(FixtureSeed.availabilityRules());
    _applications.addAll(FixtureSeed.applications());
    _notifications.addAll(FixtureSeed.notifications());

    // Every seeded appointment already owns its slot.
    for (final a in _appointments) {
      if (a.status.isUpcoming) _slotLocks[slotId(a.doctor.id, a.start)] = null;
    }
  }

  /// Cancels outstanding timers. Called when the app's provider scope disposes.
  void dispose() {
    for (final timer in _scans.values) {
      timer.cancel();
    }
    _scans.clear();
  }

  // --- doctors -------------------------------------------------------------

  List<Doctor> get doctors => List.unmodifiable(DoctorFixtures.all);

  Doctor doctorById(String id) => DoctorFixtures.byId(id);

  // --- slots and booking ---------------------------------------------------

  static String slotId(String doctorId, DateTime start) =>
      '${doctorId}__${start.millisecondsSinceEpoch}';

  bool isSlotTaken(String id) {
    if (!_slotLocks.containsKey(id)) return false;
    final holdExpiry = _slotLocks[id];
    // A booking has no expiry; an abandoned hold releases itself, exactly as
    // the server treats a lapsed `holdExpiresAt`.
    if (holdExpiry == null) return true;
    if (holdExpiry.isAfter(DateTime.now())) return true;
    _slotLocks.remove(id);
    return false;
  }

  void holdSlot(String id, Duration duration) {
    if (isSlotTaken(id)) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'Someone is booking this slot right now.',
        code: 'SLOT_TAKEN',
      );
    }
    _slotLocks[id] = DateTime.now().add(duration);
  }

  void releaseSlot(String id) {
    if (_slotLocks[id] != null) _slotLocks.remove(id);
  }

  /// Books a slot and files the appointment where the patient will look for it.
  Appointment book({
    required Doctor doctor,
    required DateTime start,
    required DateTime end,
    required ConsultationMode mode,
    required String patientName,
    String? reasonForVisit,
  }) {
    final id = slotId(doctor.id, start);
    final holdExpiry = _slotLocks[id];
    final heldByUs = holdExpiry != null && holdExpiry.isAfter(DateTime.now());

    if (!heldByUs && isSlotTaken(id)) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'That time was just booked by someone else.',
        code: 'SLOT_TAKEN',
      );
    }

    // null expiry = booked, not merely held.
    _slotLocks[id] = null;

    final appointmentId = 'a-${_nextId()}';
    final appointment = Appointment(
      id: appointmentId,
      referenceCode: _reference(),
      doctor: doctor,
      patientName: patientName,
      start: start,
      end: end,
      mode: mode,
      status: AppointmentStatus.confirmed,
      paymentStatus: PaymentStatus.notRequired,
      feeInr: doctor.feeFor(mode),
      reasonForVisit: reasonForVisit,
      consultationId: mode == ConsultationMode.inPerson ? null : appointmentId,
    );

    _appointments.insert(0, appointment);

    // The reminder the scheduled sweep would send. Filed at booking time in
    // the fixture because there is no scheduler here — the consequence a
    // reader needs to see is "booking produces a reminder", not "a cron ran".
    notify(
      kind: NotificationKind.appointmentReminder,
      title: 'Appointment confirmed',
      body: '${doctor.name} · ${_shortWhen(start)}',
      targetId: appointmentId,
    );

    return appointment;
  }

  /// A time, with no clinical detail attached. Used for notification bodies.
  static String _shortWhen(DateTime at) {
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final m = at.minute.toString().padLeft(2, '0');
    return '${at.day}/${at.month} at $h:$m ${at.hour < 12 ? 'AM' : 'PM'}';
  }

  // --- appointments --------------------------------------------------------

  List<Appointment> appointments() {
    final sorted = [..._appointments]
      ..sort((a, b) => b.start.compareTo(a.start));
    return List.unmodifiable(sorted);
  }

  Appointment appointmentById(String id) => _appointments.firstWhere(
        (a) => a.id == id,
        orElse: () => throw const Failure(
          kind: FailureKind.notFound,
          message: 'That appointment no longer exists.',
          code: 'APPOINTMENT_NOT_FOUND',
        ),
      );

  Appointment cancelAppointment(String id, {String? reason}) {
    final existing = appointmentById(id);
    if (!existing.canCancel) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'This appointment can no longer be cancelled.',
        code: 'CANCELLATION_WINDOW_CLOSED',
      );
    }

    final updated = existing.copyWith(
      status: AppointmentStatus.cancelledByPatient,
      cancellationReason: reason,
    );
    _replaceAppointment(updated);
    // The slot goes back into the pool, which is what makes a cancellation
    // useful to the next patient rather than merely to this one.
    _slotLocks.remove(slotId(existing.doctor.id, existing.start));

    // The slot is back in the pool, so anybody waiting for it should hear.
    // This is the entire point of a cancellation being useful to someone other
    // than the person cancelling.
    announceFreeSlot(
      doctorId: existing.doctor.id,
      start: existing.start,
      mode: existing.mode,
    );

    notify(
      kind: NotificationKind.appointmentChanged,
      title: 'Appointment cancelled',
      body: '${existing.doctor.name} · ${_shortWhen(existing.start)}',
      targetId: id,
    );

    return updated;
  }

  /// Moves an appointment to a different slot.
  ///
  /// Order matters and is the whole difficulty: the new slot is taken **first**,
  /// and the old one is only released once that has succeeded. Doing it the
  /// other way round means a patient who loses the race to the new time has
  /// also lost the appointment they already had — the worst possible outcome
  /// of trying to move one. The server does the same thing inside a single
  /// transaction; here it is ordering, because there is nothing to race with.
  Appointment rescheduleAppointment(
    String id, {
    required DateTime start,
    required DateTime end,
  }) {
    final existing = appointmentById(id);

    if (!existing.canReschedule) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'This appointment can no longer be moved.',
        code: 'RESCHEDULE_WINDOW_CLOSED',
      );
    }

    final newId = slotId(existing.doctor.id, start);
    final oldId = slotId(existing.doctor.id, existing.start);

    if (newId == oldId) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'That is the time this appointment is already booked for.',
        code: 'SAME_SLOT',
      );
    }

    final holdExpiry = _slotLocks[newId];
    final heldByUs = holdExpiry != null && holdExpiry.isAfter(DateTime.now());
    if (!heldByUs && isSlotTaken(newId)) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'That time was just booked by someone else.',
        code: 'SLOT_TAKEN',
      );
    }

    _slotLocks[newId] = null;
    _slotLocks.remove(oldId);

    // Moving away frees the old time just as surely as cancelling does.
    announceFreeSlot(
      doctorId: existing.doctor.id,
      start: existing.start,
      mode: existing.mode,
    );

    final updated = existing.copyWith(
      start: start,
      end: end,
      // Deliberately CONFIRMED rather than RESCHEDULED. `RESCHEDULED` is the
      // status of the appointment that was *left behind* — a terminal, past
      // state. This one is a live booking at a new time, and marking it
      // otherwise would drop it out of the upcoming list.
      status: AppointmentStatus.confirmed,
    );
    _replaceAppointment(updated);

    // Mandatory kind: a patient who is not told their appointment moved will
    // travel to the old time.
    notify(
      kind: NotificationKind.appointmentChanged,
      title: 'Appointment moved',
      body: '${existing.doctor.name} · now ${_shortWhen(start)}',
      targetId: id,
    );

    return updated;
  }

  Appointment checkIn(String id) {
    final updated =
        appointmentById(id).copyWith(status: AppointmentStatus.checkedIn);
    _replaceAppointment(updated);
    return updated;
  }

  void _replaceAppointment(Appointment updated) {
    final index = _appointments.indexWhere((a) => a.id == updated.id);
    if (index >= 0) _appointments[index] = updated;
  }

  // --- records -------------------------------------------------------------

  List<MedicalRecord> records() {
    final sorted = [..._records]
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return List.unmodifiable(sorted);
  }

  /// Records a provider may read, resolved against a live grant.
  ///
  /// The intersection is computed here rather than returning everything,
  /// because the whole point of the consent model is that a provider's view is
  /// narrower than the patient's.
  List<MedicalRecord> recordsVisibleTo(String providerId) {
    final grant = activeGrantFor(providerId);
    if (grant == null) {
      _accessLog.insert(
        0,
        RecordAccessEvent(
          id: 'ev-${_nextId()}',
          actorName: _providerName(providerId),
          recordTitle: 'All records',
          action: AccessAction.denied,
          at: DateTime.now(),
        ),
      );
      throw const Failure(
        kind: FailureKind.forbidden,
        message: 'You do not have access to these records.',
        code: 'NO_CONSENT',
      );
    }

    final visible = _records
        .where((r) => r.isReadable && _grantCovers(grant, r))
        .toList(growable: false);

    _accessLog.insert(
      0,
      RecordAccessEvent(
        id: 'ev-${_nextId()}',
        actorName: grant.providerName,
        recordTitle: '${visible.length} record(s)',
        action: AccessAction.viewMetadata,
        purpose: grant.purpose,
        at: DateTime.now(),
      ),
    );
    _noteGrantUse(grant.id);

    return List.unmodifiable(visible);
  }

  bool _grantCovers(RecordAccessGrant grant, MedicalRecord record) =>
      switch (grant.scopeKind) {
        ConsentScopeKind.allRecords => true,
        ConsentScopeKind.specificRecords => grant.recordIds.contains(record.id),
        ConsentScopeKind.recordTypes =>
          grant.recordTypeLabels.contains(record.type.label),
      };

  /// Adds a record and schedules the scan that makes it readable.
  ///
  /// The delay is the honest part: on the real system an upload lands in
  /// quarantine and a trigger promotes it, so a record genuinely is not
  /// readable for a moment. A fixture that returned `clean` immediately would
  /// hide the one state the UI most needs to handle.
  MedicalRecord addRecord({
    required String title,
    required RecordType type,
    required DateTime recordedAt,
    required String fileName,
    required int sizeBytes,
    required String contentType,
    String? notes,
    Duration scanDuration = const Duration(seconds: 3),
  }) {
    if (sizeBytes > 25 * 1024 * 1024) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Files must be smaller than 25 MB.',
        code: 'FILE_TOO_LARGE',
      );
    }

    final record = MedicalRecord(
      id: 'r-${_nextId()}',
      title: title,
      type: type,
      source: RecordSource.patient,
      recordedAt: recordedAt,
      uploadedAt: DateTime.now(),
      scanStatus: ScanStatus.pending,
      sizeBytes: sizeBytes,
      contentType: contentType,
      notes: notes,
    );

    _records.insert(0, record);
    _scheduleScan(record.id, scanDuration);
    return record;
  }

  void _scheduleScan(String recordId, Duration after) {
    if (after == Duration.zero) {
      _completeScan(recordId);
      return;
    }
    _scans[recordId] = Timer(after, () {
      _scans.remove(recordId);
      _completeScan(recordId);
    });
  }

  void _completeScan(String recordId) {
    final index = _records.indexWhere((r) => r.id == recordId);
    if (index < 0) return;
    _records[index] = _records[index].copyWith(scanStatus: ScanStatus.clean);

    // The record title is the patient's own words and can name a condition, so
    // it stays out of the body.
    notify(
      kind: NotificationKind.recordReady,
      title: 'Record ready',
      body: 'Your upload finished checking and can now be opened.',
      targetId: recordId,
    );
  }

  void deleteRecord(String id) {
    _scans.remove(id)?.cancel();
    _records.removeWhere((r) => r.id == id);
    // Nothing can be shared that no longer exists.
    for (var i = 0; i < _grants.length; i++) {
      final g = _grants[i];
      if (g.recordIds.contains(id)) {
        _grants[i] = g.copyWith(
          recordIds: [...g.recordIds]..remove(id),
        );
      }
    }
  }

  MedicalRecord recordById(String id) => _records.firstWhere(
        (r) => r.id == id,
        orElse: () => throw const Failure(
          kind: FailureKind.notFound,
          message: 'That record is no longer available.',
          code: 'RECORD_NOT_FOUND',
        ),
      );

  // --- consent -------------------------------------------------------------

  List<RecordAccessGrant> grants() {
    final sorted = [..._grants]
      ..sort((a, b) => b.grantedAt.compareTo(a.grantedAt));
    return List.unmodifiable(sorted);
  }

  List<RecordAccessRequest> pendingRequests() => List.unmodifiable(
        _requests.where((r) => r.status == AccessRequestStatus.pending),
      );

  List<RecordAccessEvent> accessLog() => List.unmodifiable(_accessLog);

  RecordAccessGrant? activeGrantFor(String providerId) {
    final live =
        _grants.where((g) => g.providerId == providerId && g.isActive).toList();
    if (live.isEmpty) return null;

    // Narrowest wins, so a later broad grant does not silently widen an earlier
    // consultation's reach.
    const rank = <ConsentScopeKind, int>{
      ConsentScopeKind.specificRecords: 0,
      ConsentScopeKind.recordTypes: 1,
      ConsentScopeKind.allRecords: 2,
    };
    live.sort((a, b) => rank[a.scopeKind]!.compareTo(rank[b.scopeKind]!));
    return live.first;
  }

  RecordAccessGrant addGrant(RecordAccessGrant grant) {
    _grants.insert(0, grant);
    _accessLog.insert(
      0,
      RecordAccessEvent(
        id: 'ev-${_nextId()}',
        actorName: 'You',
        recordTitle: 'Access granted to ${grant.providerName}',
        action: AccessAction.viewMetadata,
        purpose: grant.purpose,
        at: DateTime.now(),
      ),
    );
    return grant;
  }

  void revokeGrant(String id) {
    final index = _grants.indexWhere((g) => g.id == id);
    if (index < 0) return;
    final revoked = _grants[index].copyWith(revokedAt: DateTime.now());
    _grants[index] = revoked;
    _accessLog.insert(
      0,
      RecordAccessEvent(
        id: 'ev-${_nextId()}',
        actorName: 'You',
        recordTitle: 'Access revoked for ${revoked.providerName}',
        action: AccessAction.viewMetadata,
        at: DateTime.now(),
      ),
    );
  }

  void resolveRequest(String id, {required bool approved}) {
    final index = _requests.indexWhere((r) => r.id == id);
    if (index < 0) return;
    _requests[index] = _requests[index].copyWith(
      status:
          approved ? AccessRequestStatus.approved : AccessRequestStatus.denied,
    );
  }

  RecordAccessRequest requestById(String id) =>
      _requests.firstWhere((r) => r.id == id);

  void _noteGrantUse(String id) {
    final index = _grants.indexWhere((g) => g.id == id);
    if (index < 0) return;
    _grants[index] =
        _grants[index].copyWith(usesCount: _grants[index].usesCount + 1);
  }

  String _providerName(String providerId) {
    try {
      return doctorById(providerId).name;
    } catch (_) {
      return 'A provider';
    }
  }

  // --- prescriptions -------------------------------------------------------

  List<Prescription> prescriptions() {
    final sorted = [..._prescriptions]
      ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return List.unmodifiable(sorted);
  }

  Prescription prescriptionById(String id) => _prescriptions.firstWhere(
        (p) => p.id == id,
        orElse: () => throw const Failure(
          kind: FailureKind.notFound,
          message: 'That prescription is no longer available.',
          code: 'PRESCRIPTION_NOT_FOUND',
        ),
      );

  /// Issues a prescription and marks the appointment it came from.
  Prescription issuePrescription(Prescription prescription,
      {String? appointmentId}) {
    _prescriptions.insert(0, prescription);

    if (appointmentId != null) {
      final index = _appointments.indexWhere((a) => a.id == appointmentId);
      if (index >= 0) {
        _appointments[index] =
            _appointments[index].copyWith(hasPrescription: true);
      }
    }

    // Deliberately says nothing about the drug. "Your Sertraline prescription
    // is ready" on a lock screen is a disclosure to whoever picked the phone
    // up, with no consent record and no way to withdraw it.
    notify(
      kind: NotificationKind.prescriptionIssued,
      title: 'Prescription ready',
      body: 'From your consultation with ${prescription.providerName}',
      targetId: prescription.id,
    );

    return prescription;
  }

  // --- consultation notes --------------------------------------------------

  List<ConsultationNote> consultationNotes() {
    final sorted = [..._notes]
      ..sort((a, b) => b.writtenAt.compareTo(a.writtenAt));
    return List.unmodifiable(sorted);
  }

  ConsultationNote? noteForAppointment(String appointmentId) {
    for (final n in _notes) {
      if (n.appointmentId == appointmentId) return n;
    }
    return null;
  }

  /// Writes the doctor's note for a consultation.
  ///
  /// One per appointment, and it cannot be rewritten. A clinical note is
  /// evidence of what a clinician thought at a point in time; editing one
  /// silently rewrites the past, and the occasions a note most needs changing
  /// are exactly the ones where somebody has an interest in the earlier version
  /// disappearing. Corrections go in as addenda.
  ConsultationNote writeConsultationNote(
    String appointmentId, {
    required String body,
    required String authorName,
    required String authorRegistrationNumber,
  }) {
    final appointment = appointmentById(appointmentId);

    // A note belongs to a consultation that happened. Writing one against a
    // booking nobody has attended yet would be a record of an event that has
    // not occurred.
    final happened = appointment.status == AppointmentStatus.completed ||
        appointment.status == AppointmentStatus.inProgress ||
        appointment.status == AppointmentStatus.checkedIn;
    if (!happened) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'A note can only be written once the consultation has begun.',
        code: 'CONSULTATION_NOT_STARTED',
      );
    }

    if (noteForAppointment(appointmentId) != null) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'This consultation already has a note. Add an addendum.',
        code: 'NOTE_EXISTS',
      );
    }

    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Write the note before saving it.',
        code: 'NOTE_EMPTY',
      );
    }
    if (trimmed.length > ConsultationNote.maxBodyLength) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'That note is too long.',
        code: 'NOTE_TOO_LONG',
      );
    }

    final note = ConsultationNote(
      id: 'note-${_nextId()}',
      appointmentId: appointmentId,
      authorName: authorName,
      authorRegistrationNumber: authorRegistrationNumber,
      writtenAt: DateTime.now(),
      body: trimmed,
    );
    _notes.insert(0, note);

    // The patient is told there is something new in their record. The body is
    // clinical and stays behind authentication; the notification says only
    // that it exists.
    notify(
      kind: NotificationKind.recordReady,
      title: 'Consultation notes added',
      body: '$authorName has written up your consultation',
      targetId: appointmentId,
    );

    return note;
  }

  /// Appends a correction. Never replaces anything.
  ConsultationNote addNoteAddendum(
    String noteId, {
    required String body,
    required String authorName,
  }) {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index < 0) {
      throw const Failure(
        kind: FailureKind.notFound,
        message: 'That note no longer exists.',
        code: 'NOTE_NOT_FOUND',
      );
    }

    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Write the addendum before saving it.',
        code: 'NOTE_EMPTY',
      );
    }
    if (trimmed.length > ConsultationNote.maxAddendumLength) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'That addendum is too long.',
        code: 'NOTE_TOO_LONG',
      );
    }

    final updated = _notes[index].copyWith(
      addenda: [
        ..._notes[index].addenda,
        NoteAddendum(
          body: trimmed,
          authorName: authorName,
          writtenAt: DateTime.now(),
        ),
      ],
    );
    _notes[index] = updated;
    return updated;
  }

  // --- waitlist ------------------------------------------------------------

  List<WaitlistEntry> waitlist() {
    final sorted = [..._waitlist]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(sorted);
  }

  WaitlistEntry joinWaitlist({
    required Doctor doctor,
    required ConsultationMode mode,
    DateTime? preferredDate,
  }) {
    final duplicate = _waitlist.any((e) =>
        e.isActive &&
        e.doctorId == doctor.id &&
        e.mode == mode &&
        _sameDayOrBothNull(e.preferredDate, preferredDate));
    if (duplicate) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'You are already on the list for this doctor.',
        code: 'ALREADY_WAITING',
      );
    }

    final entry = WaitlistEntry(
      id: 'wl-${_nextId()}',
      doctorId: doctor.id,
      doctorName: doctor.name,
      mode: mode,
      createdAt: DateTime.now(),
      status: WaitlistStatus.waiting,
      preferredDate: preferredDate,
    );
    _waitlist.insert(0, entry);
    return entry;
  }

  WaitlistEntry leaveWaitlist(String id) {
    final index = _waitlist.indexWhere((e) => e.id == id);
    if (index < 0) {
      throw const Failure(
        kind: FailureKind.notFound,
        message: 'That waitlist entry no longer exists.',
        code: 'WAITLIST_NOT_FOUND',
      );
    }
    final updated = _waitlist[index].copyWith(status: WaitlistStatus.cancelled);
    _waitlist[index] = updated;
    return updated;
  }

  /// Tells everyone waiting that a slot opened.
  ///
  /// Called wherever a slot returns to the pool — a cancellation, or a
  /// reschedule moving away from it. Notifying **everyone** matching rather
  /// than holding the slot for the first in line is deliberate: a held slot
  /// sits empty while that person is asleep or no longer interested, which is
  /// exactly the waste the cancellation was supposed to recover. The
  /// notification says it is first come, first served.
  ///
  /// Each entry is marked notified, which is terminal. An entry that stayed
  /// active would ping the same person on every cancellation for the rest of
  /// the month, and that is where people turn notifications off — which on this
  /// app also silences their appointment reminders.
  int announceFreeSlot({
    required String doctorId,
    required DateTime start,
    required ConsultationMode mode,
  }) {
    final now = DateTime.now();
    var told = 0;

    for (var i = 0; i < _waitlist.length; i++) {
      final entry = _waitlist[i];
      if (!entry.matches(
        doctorId: doctorId,
        start: start,
        mode: mode,
        now: now,
      )) {
        continue;
      }

      _waitlist[i] = entry.copyWith(
        status: WaitlistStatus.notified,
        notifiedAt: now,
      );
      told++;

      notify(
        kind: NotificationKind.appointmentReminder,
        title: 'A slot opened',
        body: '${entry.doctorName} · ${_shortWhen(start)} · first come, '
            'first served',
        targetId: entry.doctorId,
      );
    }

    return told;
  }

  static bool _sameDayOrBothNull(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // --- refill requests -----------------------------------------------------

  List<RefillRequest> refillRequests() {
    final sorted = [..._refillRequests]
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return List.unmodifiable(sorted);
  }

  RefillRequest refillRequestById(String id) => _refillRequests.firstWhere(
        (r) => r.id == id,
        orElse: () => throw const Failure(
          kind: FailureKind.notFound,
          message: 'That request no longer exists.',
          code: 'REFILL_NOT_FOUND',
        ),
      );

  /// Asks the issuing doctor to repeat a prescription.
  RefillRequest requestRefill(String prescriptionId, {String? note}) {
    final prescription = _prescriptions.firstWhere(
      (p) => p.id == prescriptionId,
      orElse: () => throw const Failure(
        kind: FailureKind.notFound,
        message: 'That prescription no longer exists.',
        code: 'PRESCRIPTION_NOT_FOUND',
      ),
    );

    if (!RefillRequest.canRequestFor(prescription)) {
      // A cancelled or superseded prescription was withdrawn or replaced by a
      // clinician. Repeating it would quietly reinstate a decision somebody
      // deliberately made.
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'This prescription can no longer be repeated.',
        code: 'REFILL_NOT_ALLOWED',
      );
    }

    if (_refillRequests
        .any((r) => r.prescriptionId == prescriptionId && r.isOpen)) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'You have already asked for a repeat of this prescription.',
        code: 'REFILL_ALREADY_REQUESTED',
      );
    }

    final trimmed = note?.trim();
    if (trimmed != null &&
        trimmed.length > RefillRequest.maxPatientNoteLength) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Keep your note under 300 characters.',
        code: 'NOTE_TOO_LONG',
      );
    }

    final request = RefillRequest(
      id: 'rf-${_nextId()}',
      prescriptionId: prescriptionId,
      doctorName: prescription.providerName,
      requestedAt: DateTime.now(),
      status: RefillStatus.pending,
      patientNote: (trimmed?.isEmpty ?? true) ? null : trimmed,
    );
    _refillRequests.insert(0, request);

    notify(
      kind: NotificationKind.accountUpdate,
      title: 'Repeat requested',
      body: 'Sent to ${prescription.providerName}',
      targetId: request.id,
    );

    return request;
  }

  RefillRequest cancelRefill(String id) {
    final existing = refillRequestById(id);
    if (!existing.canCancel) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'Your doctor has already answered this request.',
        code: 'REFILL_ALREADY_DECIDED',
      );
    }
    final updated = existing.copyWith(
      status: RefillStatus.cancelled,
      decidedAt: DateTime.now(),
    );
    _replaceRefill(updated);
    return updated;
  }

  /// Approves a refill, issuing a fresh prescription.
  ///
  /// The new document is a **new prescription**, not a copy carrying the old
  /// id: it needs its own verification code, its own issue date and its own
  /// write-once PDF, because a pharmacist dispensing against it is dispensing
  /// today rather than against a document from six weeks ago.
  ///
  /// A refill is by definition a follow-up, which is exactly what makes a
  /// List B medicine prescribable at all. That makes this the one
  /// patient-initiated path that can end in a restricted drug being dispensed,
  /// so the drug list is re-checked here rather than inherited from the
  /// original.
  RefillRequest approveRefill(String id) {
    final request = refillRequestById(id);
    if (!request.isOpen) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'This request has already been answered.',
        code: 'REFILL_ALREADY_DECIDED',
      );
    }

    final original = _prescriptions.firstWhere(
      (p) => p.id == request.prescriptionId,
      orElse: () => throw const Failure(
        kind: FailureKind.notFound,
        message: 'That prescription no longer exists.',
        code: 'PRESCRIPTION_NOT_FOUND',
      ),
    );

    // Re-resolved from the catalogue by name, because an item on an issued
    // prescription is a snapshot with no drug id — and a classification that
    // has changed since should be honoured rather than inherited.
    for (final item in original.items) {
      final matches = FixturePrescriptionRepository.drugCatalogue
          .where((d) => d.name == item.drugName);
      if (matches.isEmpty) continue;
      final drug = matches.first;
      if (!drug.isPrescribableOn(isFollowUp: true)) {
        throw Failure(
          kind: FailureKind.validation,
          message: '${drug.name} cannot be repeated remotely.',
          code: 'DRUG_NOT_PRESCRIBABLE',
        );
      }
    }

    final refill = Prescription(
      id: 'rx-${_nextId()}',
      providerName: original.providerName,
      providerQualification: original.providerQualification,
      providerRegistrationNumber: original.providerRegistrationNumber,
      patientName: original.patientName,
      patientAge: original.patientAge,
      patientGender: original.patientGender,
      issuedAt: DateTime.now(),
      status: PrescriptionStatus.issued,
      items: original.items,
      diagnosis: original.diagnosis,
      advice: original.advice,
      verificationCode: 'MD-RF${_nextId()}',
      appointmentReference: original.appointmentReference,
    );
    // Filed against the same consultation as the original: a repeat is not a
    // new episode of care, and attributing it to nothing would leave the
    // patient with a prescription that belongs to no visit.
    issuePrescription(refill, appointmentId: original.appointmentReference);

    final updated = request.copyWith(
      status: RefillStatus.approved,
      decidedAt: DateTime.now(),
      issuedPrescriptionId: refill.id,
    );
    _replaceRefill(updated);
    return updated;
  }

  /// Declines a refill. **A reason is mandatory.**
  ///
  /// A patient told only "declined" will either ask again or stop taking a
  /// medicine they still need. The category says what to do about it; the note
  /// says why. Neither is optional, and the fixture refuses a blank one so the
  /// UI cannot be built against a laxer contract than the server enforces.
  RefillRequest declineRefill(
    String id, {
    required RefillDeclineReason reason,
    required String note,
  }) {
    final request = refillRequestById(id);
    if (!request.isOpen) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'This request has already been answered.',
        code: 'REFILL_ALREADY_DECIDED',
      );
    }

    final trimmed = note.trim();
    if (trimmed.isEmpty) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Tell the patient why, so they know what to do next.',
        code: 'DECLINE_REASON_REQUIRED',
      );
    }
    if (trimmed.length > RefillRequest.maxDecisionNoteLength) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Keep the note under 300 characters.',
        code: 'NOTE_TOO_LONG',
      );
    }

    final updated = request.copyWith(
      status: RefillStatus.declined,
      decidedAt: DateTime.now(),
      declineReason: reason,
      decisionNote: trimmed,
    );
    _replaceRefill(updated);
    return updated;
  }

  void _replaceRefill(RefillRequest updated) {
    final index = _refillRequests.indexWhere((r) => r.id == updated.id);
    if (index >= 0) _refillRequests[index] = updated;
  }

  // --- notifications -------------------------------------------------------

  List<AppNotification> notifications() {
    final sorted = [..._notifications]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(sorted);
  }

  int unreadNotificationCount() =>
      _notifications.where((n) => !n.isRead).length;

  NotificationPreferences notificationPreferences() => _notificationPreferences;

  void setNotificationPreferences(NotificationPreferences preferences) {
    _notificationPreferences = preferences;
  }

  void registerDevice(String token) => _deviceToken = token;

  String? get registeredDeviceToken => _deviceToken;

  void unregisterDevice() => _deviceToken = null;

  void markNotificationRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index < 0) return;
    if (_notifications[index].isRead) return;
    _notifications[index] =
        _notifications[index].copyWith(readAt: DateTime.now());
  }

  void markAllNotificationsRead() {
    final now = DateTime.now();
    for (var i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        _notifications[i] = _notifications[i].copyWith(readAt: now);
      }
    }
  }

  /// Files a notification, if the user's preferences allow it right now.
  ///
  /// Routed through [NotificationPreferences.allows] rather than filed
  /// unconditionally, because that is what the server does — and a fixture that
  /// stores everything and filters at read time would let the preference screen
  /// look like it works while proving nothing. Turning a kind off in sample
  /// data really does stop it arriving.
  ///
  /// **No clinical content in [title] or [body].** These strings reach a lock
  /// screen, a paired watch and anyone holding the phone. The detail lives
  /// behind [targetId], inside the app.
  void notify({
    required NotificationKind kind,
    required String title,
    required String body,
    String? targetId,
  }) {
    final now = DateTime.now();
    if (!_notificationPreferences.allows(kind, at: now)) return;

    _notifications.insert(
      0,
      AppNotification(
        id: 'n-${_nextId()}',
        kind: kind,
        title: title,
        body: body,
        createdAt: now,
        targetId: targetId,
      ),
    );
  }

  // --- medications ---------------------------------------------------------

  /// The patient's own account of which doses they took.
  ///
  /// There is no `courses()` here on purpose: a course is derived from the
  /// prescriptions this same store already holds, so cancelling a prescription
  /// removes its schedule with it. A separate copy is how an app ends up
  /// reminding somebody to take a drug that was withdrawn.
  List<DoseMark> doseMarksSince(DateTime from) {
    final floor = DateTime(from.year, from.month, from.day);
    final marks = _doseMarks.values
        .where((m) => !m.day.isBefore(floor))
        .toList(growable: false)
      ..sort((a, b) => a.day.compareTo(b.day));
    return List.unmodifiable(marks);
  }

  DoseMark markDose(
    String courseId, {
    required DateTime day,
    required DoseSlot slot,
    required DoseOutcome outcome,
  }) {
    final at = DateTime(day.year, day.month, day.day);
    final now = DateTime.now();

    // A future dose cannot be marked. Ticking tomorrow's tablet today records
    // something that has not happened, and the record is then indistinguishable
    // from one that did.
    if (at.isAfter(istDayOf(now))) {
      throw const Failure(
        kind: FailureKind.validation,
        message: "You can't tick off a dose that isn't due yet.",
        code: 'DOSE_NOT_DUE',
      );
    }

    final parts = courseId.split('#');
    final prescriptionId = parts.first;
    final index = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final prescription = _prescriptions.firstWhere(
      (p) => p.id == prescriptionId,
      orElse: () => throw const Failure(
        kind: FailureKind.notFound,
        message: 'That prescription no longer exists.',
        code: 'PRESCRIPTION_NOT_FOUND',
      ),
    );
    if (index == null || index < 0 || index >= prescription.items.length) {
      throw const Failure(
        kind: FailureKind.notFound,
        message: 'That medicine is not on this prescription.',
        code: 'COURSE_NOT_FOUND',
      );
    }

    // A withdrawn or replaced prescription has no doses left to take, and a
    // log against one would attribute a tablet to an instruction that had been
    // revoked.
    if (prescription.status != PrescriptionStatus.issued) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'This prescription is no longer active.',
        code: 'PRESCRIPTION_NOT_ACTIVE',
      );
    }

    final course = MedicationCourse(
      prescriptionId: prescription.id,
      itemIndex: index,
      item: prescription.items[index],
      startedOn: DateTime(prescription.issuedAt.year,
          prescription.issuedAt.month, prescription.issuedAt.day),
      schedule: DoseSchedule.parse(prescription.items[index].frequency),
      prescriberName: prescription.providerName,
    );
    if (!course.isActiveOn(at)) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'That day is outside this course.',
        code: 'DOSE_OUTSIDE_COURSE',
      );
    }

    final id = ScheduledDose.idFor(courseId, at, slot);
    final mark = DoseMark(
      id: id,
      courseId: courseId,
      day: at,
      slot: slot,
      outcome: outcome,
      markedAt: now,
    );
    _doseMarks[id] = mark;
    return mark;
  }

  void clearDoseMark(
    String courseId, {
    required DateTime day,
    required DoseSlot slot,
  }) {
    final at = DateTime(day.year, day.month, day.day);
    _doseMarks.remove(ScheduledDose.idFor(courseId, at, slot));
  }

  // --- ratings -------------------------------------------------------------

  List<Rating> ratings() {
    final sorted = [..._ratings]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(sorted);
  }

  Rating addRating(Rating rating) {
    if (rating.stars < 1 || rating.stars > 5) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Choose between one and five stars.',
        code: 'INVALID_RATING',
      );
    }
    if (_ratings.any((r) => r.appointmentId == rating.appointmentId)) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'You have already rated this consultation.',
        code: 'ALREADY_RATED',
      );
    }
    _ratings.insert(0, rating);

    final index = _appointments.indexWhere((a) => a.id == rating.appointmentId);
    if (index >= 0) {
      _appointments[index] = _appointments[index].copyWith(hasRating: true);
    }
    return rating;
  }

  /// Files a doctor's public answer to a rating.
  ///
  /// Enters moderation exactly as the rating did. A reply is public text
  /// written by the person with the most incentive to argue, and one that
  /// names a patient's condition would be a disclosure published straight past
  /// the queue that exists to catch it.
  Rating replyToRating(String id, {required String reply}) {
    final index = _ratings.indexWhere((r) => r.id == id);
    if (index < 0) {
      throw const Failure(
        kind: FailureKind.notFound,
        message: 'That rating no longer exists.',
        code: 'RATING_NOT_FOUND',
      );
    }

    final trimmed = reply.trim();
    if (trimmed.isEmpty) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Write a reply before sending it.',
        code: 'REPLY_EMPTY',
      );
    }
    if (trimmed.length > Rating.maxReplyLength) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'A reply can be at most 300 characters.',
        code: 'REPLY_TOO_LONG',
      );
    }
    if (!_ratings[index].canReply) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'This rating cannot be replied to.',
        code: 'REPLY_NOT_ALLOWED',
      );
    }

    final updated = _ratings[index].copyWith(
      providerReply: trimmed,
      providerRepliedAt: DateTime.now(),
      replyStatus: RatingStatus.pendingModeration,
    );
    _ratings[index] = updated;
    return updated;
  }

  Rating editRating(String id, {required int stars, String? comment}) {
    final index = _ratings.indexWhere((r) => r.id == id);
    if (index < 0) {
      throw const Failure(
        kind: FailureKind.notFound,
        message: 'That rating no longer exists.',
        code: 'RATING_NOT_FOUND',
      );
    }
    if (!_ratings[index].canEdit) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'Ratings can only be changed within 14 days.',
        code: 'EDIT_WINDOW_CLOSED',
      );
    }

    // An edited rating re-enters moderation, or the queue is trivially
    // bypassed: submit something bland, wait, rewrite.
    final updated = _ratings[index].copyWith(
      stars: stars,
      comment: comment,
      editedAt: DateTime.now(),
      status: RatingStatus.pendingModeration,
    );
    _ratings[index] = updated;
    return updated;
  }

  /// Anything awaiting a moderator: the rating, its reply, or both.
  ///
  /// A published rating whose reply is pending still belongs in this queue.
  /// Filtering on the rating's own status alone would leave every reply
  /// unreviewed and therefore never visible — the failure mode of adding a
  /// moderated field and forgetting the queue that clears it.
  List<Rating> pendingRatings() => List.unmodifiable(
        _ratings.where((r) =>
            r.status == RatingStatus.pendingModeration ||
            (r.hasReply && r.replyStatus == RatingStatus.pendingModeration)),
      );

  void moderateRating(String id, RatingStatus status) {
    final index = _ratings.indexWhere((r) => r.id == id);
    if (index >= 0) _ratings[index] = _ratings[index].copyWith(status: status);
  }

  /// Moderates a doctor's reply, separately from the rating.
  ///
  /// Without this a reply sits at `pendingModeration` forever and never reaches
  /// a patient — the failure mode of adding a moderated field and forgetting
  /// the queue that clears it.
  void moderateRatingReply(String id, RatingStatus status) {
    final index = _ratings.indexWhere((r) => r.id == id);
    if (index < 0) return;
    if (!_ratings[index].hasReply) return;
    _ratings[index] = _ratings[index].copyWith(replyStatus: status);
  }

  // --- support -------------------------------------------------------------

  List<SupportTicket> tickets() {
    final sorted = [..._tickets]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(sorted);
  }

  SupportTicket ticketById(String id) => _tickets.firstWhere(
        (t) => t.id == id,
        orElse: () => throw const Failure(
          kind: FailureKind.notFound,
          message: 'That ticket no longer exists.',
          code: 'TICKET_NOT_FOUND',
        ),
      );

  SupportTicket addTicket(SupportTicket ticket) {
    _tickets.insert(0, ticket);
    return ticket;
  }

  SupportTicket appendMessage(String ticketId, TicketMessage message) {
    final index = _tickets.indexWhere((t) => t.id == ticketId);
    if (index < 0) {
      throw const Failure(
        kind: FailureKind.notFound,
        message: 'That ticket no longer exists.',
        code: 'TICKET_NOT_FOUND',
      );
    }

    final ticket = _tickets[index];
    final updated = ticket.copyWith(
      messages: [...ticket.messages, message],
      updatedAt: DateTime.now(),
      // A support reply picks the ticket up; a user reply reopens it.
      status: message.isFromSupport
          ? TicketStatus.assigned
          : (ticket.status == TicketStatus.closed
              ? TicketStatus.open
              : ticket.status),
    );
    _tickets[index] = updated;
    return updated;
  }

  SupportTicket setTicketStatus(String id, TicketStatus status) {
    final index = _tickets.indexWhere((t) => t.id == id);
    if (index < 0) {
      throw const Failure(
        kind: FailureKind.notFound,
        message: 'That ticket no longer exists.',
        code: 'TICKET_NOT_FOUND',
      );
    }
    final updated =
        _tickets[index].copyWith(status: status, updatedAt: DateTime.now());
    _tickets[index] = updated;
    return updated;
  }

  // --- availability --------------------------------------------------------

  List<AvailabilityRule> rules() => List.unmodifiable(_rules);
  List<AvailabilityException> exceptions() => List.unmodifiable(_exceptions);

  AvailabilityRule addRule(AvailabilityRule rule) {
    if (!rule.isValid) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'The end time must be after the start time.',
        code: 'INVALID_TIME_RANGE',
      );
    }

    final clash = _rules.any(
      (r) =>
          r.isActive &&
          r.weekday == rule.weekday &&
          r.mode == rule.mode &&
          rule.start.totalMinutes < r.end.totalMinutes &&
          rule.end.totalMinutes > r.start.totalMinutes,
    );
    if (clash) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'That overlaps hours you have already set for this day.',
        code: 'OVERLAPPING_AVAILABILITY',
      );
    }
    _rules.add(rule);
    return rule;
  }

  void deleteRule(String id) => _rules.removeWhere((r) => r.id == id);

  AvailabilityRule toggleRule(String id, {required bool active}) {
    final index = _rules.indexWhere((r) => r.id == id);
    if (index < 0) {
      throw const Failure(
        kind: FailureKind.notFound,
        message: 'Those hours no longer exist.',
        code: 'RULE_NOT_FOUND',
      );
    }
    final updated = _rules[index].copyWith(isActive: active);
    _rules[index] = updated;
    return updated;
  }

  AvailabilityException blockDay(AvailabilityException exception) {
    _exceptions.add(exception);
    return exception;
  }

  void deleteException(String id) => _exceptions.removeWhere((e) => e.id == id);

  /// Whether a doctor has blocked a calendar day.
  ///
  /// Consulted by slot generation, so a blocked day genuinely produces no
  /// slots — the bug the real backend had until this rule was wired in.
  bool isDayBlocked(DateTime day) => _exceptions.any(
        (e) =>
            e.isBlocked &&
            e.date.year == day.year &&
            e.date.month == day.month &&
            e.date.day == day.day,
      );

  // --- consultation --------------------------------------------------------

  bool hasConsent(String consultationId) =>
      _consentCaptured.contains(consultationId);

  void captureConsent(String consultationId) =>
      _consentCaptured.add(consultationId);

  // --- profile -------------------------------------------------------------

  PatientProfile profile() => _profile;

  PatientProfile updateProfile(PatientProfileDraft draft) {
    _profile = _profile.withDraft(draft);
    return _profile;
  }

  // --- credentials and provider verification -------------------------------

  VerificationChecklist checklist() => _checklist;

  VerificationChecklist updateChecklist(VerificationChecklist checklist) {
    _checklist = checklist;
    return _checklist;
  }

  /// Files a verification application so it appears in the operator console.
  ///
  /// This is the join that makes the two apps one product in fixture mode: a
  /// doctor submitting on their phone shows up in a reviewer's queue on the web.
  void submitForReview({
    required String userId,
    required String displayName,
    String? email,
  }) {
    _applications.removeWhere((a) => a.userId == userId);
    _applications.insert(
      0,
      ProviderApplicationRecord(
        userId: userId,
        displayName: displayName,
        email: email,
        registrationNumber: _checklist.registrationNumber,
        mfaEnrolled: _checklist.mfaEnrolled,
        submittedAt: DateTime.now(),
        status: ProviderApplicationStatus.submitted,
        documents: _checklist.credentials
            .map(
              (c) => ProviderApplicationDocument(
                id: '$userId-${c.kind.wire}',
                kind: c.kind,
                status: c.status,
                fileName: c.fileName,
                uploadedAt: c.uploadedAt ?? DateTime.now(),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  List<ProviderApplicationRecord> applications() =>
      List.unmodifiable(_applications);

  ProviderApplicationRecord applicationById(String userId) =>
      _applications.firstWhere(
        (a) => a.userId == userId,
        orElse: () => throw const Failure(
          kind: FailureKind.notFound,
          message: 'No such application.',
          code: 'APPLICATION_NOT_FOUND',
        ),
      );

  void updateApplication(ProviderApplicationRecord updated) {
    final index = _applications.indexWhere((a) => a.userId == updated.userId);
    if (index >= 0) _applications[index] = updated;
  }

  // --- helpers -------------------------------------------------------------

  int _counter = 0;
  String _nextId() => '${DateTime.now().millisecondsSinceEpoch}-${_counter++}';

  /// Human-quotable reference, e.g. MD-8K2P4Q. Excludes easily confused
  /// characters so it survives being read out over a phone call.
  String _reference() {
    const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final code = List.generate(
      6,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
    return 'MD-$code';
  }
}
