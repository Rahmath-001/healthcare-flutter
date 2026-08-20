import '../../../core/error/failure.dart';
import '../../../core/fixtures/fixture_backend.dart';
import '../domain/prescription.dart';

abstract class PrescriptionRepository {
  Future<List<Prescription>> listForPatient();
  Future<Prescription> byId(String id);

  /// Drug lookup for the composer. Results carry their telemedicine list so the
  /// UI can grey out what may not be prescribed on this consultation.
  Future<List<Drug>> searchDrugs(String query);

  /// Issues a prescription. The server re-validates every item against the
  /// telemedicine drug lists; this call can therefore still fail even when the
  /// client believed the selection was legal.
  Future<Prescription> issue({
    required String appointmentId,
    required String patientName,
    required String patientAge,
    required String patientGender,
    required List<PrescriptionItem> items,
    required bool isFollowUp,
    String? diagnosis,
    String? advice,
    DateTime? followUpDate,
  });
}

class FixturePrescriptionRepository implements PrescriptionRepository {
  FixturePrescriptionRepository({
    this.latency = const Duration(milliseconds: 350),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  static final drugCatalogue = <Drug>[
    const Drug(
      id: 'dr1',
      name: 'Paracetamol',
      genericName: 'Paracetamol',
      form: 'Tablet',
      telemedicineList: TelemedicineDrugList.listO,
      commonStrengths: ['500 mg', '650 mg'],
    ),
    const Drug(
      id: 'dr2',
      name: 'Cetirizine',
      genericName: 'Cetirizine hydrochloride',
      form: 'Tablet',
      telemedicineList: TelemedicineDrugList.listO,
      commonStrengths: ['10 mg'],
    ),
    const Drug(
      id: 'dr3',
      name: 'Amoxicillin',
      genericName: 'Amoxicillin',
      form: 'Capsule',
      telemedicineList: TelemedicineDrugList.listA,
      commonStrengths: ['250 mg', '500 mg'],
    ),
    const Drug(
      id: 'dr4',
      name: 'Metformin',
      genericName: 'Metformin hydrochloride',
      form: 'Tablet',
      telemedicineList: TelemedicineDrugList.listB,
      commonStrengths: ['500 mg', '850 mg', '1000 mg'],
    ),
    const Drug(
      id: 'dr5',
      name: 'Amlodipine',
      genericName: 'Amlodipine besylate',
      form: 'Tablet',
      telemedicineList: TelemedicineDrugList.listB,
      commonStrengths: ['2.5 mg', '5 mg', '10 mg'],
    ),
    const Drug(
      id: 'dr6',
      name: 'Alprazolam',
      genericName: 'Alprazolam',
      form: 'Tablet',
      telemedicineList: TelemedicineDrugList.prohibited,
      commonStrengths: ['0.25 mg', '0.5 mg'],
    ),
    const Drug(
      id: 'dr7',
      name: 'Tramadol',
      genericName: 'Tramadol hydrochloride',
      form: 'Tablet',
      telemedicineList: TelemedicineDrugList.prohibited,
      commonStrengths: ['50 mg'],
    ),
    const Drug(
      id: 'dr8',
      name: 'Pantoprazole',
      genericName: 'Pantoprazole sodium',
      form: 'Tablet',
      telemedicineList: TelemedicineDrugList.listA,
      commonStrengths: ['20 mg', '40 mg'],
    ),
    const Drug(
      id: 'dr9',
      name: 'ORS',
      genericName: 'Oral rehydration salts',
      form: 'Sachet',
      telemedicineList: TelemedicineDrugList.listO,
    ),
    const Drug(
      id: 'dr10',
      name: 'Azithromycin',
      genericName: 'Azithromycin',
      form: 'Tablet',
      telemedicineList: TelemedicineDrugList.listA,
      commonStrengths: ['250 mg', '500 mg'],
    ),
  ];

  @override
  Future<List<Prescription>> listForPatient() async {
    await Future<void>.delayed(latency);
    return _backend.prescriptions();
  }

  @override
  Future<Prescription> byId(String id) async {
    await Future<void>.delayed(latency);
    return _backend.prescriptionById(id);
  }

  @override
  Future<List<Drug>> searchDrugs(String query) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return drugCatalogue;
    return drugCatalogue
        .where((d) =>
            d.name.toLowerCase().contains(q) ||
            d.genericName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<Prescription> issue({
    required String appointmentId,
    required String patientName,
    required String patientAge,
    required String patientGender,
    required List<PrescriptionItem> items,
    required bool isFollowUp,
    String? diagnosis,
    String? advice,
    DateTime? followUpDate,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));

    if (items.isEmpty) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Add at least one medicine before issuing.',
        code: 'NO_ITEMS',
      );
    }

    // Re-check the drug lists exactly as the server does. The client already
    // greys these out, so reaching here means the UI was bypassed — and a
    // fixture that accepted what the server refuses would teach the UI a rule
    // that does not hold.
    for (final item in items) {
      final drug =
          drugCatalogue.where((d) => d.name == item.drugName).firstOrNull;
      if (drug != null && !drug.isPrescribableOn(isFollowUp: isFollowUp)) {
        throw Failure(
          kind: FailureKind.validation,
          message: drug.blockedReason(isFollowUp: isFollowUp) ??
              'This medicine cannot be prescribed remotely.',
          code: 'DRUG_NOT_PERMITTED',
        );
      }
    }

    final prescription = Prescription(
      id: 'p-${DateTime.now().millisecondsSinceEpoch}',
      verificationCode: 'RX-${DateTime.now().millisecondsSinceEpoch % 1000000}',
      // Snapshots, not references: a prescription must render as issued even if
      // the doctor later edits their profile.
      providerName: 'Dr Ananya Sharma',
      providerQualification: 'MBBS, MD (Cardiology)',
      providerRegistrationNumber: 'KMC-58213',
      patientName: patientName,
      patientAge: patientAge,
      patientGender: patientGender,
      issuedAt: DateTime.now(),
      items: items,
      status: PrescriptionStatus.issued,
      diagnosis: diagnosis,
      advice: advice,
      followUpDate: followUpDate,
    );

    // Filed against the appointment, so the patient sees it in their own list
    // and the appointment stops offering "no prescription yet".
    return _backend.issuePrescription(prescription,
        appointmentId: appointmentId);
  }
}
