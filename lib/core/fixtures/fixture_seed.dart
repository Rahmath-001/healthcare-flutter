import 'package:meta/meta.dart';

import '../../features/appointments/domain/appointment.dart';
import '../../features/availability/domain/availability.dart';
import '../../features/consent/domain/consent.dart';
import '../../features/credentials/domain/credential.dart';
import '../../features/notifications/domain/notification.dart';
import '../../features/prescriptions/domain/prescription.dart';
import '../../features/providers_search/data/doctor_fixtures.dart';
import '../../features/providers_search/domain/doctor.dart';
import '../../features/ratings/domain/rating.dart';
import '../../features/records/domain/medical_record.dart';
import '../../features/settings/domain/patient_profile.dart';
import '../../features/settings/domain/signed_in_device.dart';
import '../../features/support/domain/support_ticket.dart';
import 'provider_application.dart';

/// The starting state of the fixture backend.
///
/// Written as a plausible six months of one patient's history rather than as
/// one row per state, because the point is to exercise the product: there is a
/// consultation that produced a prescription that can be opened, a completed
/// appointment that can still be rated, a grant about to expire, a support
/// ticket mid-conversation, and a doctor waiting in the review queue.
///
/// Everything is relative to "now", so the app never looks stale — an
/// appointment seeded at a fixed date would be in the past by the time anyone
/// demoed it.
abstract final class FixtureSeed {
  /// The clock the seed is built against.
  ///
  /// Real time in the app, pinnable in a test. Everything here is relative to
  /// "now" so the sample data never looks stale — which is right for a demo and
  /// wrong for a golden file: a records list renders "21 Aug 2026" today and
  /// "22 Aug 2026" tomorrow, so the picture is only stable until the date
  /// changes width. It survived until now purely because the test font draws
  /// every digit as an identical box; a 9-to-10 or 31-to-1 rollover would have
  /// broken it, roughly twice a month, for no reason anyone could act on.
  ///
  /// Pin it with [pinClock] and the seed becomes fully deterministic.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Freezes the seed's clock at [at]. Returns a function that restores it.
  ///
  /// Deliberately returns the undo rather than relying on the caller to
  /// remember the previous value: a test that pins the clock and forgets to
  /// release it makes every test after it in the same process mysteriously
  /// date-locked.
  @visibleForTesting
  static void Function() pinClock(DateTime at) {
    final previous = clock;
    clock = () => at;
    return () => clock = previous;
  }

  static DateTime _now() => clock();

