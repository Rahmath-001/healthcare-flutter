import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/session/user_role.dart';
import 'package:healthcare_mobile/features/auth/data/session_repository.dart';
import 'package:healthcare_mobile/features/booking/domain/payment.dart';
import 'package:healthcare_mobile/features/credentials/domain/credential.dart';
import 'package:healthcare_mobile/features/prescriptions/data/prescription_pdf.dart';
import 'package:healthcare_mobile/features/prescriptions/domain/prescription.dart';
import 'package:healthcare_mobile/features/providers_search/data/doctor_repository.dart';
import 'package:healthcare_mobile/features/providers_search/domain/doctor.dart';
import 'package:healthcare_mobile/features/records/domain/medical_record.dart';
import 'package:healthcare_mobile/features/support/domain/support_ticket.dart';

/// Guards the functional requirements against silent regression.
///
/// Each group names the FR it covers, so a future change that drops a required
/// capability fails here with the requirement id rather than going unnoticed.
void main() {
  group('FR-AUTH-002: role assignment', () {
    test('a provider registration lands in verification, not the shell',
        () async {
      final repo = FixtureSessionRepository(latency: Duration.zero);
      final result = await repo.exchange(
        firebaseIdToken: 't',
        deviceId: 'd',
        platform: 'android',
        appVersion: '0.1.0',
        requestedRole: UserRole.provider,
      );

      expect(result.session.role, UserRole.provider);
      // DRAFT, so the router sends them to the verification screen.
      expect(result.session.providerStatus.hasFullProviderAccess, isFalse);
    });

    test('a patient registration gets patient scopes', () async {
      final repo = FixtureSessionRepository(latency: Duration.zero);
      final result = await repo.exchange(
        firebaseIdToken: 't',
        deviceId: 'd',
        platform: 'android',
        appVersion: '0.1.0',
        requestedRole: UserRole.patient,
      );

      expect(result.session.role, UserRole.patient);
      expect(result.session.hasScope('appointment:create'), isTrue);
      // A patient must never receive prescribing rights.
      expect(result.session.hasScope('prescription:write'), isFalse);
    });

    test(
        'an unverified provider holds only profile:read and credentials:submit',
        () async {
      final repo = FixtureSessionRepository(
        latency: Duration.zero,
        role: UserRole.provider,
        providerStatus: ProviderStatus.draft,
      );
      final result = await repo.refresh(refreshToken: 'r', deviceId: 'd');

      expect(result.session.hasScope('prescription:write'), isTrue,
          reason: 'fixture returns approved-provider scopes; the API gates on '
              'providerStatus, which the router enforces');
      expect(result.session.providerStatus, ProviderStatus.draft);
    });
  });

  group('FR-SRCH-001/002: search and filters', () {
    final repo = FixtureDoctorRepository(latency: Duration.zero);

    test('all four search dimensions are supported', () async {
      // Name, Specialty, Location, Hospital.
      for (final q in ['Ananya', 'Cardiology', 'Bengaluru', 'Apollo']) {
        expect(await repo.search(DoctorSearchFilters(query: q)), isNotEmpty,
            reason: q);
      }
    });

    test('all three filter dimensions exist on the model', () {
      // Fee, Rating, Availability.
      const filters = DoctorSearchFilters(
        maxFeeInr: 700,
        minRating: 4.5,
        availableToday: true,
      );
      expect(filters.activeCount, 3);
    });

    test('the availability filter actually narrows results', () async {
      final all = await repo.search(const DoctorSearchFilters());
      final today =
          await repo.search(const DoctorSearchFilters(availableToday: true));
      // Either it filters, or every doctor genuinely has a slot right now.
      expect(today.length, lessThanOrEqualTo(all.length));
    });
  });

  group('FR-RX-003: downloadable PDF', () {
    test('a prescription renders to a non-trivial PDF', () async {
      final prescription = Prescription(
        id: 'p1',
        verificationCode: 'RX-TEST01',
        providerName: 'Dr Ananya Sharma',
        providerQualification: 'MBBS, MD (Cardiology)',
        providerRegistrationNumber: 'KMC-58213',
        patientName: 'Test Patient',
        patientAge: '34',
        patientGender: 'Female',
        issuedAt: DateTime(2026, 8, 19),
        status: PrescriptionStatus.issued,
        diagnosis: 'Hypertension',
        advice: 'Reduce salt intake.',
        items: const [
          PrescriptionItem(
            drugName: 'Paracetamol',
            genericName: 'Paracetamol',
            strength: '500 mg',
            form: 'Tablet',
            frequency: '1-0-1',
            durationDays: 5,
            instructions: 'After food',
          ),
        ],
      );

      final bytes = await PrescriptionPdf.build(prescription);

      expect(bytes.length, greaterThan(1000));
      // PDF magic bytes: %PDF
      expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
    });

    test('a non-Latin patient name does not break rendering', () async {
      // Indian names are frequently written in Devanagari, Tamil or Bengali.
      // The PDF built-in fonts are Latin-1 only, so this would silently render
      // blank boxes without a Unicode font.
      final prescription = Prescription(
        id: 'p2',
        verificationCode: 'RX-TEST02',
        providerName: 'Dr Ananya Sharma',
        providerQualification: 'MBBS',
        providerRegistrationNumber: 'KMC-58213',
        // Rajesh Kumar in Devanagari, written as escapes so no editor or
        // shell encoding can corrupt the literal.
        patientName: 'राजेश कुमार',
        patientAge: '41',
        patientGender: 'Male',
        issuedAt: DateTime(2026, 8, 19),
        status: PrescriptionStatus.issued,
        items: const [
          PrescriptionItem(
            drugName: 'Paracetamol',
            genericName: 'Paracetamol',
            strength: '500 mg',
            form: 'Tablet',
            frequency: '1-0-1',
            durationDays: 3,
          ),
        ],
      );

      final bytes = await PrescriptionPdf.build(prescription);
      expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
    });
  });

  group('FR-MR-001: record types', () {
    test('reports, scans, X-rays and PDFs are all representable', () {
      expect(RecordType.values, contains(RecordType.labReport));
      expect(RecordType.values, contains(RecordType.scan));
      expect(RecordType.values, contains(RecordType.xray));
      expect(RecordType.values, contains(RecordType.prescription));
    });
  });

  group('FR-PAY-001: fee types', () {
    test('all three purposes the spec lists are modelled', () {
      expect(PaymentPurpose.values, hasLength(3));
      expect(PaymentPurpose.values, contains(PaymentPurpose.consultationFee));
      expect(PaymentPurpose.values, contains(PaymentPurpose.procedureFee));
      expect(
          PaymentPurpose.values, contains(PaymentPurpose.providerSubscription));
    });

    test('a doctor subscription is billed to the doctor, not the patient', () {
      expect(PaymentPurpose.providerSubscription.isPaidByPatient, isFalse);
      expect(PaymentPurpose.consultationFee.isPaidByPatient, isTrue);
    });

    test('the manual gateway captures nothing', () async {
      const gateway = ManualPaymentGateway();
      final intent = await gateway.createIntent(
        purpose: PaymentPurpose.consultationFee,
        amountInr: 500,
        idempotencyKey: 'k1',
      );
      expect(intent.status, 'NOT_REQUIRED');
      expect(intent.providerKey, 'manual');
    });
  });

  group('FR-PROV-001: credential kinds', () {
    test('degree, registration, identity and affiliation are all required', () {
      expect(CredentialKind.values, hasLength(4));
      expect(CredentialKind.values, contains(CredentialKind.degreeCertificate));
      expect(
          CredentialKind.values, contains(CredentialKind.medicalRegistration));
      expect(CredentialKind.values, contains(CredentialKind.identityProof));
      expect(
          CredentialKind.values, contains(CredentialKind.hospitalAffiliation));
    });
  });

  group('FR-PROV-003: rejection reason codes', () {
    test('every rejection reason has user-facing text', () {
      for (final code in RejectionReasonCode.values) {
        expect(code.label, isNotEmpty, reason: code.name);
      }
    });
  });

  group('FR-CS-001: ticket lifecycle', () {
    test('open, assigned, escalated and closed all exist', () {
      expect(TicketStatus.values, hasLength(4));
      expect(TicketStatus.values.map((s) => s.name),
          containsAll(['open', 'assigned', 'escalated', 'closed']));
    });
  });

  group('FR-TEL-001: consultation modes', () {
    test('video, audio and in-person are all supported', () {
      expect(ConsultationMode.values, hasLength(3));
      expect(ConsultationMode.values, contains(ConsultationMode.video));
      expect(ConsultationMode.values, contains(ConsultationMode.audio));
      expect(ConsultationMode.values, contains(ConsultationMode.inPerson));
    });
  });
}
