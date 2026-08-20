import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/error/failure.dart';
import 'package:healthcare_mobile/core/files/blob_client.dart';
import 'package:healthcare_mobile/core/files/file_picker_service.dart';
import 'package:healthcare_mobile/core/network/api_client.dart';
import 'package:healthcare_mobile/features/appointments/data/api_appointment_repository.dart';
import 'package:healthcare_mobile/features/availability/data/api_availability_repository.dart';
import 'package:healthcare_mobile/features/availability/domain/availability.dart';
import 'package:healthcare_mobile/features/prescriptions/data/api_prescription_repository.dart';
import 'package:healthcare_mobile/features/prescriptions/domain/prescription.dart';
import 'package:healthcare_mobile/features/providers_search/data/api_doctor_repository.dart';
import 'package:healthcare_mobile/features/providers_search/domain/doctor.dart';
import 'package:healthcare_mobile/features/ratings/data/api_ratings_repository.dart';
import 'package:healthcare_mobile/features/ratings/domain/rating.dart';
import 'package:healthcare_mobile/features/records/data/api_records_repository.dart';
import 'package:healthcare_mobile/features/records/domain/medical_record.dart';
import 'package:healthcare_mobile/features/support/data/api_support_repository.dart';
import 'package:healthcare_mobile/features/support/domain/support_ticket.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// The `USE_FIXTURES=false` path.
///
/// Every one of these classes is what runs against a real server, and none of
/// them had a test: the fixtures were covered thoroughly and the code that
/// actually talks to the API was not. What matters here is the wire contract —
/// paths, request shapes, and the enum mapping in both directions — because a
/// mismatch there is invisible until it is in front of a patient.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ApiClient api;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    adapter = DioAdapter(dio: dio);
    api = ApiClient(dio: dio);
  });

  group('ApiDoctorRepository', () {
    test('omits filters that are not set', () async {
      // An unset filter must be absent, not sent as null: the server treats a
      // present key as a constraint. The adapter only matches this exact query,
      // so an extra key makes the call fail to match and the test fail.
      adapter.onGet(
        '/v1/doctors',
        (server) => server.reply(200, {'items': <Object>[]}),
        queryParameters: {'specialtyCode': 'CARD', 'city': 'Bengaluru'},
      );

      final doctors = await ApiDoctorRepository(api).search(
        const DoctorSearchFilters(specialtyCode: 'CARD', city: 'Bengaluru'),
      );
      expect(doctors, isEmpty);
    });

    test('parses a doctor out of the items envelope', () async {
      adapter.onGet(
        '/v1/doctors',
        (server) => server.reply(200, {
          'items': [
            {
              'id': 'd1',
              'name': 'Dr Anjali Rao',
              'specialties': [
                {'code': 'CARD', 'name': 'Cardiology'}
              ],
              'qualification': 'MBBS, MD',
              'registrationNumber': 'KMC-12345',
              'yearsExperience': 12,
              'consultationFeeInr': 800,
              'videoFeeInr': 600,
              'rating': 4.7,
              'ratingCount': 210,
              'hospital': {'id': 'h1', 'name': 'Apollo', 'city': 'Bengaluru'},
              'languages': ['English'],
              'modes': ['VIDEO', 'IN_PERSON'],
            }
          ]
        }),
        queryParameters: {},
      );

      final doctors =
          await ApiDoctorRepository(api).search(const DoctorSearchFilters());
      expect(doctors, hasLength(1));
      expect(doctors.first.name, 'Dr Anjali Rao');
      // Surfaced to patients because the MoHFW guidelines require it visible.
      expect(doctors.first.registrationNumber, 'KMC-12345');
      expect(doctors.first.modes, contains(ConsultationMode.video));
    });
  });

  group('ApiRecordsRepository', () {
    test('upload creates metadata then PUTs the bytes to the signed URL',
        () async {
      adapter.onPost(
        '/v1/records',
        (server) => server.reply(201, {
          'record': _recordJson(scanStatus: 'PENDING'),
          'upload': {
            'url': 'https://storage.test/signed',
            'method': 'PUT',
            'expiresAt': '2030-01-01T00:00:00.000Z',
            'headers': {'Content-Type': 'image/jpeg'},
          },
        }),
        data: Matchers.any,
      );

      final blobDio = Dio();
      final blobAdapter = DioAdapter(dio: blobDio);
      blobAdapter.onPut(
        'https://storage.test/signed',
        (server) => server.reply(200, ''),
        data: Matchers.any,
      );

      final repo = ApiRecordsRepository(api, BlobClient(dio: blobDio));
      final record = await repo.upload(
        title: 'Blood test',
        type: RecordType.labReport,
        recordedAt: DateTime(2026, 1, 2),
        file:
            PickedFile(name: 'scan.jpg', bytes: Uint8List.fromList([1, 2, 3])),
      );

      // Pending, not readable: the bytes exist but nothing has inspected them.
      expect(record.scanStatus, ScanStatus.pending);
      expect(record.isReadable, isFalse);
    });

    test('an unknown scan status is treated as failed, never as readable',
        () async {
      adapter.onGet(
        '/v1/records',
        (server) => server.reply(200, [_recordJson(scanStatus: 'QUARANTINED')]),
      );

      final records =
          await ApiRecordsRepository(api, BlobClient(dio: Dio())).listOwn();
      expect(records.single.scanStatus, ScanStatus.failed);
      expect(records.single.isReadable, isFalse);
    });

    test('surfaces a consent refusal as a Failure, not an exception', () async {
      adapter.onGet(
        '/v1/records/granted/p1',
        (server) => server.reply(403, {
          'title': 'Forbidden',
          'status': 403,
          'detail': 'You do not have access to these records.',
          'code': 'NO_CONSENT',
        }),
      );

      final repo = ApiRecordsRepository(api, BlobClient(dio: Dio()));
      await expectLater(
        repo.listGranted('p1'),
        throwsA(isA<Failure>()
            .having((f) => f.kind, 'kind', FailureKind.forbidden)
            .having((f) => f.code, 'code', 'NO_CONSENT')),
      );
    });
  });

  group('ApiAvailabilityRepository', () {
    test('sends times as minutes past midnight, not clock strings', () async {
      adapter.onPost(
        '/v1/availability/rules',
        (server) => server.reply(201, {
          'id': 'r1',
          'weekday': 1,
          'startMinutes': 570,
          'endMinutes': 780,
          'mode': 'VIDEO',
          'slotMinutes': 30,
          'active': true,
        }),
        data: {
          'weekday': 1,
          'startMinutes': 570,
          'endMinutes': 780,
          'mode': 'VIDEO',
          'slotMinutes': 30,
        },
      );

      final rule = await ApiAvailabilityRepository(api).addRule(
        weekday: 1,
        start: const TimeOfDayValue(9, 30),
        end: const TimeOfDayValue(13, 0),
        mode: ConsultationMode.video,
        slotMinutes: 30,
      );

      expect(rule.start.hour, 9);
      expect(rule.start.minute, 30);
      expect(rule.slotCount, 7);
    });

    test('a blocked day is sent as a calendar date, not an instant', () async {
      adapter.onPost(
        '/v1/availability/exceptions',
        (server) => server.reply(201, {
          'id': 'e1',
          'date': '2026-03-05',
          'isBlocked': true,
          'startMinutes': null,
          'endMinutes': null,
          'reason': 'Conference',
        }),
        // 23:30 local must not become the 6th, or the wrong day is blocked.
        data: {'date': '2026-03-05', 'reason': 'Conference'},
      );

      final blocked = await ApiAvailabilityRepository(api)
          .blockDay(DateTime(2026, 3, 5, 23, 30), reason: 'Conference');

      expect(blocked.date, DateTime(2026, 3, 5));
      expect(blocked.isBlocked, isTrue);
    });
  });

  group('ApiRatingsRepository', () {
    test('never sends the doctor name — the server snapshots it', () async {
      adapter.onPost(
        '/v1/ratings',
        (server) => server.reply(201, {
          'id': 'a1',
          'appointmentId': 'a1',
          'doctorName': 'Dr Anjali Rao',
          'stars': 5,
          'createdAt': '2026-01-01T10:00:00.000Z',
          'status': 'PENDING_MODERATION',
          'comment': null,
          'editedAt': null,
        }),
        // Attribution is the server's to decide; a client-supplied name would
        // let a rating be pointed at someone else.
        data: {'appointmentId': 'a1', 'stars': 5},
      );

      final rating = await ApiRatingsRepository(api).submit(
        appointmentId: 'a1',
        doctorName: 'Someone Else',
        stars: 5,
      );

      expect(rating.doctorName, 'Dr Anjali Rao');
      expect(rating.status, RatingStatus.pendingModeration);
    });

    test('a duplicate rating surfaces as a conflict', () async {
      adapter.onPost(
        '/v1/ratings',
        (server) => server.reply(409, {
          'title': 'Conflict',
          'status': 409,
          'detail': 'You have already rated this consultation.',
          'code': 'ALREADY_RATED',
        }),
        data: Matchers.any,
      );

      await expectLater(
        ApiRatingsRepository(api)
            .submit(appointmentId: 'a1', doctorName: 'x', stars: 4),
        throwsA(
            isA<Failure>().having((f) => f.kind, 'kind', FailureKind.conflict)),
      );
    });
  });

  group('ApiSupportRepository', () {
    test('round-trips categories and statuses through their wire values',
        () async {
      adapter.onPost(
        '/v1/support/tickets',
        (server) => server.reply(201, {
          'id': 't1',
          'reference': 'SUP-ABC123',
          'subject': 'Cannot join',
          'category': 'BOOKING_PROBLEM',
          'status': 'OPEN',
          'createdAt': '2026-01-01T10:00:00.000Z',
          'updatedAt': '2026-01-01T10:00:00.000Z',
          'messages': [
            {
              'id': 'm1',
              'body': 'The button does nothing.',
              'authorName': 'Priya',
              'fromSupport': false,
              'at': '2026-01-01T10:00:00.000Z',
            }
          ],
        }),
        data: {
          'subject': 'Cannot join',
          'category': 'BOOKING_PROBLEM',
          'body': 'The button does nothing.',
        },
      );

      final ticket = await ApiSupportRepository(api).create(
        subject: 'Cannot join',
        category: TicketCategory.bookingProblem,
        body: 'The button does nothing.',
      );

      expect(ticket.reference, 'SUP-ABC123');
      expect(ticket.category, TicketCategory.bookingProblem);
      expect(ticket.status, TicketStatus.open);
      expect(ticket.messages.single.isFromSupport, isFalse);
    });
  });

  group('ApiPrescriptionRepository', () {
    test('sends drug ids, never the classification', () async {
      adapter.onPost(
        '/v1/prescriptions',
        (server) => server.reply(201, _prescriptionJson()),
        // No `telemedicineList` anywhere in the body: trusting a client-supplied
        // classification would make the whole MoHFW check decorative.
        data: {
          'appointmentId': 'a1',
          'items': [
            {
              'drugId': 'amoxicillin-500',
              'strength': '500mg',
              'frequency': '1-0-1',
              'durationDays': 5,
            }
          ],
        },
      );

      final rx = await ApiPrescriptionRepository(api).issue(
        appointmentId: 'a1',
        patientName: 'Priya',
        patientAge: '32',
        patientGender: 'FEMALE',
        isFollowUp: true,
        items: const [
          PrescriptionItem(
            drugId: 'amoxicillin-500',
            drugName: 'Amoxicillin 500mg',
            genericName: 'Amoxicillin',
            strength: '500mg',
            form: 'Capsule',
            frequency: '1-0-1',
            durationDays: 5,
          )
        ],
      );

      expect(rx.verificationCode, 'RX-ABCD2345');
      expect(rx.items.single.drugName, 'Amoxicillin 500mg');
    });

    test('a server-side drug refusal reaches the UI as a validation Failure',
        () async {
      adapter.onPost(
        '/v1/prescriptions',
        (server) => server.reply(422, {
          'title': 'Medicine not permitted',
          'status': 422,
          'detail':
              'Alprazolam 0.25mg cannot be prescribed in a teleconsultation.',
          'code': 'DRUG_NOT_PRESCRIBABLE',
        }),
        data: Matchers.any,
      );

      await expectLater(
        ApiPrescriptionRepository(api).issue(
          appointmentId: 'a1',
          patientName: 'Priya',
          patientAge: '32',
          patientGender: 'FEMALE',
          isFollowUp: false,
          items: const [
            PrescriptionItem(
              drugId: 'alprazolam-025',
              drugName: 'Alprazolam 0.25mg',
              genericName: 'Alprazolam',
              strength: '0.25mg',
              form: 'Tablet',
              frequency: '0-0-1',
              durationDays: 7,
            )
          ],
        ),
        throwsA(isA<Failure>()
            .having((f) => f.kind, 'kind', FailureKind.validation)
            .having((f) => f.code, 'code', 'DRUG_NOT_PRESCRIBABLE')),
      );
    });

    test('an unknown drug list is read as prohibited, not as permitted',
        () async {
      adapter.onGet(
        '/v1/prescriptions/drugs',
        (server) => server.reply(200, [
          {
            'id': 'x',
            'name': 'Something New',
            'genericName': 'Novel',
            'form': 'Tablet',
            'telemedicineList': 'LIST_Q',
            'commonStrengths': <String>[],
          }
        ]),
        queryParameters: {'q': 'some'},
      );

      final drugs = await ApiPrescriptionRepository(api).searchDrugs('some');
      expect(drugs.single.telemedicineList, TelemedicineDrugList.prohibited);
      expect(drugs.single.isPrescribableOn(isFollowUp: true), isFalse);
    });
  });

  group('ApiAppointmentRepository', () {
    test('a transport failure becomes a network Failure, not a DioException',
        () async {
      adapter.onGet(
        '/v1/appointments',
        (server) => server.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/v1/appointments'),
            reason: 'offline',
          ),
        ),
      );

      await expectLater(
        ApiAppointmentRepository(api).listForPatient(),
        throwsA(
            isA<Failure>().having((f) => f.kind, 'kind', FailureKind.network)),
      );
    });
  });

  group('BlobClient', () {
    test('an expired signed URL reads as "took too long", not "forbidden"',
        () async {
      final blobDio = Dio();
      final blobAdapter = DioAdapter(dio: blobDio);
      blobAdapter.onPut(
        'https://storage.test/expired',
        (server) => server.reply(403, ''),
        data: Matchers.any,
      );

      await expectLater(
        BlobClient(dio: blobDio).put(
          url: 'https://storage.test/expired',
          bytes: Uint8List.fromList([1]),
          contentType: 'image/jpeg',
        ),
        throwsA(
            isA<Failure>().having((f) => f.code, 'code', 'BLOB_URL_EXPIRED')),
      );
    });
  });
}