  /// A date [days] from today at [hour]:[minute], local time.
  static DateTime at(int days, int hour, int minute) {
    final now = _now();
    final day =
        DateTime(now.year, now.month, now.day).add(Duration(days: days));
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  static PatientProfile profile() => PatientProfile(
        userId: 'u-patient',
        displayName: 'Priya Sharma',
        email: 'priya.sharma@example.com',
        phone: '+91 98765 43210',
        dateOfBirth: DateTime(1994, 4, 12),
        gender: Gender.female,
        bloodGroup: BloodGroup.oPositive,
        allergies: const ['Penicillin', 'Dust mites'],
        chronicConditions: const ['Hypothyroidism'],
        emergencyContactName: 'Anil Sharma',
        emergencyContactPhone: '+91 98123 45678',
      );

  // --- appointments --------------------------------------------------------

  static List<Appointment> appointments() => [
        // Joinable shortly — the demo's live-consultation entry point.
        Appointment(
          id: 'a1',
          referenceCode: 'MD-7K2P4Q',
          doctor: DoctorFixtures.byId('d1'),
          patientId: 'u-patient',
          patientName: 'Priya Sharma',
          start: at(0, _soonHour(), 0),
          end: at(0, _soonHour(), 30),
          mode: ConsultationMode.video,
          status: AppointmentStatus.confirmed,
          paymentStatus: PaymentStatus.notRequired,
          feeInr: 800,
          reasonForVisit: 'Follow-up on blood pressure readings',
          consultationId: 'a1',
        ),
        Appointment(
          id: 'a2',
          referenceCode: 'MD-3H8W2R',
          doctor: DoctorFixtures.byId('d5'),
          patientId: 'u-patient',
          patientName: 'Priya Sharma',
          start: at(2, 11, 30),
          end: at(2, 12, 0),
          mode: ConsultationMode.inPerson,
          status: AppointmentStatus.confirmed,
          paymentStatus: PaymentStatus.notRequired,
          feeInr: 600,
          reasonForVisit: 'Routine child vaccination',
        ),
        // Completed and already prescribed for — opens the prescription.
        Appointment(
          id: 'a3',
          referenceCode: 'MD-9L5N1T',
          doctor: DoctorFixtures.byId('d3'),
          patientId: 'u-patient',
          patientName: 'Priya Sharma',
          start: at(-9, 16, 0),
          end: at(-9, 16, 30),
          mode: ConsultationMode.video,
          status: AppointmentStatus.completed,
          paymentStatus: PaymentStatus.notRequired,
          feeInr: 500,
          reasonForVisit: 'Persistent skin rash',
          consultationId: 'a3',
          hasPrescription: true,
          hasRating: true,
        ),
        // Completed, unrated, inside the 14-day window: the rating flow works.
        Appointment(
          id: 'a4',
          referenceCode: 'MD-2B6V8X',
          doctor: DoctorFixtures.byId('d2'),
          patientId: 'u-patient',
          patientName: 'Priya Sharma',
          start: at(-4, 10, 0),
          end: at(-4, 10, 30),
          mode: ConsultationMode.video,
          status: AppointmentStatus.completed,
          paymentStatus: PaymentStatus.notRequired,
          feeInr: 700,
          reasonForVisit: 'Viral fever, third day',
          consultationId: 'a4',
          hasPrescription: true,
        ),
        Appointment(
          id: 'a5',
          referenceCode: 'MD-5R1Z9C',
          doctor: DoctorFixtures.byId('d4'),
          patientId: 'u-patient',
          patientName: 'Priya Sharma',
          start: at(-30, 9, 0),
          end: at(-30, 9, 30),
          mode: ConsultationMode.inPerson,
          status: AppointmentStatus.cancelledByPatient,
          paymentStatus: PaymentStatus.notRequired,
          feeInr: 900,
          reasonForVisit: 'Knee pain',
          cancellationReason: 'Could not travel',
        ),
      ];

  /// An hour later today, clamped so the seeded consultation is always ahead of
  /// "now" and inside its join window rather than accidentally expired.
  static int _soonHour() {
    final hour = _now().hour + 1;
    return hour > 22 ? 22 : hour;
  }

  // --- records -------------------------------------------------------------

  static List<MedicalRecord> records() => [
        MedicalRecord(
          id: 'r1',
          title: 'Complete Blood Count',
          type: RecordType.labReport,
          source: RecordSource.provider,
          recordedAt: at(-9, 9, 0),
          uploadedAt: at(-9, 10, 0),
          scanStatus: ScanStatus.clean,
          sizeBytes: 248 * 1024,
          contentType: 'application/pdf',
          issuedByName: 'Apollo Diagnostics',
          pageCount: 2,
        ),
        MedicalRecord(
          id: 'r2',
          title: 'Chest X-Ray',
          type: RecordType.xray,
          source: RecordSource.provider,
          recordedAt: at(-34, 11, 0),
          uploadedAt: at(-33, 9, 0),
          scanStatus: ScanStatus.clean,
          sizeBytes: 1830 * 1024,
          contentType: 'image/jpeg',
          issuedByName: 'Fortis Radiology',
        ),
        MedicalRecord(
          id: 'r3',
          title: 'Thyroid Profile',
          type: RecordType.labReport,
          source: RecordSource.patient,
          recordedAt: at(-62, 8, 30),
          uploadedAt: at(-61, 20, 0),
          scanStatus: ScanStatus.clean,
          sizeBytes: 190 * 1024,
          contentType: 'application/pdf',
          notes: 'Six-monthly check for hypothyroidism.',
          pageCount: 1,
        ),
        MedicalRecord(
          id: 'r4',
          title: 'Discharge Summary — Day Care',
          type: RecordType.dischargeSummary,
          source: RecordSource.provider,
          recordedAt: at(-120, 18, 0),
          uploadedAt: at(-119, 12, 0),
          scanStatus: ScanStatus.clean,
          sizeBytes: 420 * 1024,
          contentType: 'application/pdf',
          issuedByName: 'Manipal Hospital',
          pageCount: 4,
        ),
        // Deliberately still being checked, so the UI's "not readable yet"
        // state is visible without having to upload something first.
        MedicalRecord(
          id: 'r5',
          title: 'Vitamin D Panel',
          type: RecordType.labReport,
          source: RecordSource.patient,
          recordedAt: at(-1, 8, 0),
          uploadedAt: _now().subtract(const Duration(minutes: 2)),
          scanStatus: ScanStatus.pending,
          sizeBytes: 96 * 1024,
          contentType: 'application/pdf',
        ),
      ];

  // --- prescriptions -------------------------------------------------------

  static List<Prescription> prescriptions() => [
        Prescription(
          id: 'p1',
          verificationCode: 'RX-4M8K2P',
          providerName: 'Dr Meera Iyer',
          providerQualification: 'MBBS, MD (Dermatology)',
          providerRegistrationNumber: 'TSMC-77410',
          patientName: 'Priya Sharma',
          patientAge: '32',
          patientGender: 'Female',
          issuedAt: at(-9, 16, 30),
          status: PrescriptionStatus.issued,
          diagnosis: 'Contact dermatitis',
          advice: 'Avoid known irritants. Use a fragrance-free moisturiser '
              'twice daily. Return if the rash spreads or blisters.',
          appointmentReference: 'MD-9L5N1T',
          items: const [
            PrescriptionItem(
              drugName: 'Cetirizine',
              genericName: 'Cetirizine hydrochloride',
              strength: '10 mg',
              form: 'Tablet',
              frequency: '0-0-1',
              durationDays: 7,
              instructions: 'Take at night. May cause drowsiness.',
            ),
            PrescriptionItem(
              drugName: 'Pantoprazole',
              genericName: 'Pantoprazole sodium',
              strength: '40 mg',
              form: 'Tablet',
              frequency: '1-0-0',
              durationDays: 5,
              instructions: 'Take before breakfast.',
            ),
          ],
        ),
        Prescription(
          id: 'p2',
          verificationCode: 'RX-9T3B7D',
          providerName: 'Dr Rajesh Kumar',
          providerQualification: 'MBBS, MD (General Medicine)',
          providerRegistrationNumber: 'KMC-41902',
          patientName: 'Priya Sharma',
          patientAge: '32',
          patientGender: 'Female',
          issuedAt: at(-4, 10, 30),
          status: PrescriptionStatus.issued,
          diagnosis: 'Viral fever',
          advice:
              'Rest and fluids. Review if fever persists beyond three days.',
          appointmentReference: 'MD-2B6V8X',
          items: const [
            PrescriptionItem(
              drugName: 'Paracetamol',
              genericName: 'Paracetamol',
              strength: '650 mg',
              form: 'Tablet',
              frequency: '1-1-1',
              durationDays: 3,
              instructions: 'After food. Do not exceed 4 doses in 24 hours.',
            ),
            PrescriptionItem(
              drugName: 'ORS',
              genericName: 'Oral rehydration salts',
              strength: '21.8 g',
              form: 'Sachet',
              frequency: 'As needed',
              durationDays: 3,
              instructions: 'One sachet in one litre of clean water.',
            ),
          ],
        ),
        // A course that is still running, so the medicines screen has
        // something to take today. The other two have finished, and a sample
        // dataset where every prescription is over demos the empty state
        // rather than the feature.
        Prescription(
          id: 'p3',
          verificationCode: 'RX-2C7Q1H',
          providerName: 'Dr Rajesh Kumar',
          providerQualification: 'MBBS, MD (General Medicine)',
          providerRegistrationNumber: 'KMC-41902',
          patientName: 'Priya Sharma',
          patientAge: '32',
          patientGender: 'Female',
          issuedAt: at(-2, 9, 15),
          status: PrescriptionStatus.issued,
          diagnosis: 'Hypertension, type 2 diabetes — ongoing management',
          advice: 'Check blood pressure weekly and bring the readings to your '
              'next review. Reduce added salt.',
          appointmentReference: 'MD-2B6V8X',
          items: const [
            PrescriptionItem(
              drugName: 'Amlodipine',
              genericName: 'Amlodipine besylate',
              strength: '5 mg',
              form: 'Tablet',
              frequency: '1-0-0',
              durationDays: 30,
              instructions: 'Take in the morning.',
            ),
            PrescriptionItem(
              drugName: 'Metformin',
              genericName: 'Metformin hydrochloride',
              strength: '500 mg',
              form: 'Tablet',
              frequency: '1-0-1',
              durationDays: 30,
              instructions: 'After food.',
            ),
            // Deliberately weekly. The schedule parser refuses every interval
            // that is not daily, so this one renders under "follow your
            // doctor's instructions" with the doctor's own words and no
            // reminders — which is the behaviour worth demonstrating, because
            // 60,000 IU taken every morning instead of every Sunday is an
            // overdose the app would have invented.
            PrescriptionItem(
              drugName: 'Cholecalciferol',
              genericName: 'Vitamin D3',
              strength: '60000 IU',
              form: 'Sachet',
              frequency: 'Once weekly',
              durationDays: 28,
              instructions: 'One sachet on Sunday, with milk.',
            ),
          ],
        ),
      ];

  /// Where the sample account is signed in.
  ///
  /// Three, deliberately: one current, one recent, and one untouched for a
  /// month. A device list with a single row cannot show the control it exists
  /// for, and the stale entry is the one a person is meant to look at twice.
  static List<SignedInDevice> devices() => [
        SignedInDevice(
          id: 'sess-current',
          platform: 'android',
          appVersion: '1.0.0',
          createdAt: at(-30, 9, 12),
          lastSeenAt: DateTime.now(),
          isCurrent: true,
        ),
        SignedInDevice(
          id: 'sess-tablet',
          platform: 'ios',
          appVersion: '1.0.0',
          createdAt: at(-12, 20, 5),
          lastSeenAt: at(-2, 21, 40),
          isCurrent: false,
        ),
        SignedInDevice(
          id: 'sess-browser',
          platform: 'web',
          appVersion: '1.0.0',
          createdAt: at(-40, 14, 0),
          lastSeenAt: at(-31, 14, 2),
          isCurrent: false,
        ),
      ];

  // --- consent -------------------------------------------------------------

  static List<RecordAccessGrant> grants() => [
        RecordAccessGrant(
          id: 'g1',
          providerId: 'd1',
          providerName: 'Dr Anjali Rao',
          providerSpecialty: 'Cardiology',
          scopeKind: ConsentScopeKind.recordTypes,
          purpose: ConsentPurpose.consultation,
          grantedAt: at(-6, 9, 0),
          // Close enough that the countdown is visible on screen.
          expiresAt: _now().add(const Duration(days: 3, hours: 4)),
          recordTypeLabels: const ['Lab report', 'X-ray'],
          appointmentReference: 'MD-7K2P4Q',
          usesCount: 2,
        ),
        RecordAccessGrant(
          id: 'g2',
          providerId: 'd3',
          providerName: 'Dr Meera Iyer',
          providerSpecialty: 'Dermatology',
          scopeKind: ConsentScopeKind.specificRecords,
          purpose: ConsentPurpose.continuityOfCare,
          grantedAt: at(-9, 15, 30),
          expiresAt: _now().add(const Duration(days: 51)),
          recordIds: const ['r1'],
          appointmentReference: 'MD-9L5N1T',
          usesCount: 1,
        ),
        // Already revoked, so the log has something to show.
        RecordAccessGrant(
          id: 'g3',
          providerId: 'd4',
          providerName: 'Dr Vikram Nair',
          providerSpecialty: 'Orthopaedics',
          scopeKind: ConsentScopeKind.allRecords,
          purpose: ConsentPurpose.secondOpinion,
          grantedAt: at(-40, 12, 0),
          expiresAt: _now().add(const Duration(days: 20)),
          revokedAt: at(-31, 18, 0),
          usesCount: 4,
        ),
      ];

  static List<RecordAccessRequest> requests() => [
        RecordAccessRequest(
          id: 'q1',
          providerId: 'd2',
          providerName: 'Dr Rajesh Kumar',
          providerSpecialty: 'General Physician',
          purpose: ConsentPurpose.consultation,
          requestedAt: _now().subtract(const Duration(hours: 5)),
          expiresAt: _now().add(const Duration(hours: 67)),
          status: AccessRequestStatus.pending,
          message: 'I would like to see your recent blood work before we '
              'talk on Thursday.',
          appointmentReference: 'MD-2B6V8X',
        ),
      ];

  static List<RecordAccessEvent> accessLog() => [
        RecordAccessEvent(
          id: 'ev1',
          actorName: 'Dr Anjali Rao',
          recordTitle: 'Complete Blood Count',
          action: AccessAction.view,
          purpose: ConsentPurpose.consultation,
          at: _now().subtract(const Duration(hours: 20)),
        ),
        RecordAccessEvent(
          id: 'ev2',
          actorName: 'Dr Anjali Rao',
          recordTitle: '2 record(s)',
          action: AccessAction.viewMetadata,
          purpose: ConsentPurpose.consultation,
          at: _now().subtract(const Duration(hours: 20, minutes: 2)),
        ),
        // A denial, because the log records attempts as deliberately as reads.
        RecordAccessEvent(
          id: 'ev3',
          actorName: 'Dr Vikram Nair',
          recordTitle: 'Thyroid Profile',
          action: AccessAction.denied,
          at: _now().subtract(const Duration(days: 30)),
        ),
        RecordAccessEvent(
          id: 'ev4',
          actorName: 'Dr Meera Iyer',
          recordTitle: 'Complete Blood Count',
          action: AccessAction.download,
          purpose: ConsentPurpose.continuityOfCare,
          at: at(-9, 16, 10),
        ),
      ];

  // --- notifications -------------------------------------------------------

  /// A short history, so the notification centre has something to render on a
  /// fresh install and the read/unread split is visible without waiting for an
  /// event to fire.
  ///
  /// Every body here is deliberately free of clinical detail — these strings
  /// are what a lock screen would show.
  static List<AppNotification> notifications() {
    final now = _now();
    return [
      AppNotification(
        id: 'n-seed-1',
        kind: NotificationKind.consentRequested,
        title: 'A doctor asked to see your records',
        body: 'Dr Vikram Mehta · tap to review',
        createdAt: now.subtract(const Duration(hours: 5)),
        targetId: 'req1',
      ),
      AppNotification(
        id: 'n-seed-2',
        kind: NotificationKind.prescriptionIssued,
        title: 'Prescription ready',
        body: 'From your consultation with Dr Anjali Rao',
        createdAt: now.subtract(const Duration(days: 1)),
        readAt: now.subtract(const Duration(hours: 20)),
        targetId: 'rx1',
      ),
      AppNotification(
        id: 'n-seed-3',
        kind: NotificationKind.ratingRequested,
        title: 'How was your consultation?',
        body: 'Rate it to help other patients choose.',
        createdAt: now.subtract(const Duration(days: 3)),
        readAt: now.subtract(const Duration(days: 2)),
        targetId: 'a2',
      ),
    ];
  }

  // --- ratings -------------------------------------------------------------

  static List<Rating> ratings() => [
        Rating(
          id: 'rt1',
          appointmentId: 'a3',
          doctorName: 'Dr Meera Iyer',
          stars: 5,
          createdAt: at(-8, 9, 0),
          status: RatingStatus.published,
          comment:
              'Explained everything clearly and did not rush the appointment.',
        ),
        // Awaiting moderation, so the console's queue is not empty on first run.
        Rating(
          id: 'rt2',
          appointmentId: 'a-seed-old',
          doctorName: 'Dr Rajesh Kumar',
          stars: 4,
          createdAt: _now().subtract(const Duration(hours: 6)),
          status: RatingStatus.pendingModeration,
          comment: 'Good consultation, though the call dropped once.',
        ),
      ];

  // --- support -------------------------------------------------------------

  static List<SupportTicket> tickets() => [
        SupportTicket(
          id: 't1',
          reference: 'SUP-4471',
          subject: 'Could not join my video consultation',
          category: TicketCategory.bookingProblem,
          status: TicketStatus.assigned,
          createdAt: _now().subtract(const Duration(days: 2)),
          updatedAt: _now().subtract(const Duration(hours: 20)),
          messages: [
            TicketMessage(
              id: 'tm1',
              body: 'The Join button did nothing on Tuesday at 4pm. I waited '
                  'ten minutes and then the appointment was over.',
              sentAt: _now().subtract(const Duration(days: 2)),
              isFromSupport: false,
              authorName: 'Priya Sharma',
            ),
            TicketMessage(
              id: 'tm2',
              body: 'Sorry about that. We can see the consultation did not '
                  'connect from our side either, and the doctor has been '
                  'asked to reschedule at no charge.',
              sentAt: _now().subtract(const Duration(hours: 20)),
              isFromSupport: true,
              authorName: 'MiDoctor Support',
            ),
          ],
        ),
        SupportTicket(
          id: 't2',
          reference: 'SUP-4520',
          subject: 'Wrong blood group on my profile',
          category: TicketCategory.recordsProblem,
          status: TicketStatus.open,
          createdAt: _now().subtract(const Duration(hours: 3)),
          updatedAt: _now().subtract(const Duration(hours: 3)),
          messages: [
            TicketMessage(
              id: 'tm3',
              body: 'My profile says O+ but my report says O-. How do I get '
                  'this corrected?',
              sentAt: _now().subtract(const Duration(hours: 3)),
              isFromSupport: false,
              authorName: 'Priya Sharma',
            ),
          ],
        ),
      ];

  // --- availability (provider persona) -------------------------------------

  static List<AvailabilityRule> availabilityRules() => const [
        AvailabilityRule(
          id: 'ar1',
          weekday: DateTime.monday,
          start: TimeOfDayValue(9, 0),
          end: TimeOfDayValue(13, 0),
          mode: ConsultationMode.video,
          slotMinutes: 30,
        ),
        AvailabilityRule(
          id: 'ar2',
          weekday: DateTime.monday,
          start: TimeOfDayValue(17, 0),
          end: TimeOfDayValue(20, 0),
          mode: ConsultationMode.inPerson,
          slotMinutes: 20,
        ),
        AvailabilityRule(
          id: 'ar3',
          weekday: DateTime.wednesday,
          start: TimeOfDayValue(10, 0),
          end: TimeOfDayValue(14, 0),
          mode: ConsultationMode.video,
          slotMinutes: 30,
        ),
        AvailabilityRule(
          id: 'ar4',
          weekday: DateTime.friday,
          start: TimeOfDayValue(9, 30),
          end: TimeOfDayValue(12, 30),
          mode: ConsultationMode.video,
          slotMinutes: 15,
          isActive: false,
        ),
      ];

  // --- provider verification -----------------------------------------------

  /// A part-finished checklist, so the provider flow has somewhere to go.
  ///
  /// Two documents in, no registration number, no MFA — which means the submit
  /// button is correctly disabled on first run and becomes enabled as the user
  /// works through it. A fully complete checklist would demo nothing.
  static VerificationChecklist checklist() => VerificationChecklist(
        credentials: [
          ProviderCredential(
            kind: CredentialKind.degreeCertificate,
            status: CredentialReviewStatus.submitted,
            fileName: 'mbbs-degree.pdf',
            uploadedAt: _now().subtract(const Duration(days: 1)),
          ),
          ProviderCredential(
            kind: CredentialKind.medicalRegistration,
            status: CredentialReviewStatus.submitted,
            fileName: 'nmc-registration.pdf',
            uploadedAt: _now().subtract(const Duration(days: 1)),
          ),
          const ProviderCredential(
            kind: CredentialKind.identityProof,
            status: CredentialReviewStatus.notSubmitted,
          ),
          const ProviderCredential(
            kind: CredentialKind.hospitalAffiliation,
            status: CredentialReviewStatus.notSubmitted,
          ),
        ],
        registrationNumber: null,
        mfaEnrolled: false,
      );

  /// Applications already waiting in the operator console.
  ///
  /// One ready to approve and one needing a document rejected, so both halves
  /// of the reviewer's job are reachable without first submitting from a phone.
  static List<ProviderApplicationRecord> applications() => [
        ProviderApplicationRecord(
          userId: 'u-dr-sunita',
          displayName: 'Dr Sunita Menon',
          email: 'sunita.menon@example.com',
          phone: '+91 99001 22334',
          registrationNumber: 'KMC-58210',
          mfaEnrolled: true,
          status: ProviderApplicationStatus.submitted,
          submittedAt: _now().subtract(const Duration(days: 2)),
          documents: [
            ProviderApplicationDocument(
              id: 'u-dr-sunita-DEGREE_CERTIFICATE',
              kind: CredentialKind.degreeCertificate,
              status: CredentialReviewStatus.submitted,
              fileName: 'mbbs-md-degree.pdf',
              uploadedAt: _now().subtract(const Duration(days: 2)),
            ),
            ProviderApplicationDocument(
              id: 'u-dr-sunita-MEDICAL_REGISTRATION',
              kind: CredentialKind.medicalRegistration,
              status: CredentialReviewStatus.submitted,
              fileName: 'kmc-certificate.pdf',
              uploadedAt: _now().subtract(const Duration(days: 2)),
            ),
            ProviderApplicationDocument(
              id: 'u-dr-sunita-IDENTITY_PROOF',
              kind: CredentialKind.identityProof,
              status: CredentialReviewStatus.submitted,
              fileName: 'digilocker-verified',
              uploadedAt: _now().subtract(const Duration(days: 2)),
            ),
            ProviderApplicationDocument(
              id: 'u-dr-sunita-HOSPITAL_AFFILIATION',
              kind: CredentialKind.hospitalAffiliation,
              status: CredentialReviewStatus.submitted,
              fileName: 'affiliation-letter.pdf',
              uploadedAt: _now().subtract(const Duration(days: 2)),
            ),
          ],
        ),
        ProviderApplicationRecord(
          userId: 'u-dr-arun',
          displayName: 'Dr Arun Prakash',
          email: 'arun.prakash@example.com',
          phone: '+91 98220 11445',
          registrationNumber: 'TSMC-31889',
          mfaEnrolled: true,
          status: ProviderApplicationStatus.underReview,
          submittedAt: _now().subtract(const Duration(days: 5)),
          documents: [
            ProviderApplicationDocument(
              id: 'u-dr-arun-DEGREE_CERTIFICATE',
              kind: CredentialKind.degreeCertificate,
              status: CredentialReviewStatus.accepted,
              fileName: 'degree.pdf',
              uploadedAt: _now().subtract(const Duration(days: 5)),
            ),
            ProviderApplicationDocument(
              id: 'u-dr-arun-MEDICAL_REGISTRATION',
              kind: CredentialKind.medicalRegistration,
              status: CredentialReviewStatus.submitted,
              fileName: 'registration-scan.jpg',
              uploadedAt: _now().subtract(const Duration(days: 5)),
            ),
            ProviderApplicationDocument(
              id: 'u-dr-arun-IDENTITY_PROOF',
              kind: CredentialKind.identityProof,
              status: CredentialReviewStatus.accepted,
              fileName: 'digilocker-verified',
              uploadedAt: _now().subtract(const Duration(days: 5)),
            ),
            ProviderApplicationDocument(
              id: 'u-dr-arun-HOSPITAL_AFFILIATION',
              kind: CredentialKind.hospitalAffiliation,
              status: CredentialReviewStatus.rejected,
              fileName: 'letter.jpg',
              uploadedAt: _now().subtract(const Duration(days: 5)),
              reasonCode: RejectionReasonCode.docIllegible,
              reviewerNote: 'The letterhead is cut off. Please rescan the '
                  'whole page.',
            ),
          ],
        ),
      ];
}
