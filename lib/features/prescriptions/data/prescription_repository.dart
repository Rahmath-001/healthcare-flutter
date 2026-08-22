import '../../../core/error/failure.dart';
import '../../../core/fixtures/fixture_backend.dart';
import '../domain/prescription.dart';
import '../domain/refill_request.dart';

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

  /// Refill requests the caller can see.
  ///
  /// The patient's own when signed in as a patient; those addressed to the
  /// doctor when signed in as a provider. One method rather than two, because
  /// the server already knows which side is asking and a client-supplied
  /// "whose" parameter would be a authorization decision made in the wrong
  /// place.
  Future<List<RefillRequest>> refillRequests();

  /// Asks the issuing doctor to repeat a prescription.
  Future<RefillRequest> requestRefill(String prescriptionId, {String? note});

  /// Withdraws a request the doctor has not answered yet.
  Future<RefillRequest> cancelRefill(String id);

  /// Approves a refill, issuing a fresh prescription.
  ///
  /// A refill is by definition a follow-up, which is what makes a List B
  /// medicine prescribable at all — so the drug list is re-checked server-side
  /// rather than inherited from the original document.
  Future<RefillRequest> approveRefill(String id);

  /// Declines a refill. **The reason and the note are both required.**
  ///
  /// A patient told only "declined" will ask again or stop taking a medicine
  /// they still need. The category says what to do next; the note says why.
  Future<RefillRequest> declineRefill(
    String id, {
    required RefillDeclineReason reason,
    required String note,
  });

  /// A short-lived link to the **server-generated, write-once** PDF.
  ///
  /// Null while the document is still being prepared, which is a real state
  /// rather than an error: the prescription is issued and verifiable the
  /// instant it is written, but freezing its PDF is a separate step that can
  /// lag or fail. Callers fall back to rendering locally.
  ///
  /// The digest is returned with the link so the bytes can be checked against
  /// what the server recorded. Immutable storage nobody can verify is a claim,
  /// not a control.
  Future<({String url, String? sha256})?> officialPdf(String id);
}

class FixturePrescriptionRepository implements PrescriptionRepository {
  @override
  Future<List<RefillRequest>> refillRequests() async {
    await Future<void>.delayed(latency);
    return _backend.refillRequests();
  }

  @override
  Future<RefillRequest> requestRefill(
    String prescriptionId, {
    String? note,
  }) async {
    await Future<void>.delayed(latency);
    return _backend.requestRefill(prescriptionId, note: note);
  }

  @override
  Future<RefillRequest> cancelRefill(String id) async {
    await Future<void>.delayed(latency);
    return _backend.cancelRefill(id);
  }

  @override
  Future<RefillRequest> approveRefill(String id) async {
    await Future<void>.delayed(latency);
    return _backend.approveRefill(id);
  }

  @override
  Future<RefillRequest> declineRefill(
    String id, {
    required RefillDeclineReason reason,
    required String note,
  }) async {
    await Future<void>.delayed(latency);
    return _backend.declineRefill(id, reason: reason, note: note);
  }

  /// Sample data has no object storage behind it, so there is no frozen
  /// document to link to. Returning null rather than a fake URL is what keeps
  /// the fallback path exercised in every fixture run — a mock that claims a
  /// document exists would hide the only code path that ever runs offline.
  @override
  Future<({String url, String? sha256})?> officialPdf(String id) async => null;

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