Map<String, dynamic> _recordJson({required String scanStatus}) => {
      'id': 'r1',
      'title': 'Blood test',
      'type': 'LAB_REPORT',
      'source': 'PATIENT',
      'recordedAt': '2026-01-02T00:00:00.000Z',
      'uploadedAt': '2026-01-02T10:00:00.000Z',
      'scanStatus': scanStatus,
      'sizeBytes': 2048,
      'contentType': 'image/jpeg',
      'issuedByName': null,
      'notes': null,
      'pageCount': null,
    };

Map<String, dynamic> _prescriptionJson() => {
      'id': 'rx1',
      'verificationCode': 'RX-ABCD2345',
      'providerName': 'Dr Anjali Rao',
      'providerQualification': 'MBBS, MD',
      'providerRegistrationNumber': 'KMC-12345',
      'patientName': 'Priya',
      'patientAge': '32',
      'patientGender': 'FEMALE',
      'issuedAt': '2026-01-02T10:00:00.000Z',
      'status': 'ISSUED',
      'items': [
        {
          'drugName': 'Amoxicillin 500mg',
          'genericName': 'Amoxicillin',
          'strength': '500mg',
          'form': 'Capsule',
          'frequency': '1-0-1',
          'durationDays': 5,
          'instructions': null,
        }
      ],
      'diagnosis': null,
      'advice': null,
      'followUpDate': null,
      'appointmentReference': 'MD-8K2P4Q',
    };
