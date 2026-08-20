import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/features/appointments/domain/appointment.dart';
import 'package:healthcare_mobile/features/consent/domain/consent.dart';
import 'package:healthcare_mobile/features/credentials/domain/credential.dart';
import 'package:healthcare_mobile/features/prescriptions/domain/prescription.dart';
import 'package:healthcare_mobile/features/providers_search/data/doctor_fixtures.dart';
import 'package:healthcare_mobile/features/providers_search/domain/doctor.dart';
import 'package:healthcare_mobile/features/ratings/domain/rating.dart';

/// Rules that carry legal or safety weight. These are the checks that stop the
/// product doing something it must not do, so they are tested directly rather
/// than through a screen.
void main() {
  group('telemedicine drug lists (MoHFW guidelines)', () {
    const otc = Drug(
      id: '1',
      name: 'Paracetamol',
      genericName: 'Paracetamol',
      form: 'Tablet',
      telemedicineList: TelemedicineDrugList.listO,
    );
    const listA = Drug(
      id: '2',
      name: 'Amoxicillin',
      genericName: 'Amoxicillin',
      form: 'Capsule',
      telemedicineList: TelemedicineDrugList.listA,
    );
    const listB = Drug(
      id: '3',
      name: 'Metformin',
      genericName: 'Metformin',
      form: 'Tablet',
      telemedicineList: TelemedicineDrugList.listB,
    );
    const prohibited = Drug(
      id: '4',
      name: 'Alprazolam',
      genericName: 'Alprazolam',
      form: 'Tablet',
      telemedicineList: TelemedicineDrugList.prohibited,
    );

    test('OTC and List A are prescribable on a first consultation', () {
      expect(otc.isPrescribableOn(isFollowUp: false), isTrue);
      expect(listA.isPrescribableOn(isFollowUp: false), isTrue);
    });

    test('List B is refill-only: blocked on first, allowed on follow-up', () {
      expect(listB.isPrescribableOn(isFollowUp: false), isFalse);
      expect(listB.isPrescribableOn(isFollowUp: true), isTrue);
    });

    test('prohibited drugs are never prescribable, follow-up or not', () {
      // Schedule X, narcotics and psychotropics. There is no path to yes.
      expect(prohibited.isPrescribableOn(isFollowUp: false), isFalse);
      expect(prohibited.isPrescribableOn(isFollowUp: true), isFalse);
    });

    test('a blocked drug always explains why', () {
      expect(prohibited.blockedReason(isFollowUp: true), isNotNull);
      expect(listB.blockedReason(isFollowUp: false), contains('follow-up'));
      expect(otc.blockedReason(isFollowUp: false), isNull);
    });
  });

  group('consent grants', () {
    RecordAccessGrant grant({
      DateTime? expiresAt,
      DateTime? revokedAt,
    }) =>
        RecordAccessGrant(
          id: 'g',
          providerId: 'p',
          providerName: 'Dr X',
          providerSpecialty: 'GP',
          scopeKind: ConsentScopeKind.allRecords,
          purpose: ConsentPurpose.consultation,
          grantedAt: DateTime.now().subtract(const Duration(hours: 1)),
          expiresAt: expiresAt ?? DateTime.now().add(const Duration(days: 1)),
          revokedAt: revokedAt,
        );

    test('a live grant is active', () {
      expect(grant().isActive, isTrue);
    });

    test('an expired grant is not active', () {
      expect(
        grant(expiresAt: DateTime.now().subtract(const Duration(minutes: 1)))
            .isActive,
        isFalse,
      );
    });

    test('a revoked grant is not active even before it expires', () {
      // Revocation must beat the clock, otherwise "stop sharing" would only
      // take effect at expiry.
      expect(grant(revokedAt: DateTime.now()).isActive, isFalse);
    });

    test('remaining time never goes negative', () {
      expect(
        grant(expiresAt: DateTime.now().subtract(const Duration(days: 5)))
            .remaining,
        Duration.zero,
      );
    });

    test('every offered duration is finite and within the 180-day ceiling', () {
      for (final d in ConsentDuration.values) {
        expect(d.duration, greaterThan(Duration.zero), reason: d.name);
        expect(d.duration, lessThanOrEqualTo(const Duration(days: 180)),
            reason: d.name);
      }
    });
  });

  group('appointment rules', () {
    Appointment appointment({
      required DateTime start,
      AppointmentStatus status = AppointmentStatus.confirmed,
      ConsultationMode mode = ConsultationMode.video,
      bool hasRating = false,
    }) =>
        Appointment(
          id: 'a',
          referenceCode: 'MD-TEST',
          doctor: DoctorFixtures.all.first,
          patientName: 'You',
          start: start,
          end: start.add(const Duration(minutes: 30)),
          mode: mode,
          status: status,
          paymentStatus: PaymentStatus.notRequired,
          feeInr: 500,
          consultationId: 'c',
          hasRating: hasRating,
        );

    test('an upcoming appointment can be cancelled', () {
      expect(
        appointment(start: DateTime.now().add(const Duration(days: 2)))
            .canCancel,
        isTrue,
      );
    });

    test('a past or cancelled appointment cannot be cancelled', () {
      expect(
        appointment(
          start: DateTime.now().subtract(const Duration(days: 1)),
          status: AppointmentStatus.completed,
        ).canCancel,
        isFalse,
      );
      expect(
        appointment(
          start: DateTime.now().add(const Duration(days: 1)),
          status: AppointmentStatus.cancelledByPatient,
        ).canCancel,
        isFalse,
      );
    });

    test('free cancellation applies only beyond 24 hours', () {
      expect(
        appointment(start: DateTime.now().add(const Duration(hours: 30)))
            .isFreeCancellation,
        isTrue,
      );
      expect(
        appointment(start: DateTime.now().add(const Duration(hours: 5)))
            .isFreeCancellation,
        isFalse,
      );
    });

    group('consultation join window', () {
      test('opens 15 minutes before the start', () {
        expect(
          appointment(start: DateTime.now().add(const Duration(minutes: 10)))
              .canJoinConsultation,
          isTrue,
        );
        expect(
          appointment(start: DateTime.now().add(const Duration(minutes: 45)))
              .canJoinConsultation,
          isFalse,
        );
      });

      test('closes 30 minutes after the scheduled end', () {
        // Started 20 min ago, so ended 10 min ago: still joinable.
        expect(
          appointment(
                  start: DateTime.now().subtract(const Duration(minutes: 20)))
              .canJoinConsultation,
          isTrue,
        );
        // Ended well over 30 minutes ago.
        expect(
          appointment(start: DateTime.now().subtract(const Duration(hours: 2)))
              .canJoinConsultation,
          isFalse,
        );
      });

      test('an in-person appointment is never joinable', () {
        expect(
          appointment(
            start: DateTime.now(),
            mode: ConsultationMode.inPerson,
          ).canJoinConsultation,
          isFalse,
        );
      });
    });

    test('only a completed, unrated appointment can be rated', () {
      expect(
        appointment(
          start: DateTime.now().subtract(const Duration(days: 1)),
          status: AppointmentStatus.completed,
        ).canRate,
        isTrue,
      );
      expect(
        appointment(
          start: DateTime.now().subtract(const Duration(days: 1)),
          status: AppointmentStatus.completed,
          hasRating: true,
        ).canRate,
        isFalse,
      );
      expect(
        appointment(start: DateTime.now().add(const Duration(days: 1))).canRate,
        isFalse,
      );
    });
  });

  group('slot holds', () {
    test('a fresh hold is not expired and counts down', () {
      final hold = SlotHold(
        slotId: 's',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
      expect(hold.isExpired, isFalse);
      expect(hold.remaining.inMinutes, greaterThan(8));
    });

    test('a lapsed hold is expired and reports zero remaining', () {
      final hold = SlotHold(
        slotId: 's',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(hold.isExpired, isTrue);
      expect(hold.remaining, Duration.zero);
    });
  });

  group('provider verification gate', () {
    List<ProviderCredential> allProvided() => CredentialKind.values
        .map((k) => ProviderCredential(
              kind: k,
              status: CredentialReviewStatus.submitted,
            ))
        .toList();

    test('all three gates are required before submission', () {
      expect(
        VerificationChecklist(
          credentials: allProvided(),
          registrationNumber: 'KMC-123',
          mfaEnrolled: true,
        ).canSubmit,
        isTrue,
      );
    });

    test('MFA alone blocks submission', () {
      // An approved provider can prescribe and read records, so the account
      // must be protected before it gains those powers.
      expect(
        VerificationChecklist(
          credentials: allProvided(),
          registrationNumber: 'KMC-123',
          mfaEnrolled: false,
        ).canSubmit,
        isFalse,
      );
    });

    test('a missing registration number blocks submission', () {
      expect(
        VerificationChecklist(
          credentials: allProvided(),
          registrationNumber: '   ',
          mfaEnrolled: true,
        ).canSubmit,
        isFalse,
      );
    });

    test('a rejected document counts as not provided', () {
      final credentials = allProvided();
      credentials[0] = const ProviderCredential(
        kind: CredentialKind.degreeCertificate,
        status: CredentialReviewStatus.rejected,
        reasonCode: RejectionReasonCode.docIllegible,
      );
      expect(
        VerificationChecklist(
          credentials: credentials,
          registrationNumber: 'KMC-123',
          mfaEnrolled: true,
        ).canSubmit,
        isFalse,
      );
    });

    test('there is no Aadhaar credential kind', () {
      // Storing Aadhaar images is a legal liability; identity is proven via
      // DigiLocker instead.
      expect(
        CredentialKind.values
            .any((k) => k.name.toLowerCase().contains('aadhaar')),
        isFalse,
      );
      expect(CredentialKind.identityProof.isDigiLocker, isTrue);
    });
  });

  group('ratings', () {
    Rating rating(DateTime createdAt) => Rating(
          id: 'r',
          appointmentId: 'a',
          doctorName: 'Dr X',
          stars: 5,
          createdAt: createdAt,
          status: RatingStatus.published,
        );

    test('editable within 14 days, not after', () {
      expect(
        rating(DateTime.now().subtract(const Duration(days: 13))).canEdit,
        isTrue,
      );
      expect(
        rating(DateTime.now().subtract(const Duration(days: 15))).canEdit,
        isFalse,
      );
    });

    test('a removed rating cannot be edited even inside the window', () {
      final removed = Rating(
        id: 'r',
        appointmentId: 'a',
        doctorName: 'Dr X',
        stars: 1,
        createdAt: DateTime.now(),
        status: RatingStatus.removed,
      );
      expect(removed.canEdit, isFalse);
    });
  });
}
