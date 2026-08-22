import { createHash, randomUUID } from "crypto";
import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { requireAuth, requireScope } from "../auth/middleware";
import {
  C,
  db,
  type AppointmentDoc,
  type DoctorDoc,
  type PatientProfileDoc,
  type PrescriptionDoc,
  type PrescriptionItemDoc,
  type RefillRequestDoc,
  type RefillStatus,
  type RefillDeclineReason,
} from "../db";
import { handler, Problem } from "../errors";
import { rateLimit } from "../rate_limit";
import { assertPrescribable, type DrugDoc, type DrugList } from "./drug_rules";
import { signedDownloadUrl } from "../storage";
import { notify } from "../notifications/send";
import { storePrescriptionPdf } from "./pdf_store";

/**
 * Prescriptions.
 *
 * A prescription is a legal document, which drives three decisions here:
 *
 *  - **Provider details are snapshots**, not references. It has to render
 *    exactly as issued even after the doctor edits their profile, and the NMC
 *    registration number must appear on it.
 *  - **It is immutable once issued.** There is no edit endpoint. A mistake is
 *    corrected by cancelling and issuing a replacement, so the record of what
 *    was actually handed to a patient survives.
 *  - **The verification code is a keyed digest of the content**, so a pharmacy
 *    checking it is checking the prescription rather than checking that a
 *    string exists.
 */

const MAX_ITEMS = 20;

function itemJson(i: PrescriptionItemDoc) {
  return {
    drugName: i.drugName,
    genericName: i.genericName,
    strength: i.strength,
    form: i.form,
    frequency: i.frequency,
    durationDays: i.durationDays,
    instructions: i.instructions ?? null,
  };
}

function prescriptionJson(id: string, p: PrescriptionDoc) {
  return {
    id,
    verificationCode: p.verificationCode,
    providerName: p.providerName,
    providerQualification: p.providerQualification,
    providerRegistrationNumber: p.providerRegistrationNumber,
    patientName: p.patientName,
    patientAge: p.patientAge,
    patientGender: p.patientGender,
    issuedAt: p.issuedAt.toDate().toISOString(),
    status: p.status,
    items: p.items.map(itemJson),
    diagnosis: p.diagnosis ?? null,
    advice: p.advice ?? null,
    followUpDate: p.followUpDate ?? null,
    appointmentReference: p.appointmentReference ?? null,
  };
}

/**
 * A short code derived from the prescription's content and the signing secret.
 *
 * Keyed, so it cannot be forged without the secret, and content-derived, so an
 * altered prescription no longer matches its own code. A random string would
 * only prove that *a* prescription exists, which is the question nobody asks.
 */
function verificationCode(secret: string, id: string, items: PrescriptionItemDoc[]): string {
  const canonical = items
    .map((i) => `${i.drugName}|${i.strength}|${i.frequency}|${i.durationDays}`)
    .join(";");
  const digest = createHash("sha256").update(`${secret}|${id}|${canonical}`).digest("hex");
  // Base32-ish alphabet with no 0/O or 1/I, because this gets read aloud.
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let out = "";
  for (let i = 0; i < 8; i++) {
    out += alphabet[parseInt(digest.slice(i * 2, i * 2 + 2), 16) % alphabet.length];
  }
  return `RX-${out}`;
}

function ageFrom(dateOfBirth?: string | null): string {
  if (!dateOfBirth) return "Not recorded";
  const dob = new Date(`${dateOfBirth}T00:00:00Z`);
  if (Number.isNaN(dob.getTime())) return "Not recorded";
  const now = new Date();
  let years = now.getUTCFullYear() - dob.getUTCFullYear();
  const beforeBirthday =
    now.getUTCMonth() < dob.getUTCMonth() ||
    (now.getUTCMonth() === dob.getUTCMonth() && now.getUTCDate() < dob.getUTCDate());
  if (beforeBirthday) years--;
  return `${years}`;
}


const MAX_NOTE = 300;

const DECLINE_REASONS = [
  "REVIEW_NEEDED",
  "NOT_SUITABLE_REMOTELY",
  "TOO_SOON",
  "TREATMENT_CHANGED",
  "SEE_ANOTHER_DOCTOR",
  "OTHER",
];

function refillJson(id: string, r: RefillRequestDoc) {
  return {
    id,
    prescriptionId: r.prescriptionId,
    doctorName: r.doctorName,
    requestedAt: r.requestedAt.toDate().toISOString(),
    status: r.status,
    patientNote: r.patientNote ?? null,
    decidedAt: r.decidedAt ? r.decidedAt.toDate().toISOString() : null,
    declineReason: r.declineReason ?? null,
    decisionNote: r.decisionNote ?? null,
    issuedPrescriptionId: r.issuedPrescriptionId ?? null,
  };
}

async function loadRefill(id: string) {
  const ref = db().collection(C.refillRequests).doc(id);
  const snap = await ref.get();
  if (!snap.exists) throw Problem.notFound("REFILL_NOT_FOUND", "Not found.");
  return { ref, doc: snap.data() as RefillRequestDoc };
}

/**
 * Re-resolves every item and refuses anything that may not be repeated.
 *
 * `isFollowUp: true` throughout, because that is what a refill is — and the
 * reason this check cannot be skipped: it is precisely the flag that unlocks
 * List B.
 */
async function assertRefillable(source: PrescriptionDoc): Promise<void> {
  for (const item of source.items) {
    const snap = await db()
      .collection(C.drugs)
      .where("name", "==", item.drugName)
      .limit(1)
      .get();
    if (snap.empty) continue;

    const drug = snap.docs[0].data() as { telemedicineList?: string };
    // List B is *permitted* here, and that is the whole point: a refill is the
    // follow-up that unlocks it. Only the prohibited list is refused, and it is
    // refused against today's classification rather than the one snapshotted on
    // a document that may be months old.
    if (drug.telemedicineList === "PROHIBITED") {
      throw Problem.validation(`${item.drugName} cannot be repeated remotely.`, {
        items: "not_prescribable",
      });
    }
  }
}

export function prescriptionRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  /** Drug search. Every result carries its list, so the UI can explain a block. */
  r.get(
    "/drugs",
    requireScope("prescription:write"),
    handler(async (req, res) => {
      const q = String(req.query.q ?? "").trim().toLowerCase();
      if (q.length < 2) {
        res.json([]);
        return;
      }

      // Firestore has no substring search. `searchTerms` holds lowercased
      // tokens and this is a prefix range query — correct at closed-beta scale.
      // A real formulary needs a search index, not a cleverer query.
      const snap = await db()
        .collection(C.drugs)
        .where("searchTerms", "array-contains", q.slice(0, 3))
        .limit(50)
        .get();

      const matches = snap.docs
        .map((d) => ({ id: d.id, drug: d.data() as DrugDoc }))
        .filter(
          ({ drug }) =>
            drug.name.toLowerCase().includes(q) || drug.genericName.toLowerCase().includes(q)
        )
        .slice(0, 20);

      res.json(
        matches.map(({ id, drug }) => ({
          id,
          name: drug.name,
          genericName: drug.genericName,
          form: drug.form,
          telemedicineList: drug.telemedicineList,
          commonStrengths: drug.commonStrengths,
        }))
      );
    })
  );

  r.get(
    "/",
    handler(async (req, res) => {
      const isProvider = req.user!.role === "PROVIDER";
      const query = isProvider
        ? db().collection(C.prescriptions).where("doctorId", "==", req.user!.doctorId ?? "__none__")
        : db().collection(C.prescriptions).where("patientId", "==", req.auth!.sub);

      const snap = await query.get();
      const items = snap.docs
        .map((d) => ({ id: d.id, p: d.data() as PrescriptionDoc }))
        .sort((a, b) => b.p.issuedAt.toMillis() - a.p.issuedAt.toMillis());

      res.json(items.map(({ id, p }) => prescriptionJson(id, p)));
    })
  );

  r.get(
    "/:id",
    handler(async (req, res) => {
      const snap = await db().collection(C.prescriptions).doc(req.params.id).get();
      if (!snap.exists) throw Problem.notFound("PRESCRIPTION_NOT_FOUND", "Not found.");

      const p = snap.data() as PrescriptionDoc;
      const mine = p.patientId === req.auth!.sub || p.doctorId === req.user!.doctorId;
      if (!mine) {
        throw Problem.forbidden("NOT_YOURS", "You do not have access to this prescription.");
      }

      res.json(prescriptionJson(req.params.id, p));
    })
  );

  /**
   * Refill requests visible to the caller.
   *
   * Which side is asking is decided from the session, never from a parameter.
   * A `?whose=` would be an authorization decision made by the client.
   */
  r.get(
    "/refills",
    handler(async (req, res) => {
      const isProvider = req.auth!.role === "PROVIDER";
      const field = isProvider ? "doctorId" : "patientId";
      const value = isProvider ? req.user!.doctorId : req.auth!.sub;
      if (!value) throw Problem.forbidden("NOT_A_PROVIDER", "Not a provider.");

      const snap = await db()
        .collection(C.refillRequests)
        .where(field, "==", value)
        .orderBy("requestedAt", "desc")
        .limit(100)
        .get();

      res.json(
        snap.docs.map((d) => refillJson(d.id, d.data() as RefillRequestDoc))
      );
    })
  );

  /** Asks the issuing doctor to repeat a prescription. */
  r.post(
    "/:id/refill",
    requireScope("prescription:read_own"),
    handler(async (req, res) => {
      const snap = await db().collection(C.prescriptions).doc(req.params.id).get();
      if (!snap.exists) throw Problem.notFound("PRESCRIPTION_NOT_FOUND", "Not found.");

      const p = snap.data() as PrescriptionDoc;
      if (p.patientId !== req.auth!.sub) {
        throw Problem.notFound("PRESCRIPTION_NOT_FOUND", "Not found.");
      }
      if (p.status !== "ISSUED") {
        // Cancelled or superseded means a clinician withdrew or replaced it.
        // Repeating it would quietly reinstate a decision somebody made.
        throw Problem.conflict("REFILL_NOT_ALLOWED", "This prescription can no longer be repeated.");
      }

      const open = await db()
        .collection(C.refillRequests)
        .where("prescriptionId", "==", req.params.id)
        .where("status", "==", "PENDING")
        .limit(1)
        .get();
      if (!open.empty) {
        throw Problem.conflict(
          "REFILL_ALREADY_REQUESTED",
          "You have already asked for a repeat of this prescription."
        );
      }

      const note = typeof req.body?.note === "string" ? req.body.note.trim() : "";
      if (note.length > MAX_NOTE) {
        throw Problem.validation("Keep your note under 300 characters.", { note: "too_long" });
      }

      const doc: RefillRequestDoc = {
        prescriptionId: req.params.id,
        patientId: p.patientId,
        doctorId: p.doctorId,
        doctorName: p.providerName,
        requestedAt: Timestamp.now(),
        status: "PENDING",
        patientNote: note || null,
        decidedAt: null,
        declineReason: null,
        decisionNote: null,
        issuedPrescriptionId: null,
      };

      const ref = await db().collection(C.refillRequests).add(doc);
      res.status(201).json(refillJson(ref.id, doc));
    })
  );

  /** Withdraws a request the doctor has not answered. */
  r.post(
    "/refills/:id/cancel",
    handler(async (req, res) => {
      const { ref, doc } = await loadRefill(req.params.id);
      if (doc.patientId !== req.auth!.sub) {
        throw Problem.notFound("REFILL_NOT_FOUND", "Not found.");
      }
      if (doc.status !== "PENDING") {
        throw Problem.conflict("REFILL_ALREADY_DECIDED", "Your doctor has already answered this.");
      }

      const patch = { status: "CANCELLED" as RefillStatus, decidedAt: Timestamp.now() };
      await ref.update(patch);
      res.json(refillJson(req.params.id, { ...doc, ...patch }));
    })
  );

  /**
   * Approves a refill, issuing a fresh prescription.
   *
   * The drug list is re-checked here rather than inherited. A refill *is* the
   * follow-up that makes List B permissible, so this is the one patient-
   * initiated path that can end in a restricted drug being dispensed — and a
   * classification that has changed since the original must be honoured.
   */
  r.post(
    "/refills/:id/approve",
    requireScope("prescription:write"),
    handler(async (req, res) => {
      const { ref, doc } = await loadRefill(req.params.id);
      if (doc.doctorId !== req.user!.doctorId) {
        throw Problem.notFound("REFILL_NOT_FOUND", "Not found.");
      }
      if (doc.status !== "PENDING") {
        throw Problem.conflict("REFILL_ALREADY_DECIDED", "This request has already been answered.");
      }

      const original = await db().collection(C.prescriptions).doc(doc.prescriptionId).get();
      if (!original.exists) throw Problem.notFound("PRESCRIPTION_NOT_FOUND", "Not found.");
      const source = original.data() as PrescriptionDoc;

      await assertRefillable(source);

      const id = randomUUID();
      const refill: PrescriptionDoc = {
        ...source,
        verificationCode: verificationCode(secret(), id, source.items),
        issuedAt: Timestamp.now(),
        status: "ISSUED",
        isFollowUp: true,
        pdfPath: null,
        pdfSha256: null,
        pdfStoredAt: null,
      };
      await db().collection(C.prescriptions).doc(id).set(refill);
      // Best-effort, exactly as on first issue: the prescription is already
      // committed, and a storage outage must not undo a clinical decision.
      await storePrescriptionPdf(id, refill);

      const patch = {
        status: "APPROVED" as RefillStatus,
        decidedAt: Timestamp.now(),
        issuedPrescriptionId: id,
      };
      await ref.update(patch);

      await notify({
        userId: doc.patientId,
        kind: "PRESCRIPTION_ISSUED",
        title: "Repeat approved",
        body: `From ${doc.doctorName}`,
        targetId: id,
      });

      res.json(refillJson(req.params.id, { ...doc, ...patch }));
    })
  );

  /**
   * Declines a refill. **The reason and the note are both required.**
   *
   * A patient told only "declined" will ask again, or stop taking a medicine
   * they still need. The category says what to do next and can be counted
   * later; the note says why. Refusing a blank note here is what stops a
   * client from making it optional.
   */
  r.post(
    "/refills/:id/decline",
    requireScope("prescription:write"),
    handler(async (req, res) => {
      const { ref, doc } = await loadRefill(req.params.id);
      if (doc.doctorId !== req.user!.doctorId) {
        throw Problem.notFound("REFILL_NOT_FOUND", "Not found.");
      }
      if (doc.status !== "PENDING") {
        throw Problem.conflict("REFILL_ALREADY_DECIDED", "This request has already been answered.");
      }

      const reason = req.body?.reason;
      if (!DECLINE_REASONS.includes(reason)) {
        throw Problem.validation("Choose a reason.", { reason: "invalid" });
      }

      const note = typeof req.body?.note === "string" ? req.body.note.trim() : "";
      if (!note) {
        throw Problem.validation(
          "Tell the patient why, so they know what to do next.",
          { note: "required" }
        );
      }
      if (note.length > MAX_NOTE) {
        throw Problem.validation("Keep the note under 300 characters.", { note: "too_long" });
      }

      const patch = {
        status: "DECLINED" as RefillStatus,
        decidedAt: Timestamp.now(),
        declineReason: reason as RefillDeclineReason,
        decisionNote: note,
      };
      await ref.update(patch);

      await notify({
        userId: doc.patientId,
        kind: "ACCOUNT_UPDATE",
        title: "Repeat declined",
        // The reason lives in the app, behind authentication. A lock screen is
        // the wrong place for a clinical judgement about someone.
        body: `${doc.doctorName} has answered your request`,
        targetId: req.params.id,
      });

      res.json(refillJson(req.params.id, { ...doc, ...patch }));
    })
  );

  /**
   * A short-lived link to the server-generated, write-once PDF.
   *
   * Deliberately not a redirect to a permanent URL: the object is private and
   * every read is entitled here first, exactly like a medical record download.
   *
   * `pdfSha256` comes back with the link so the caller can verify the bytes it
   * receives are the bytes that were frozen. Without that, "immutable storage"
   * is a claim the client has no way to check.
   */
  r.get(
    "/:id/pdf",
    handler(async (req, res) => {
      const snap = await db().collection(C.prescriptions).doc(req.params.id).get();
      if (!snap.exists) throw Problem.notFound("PRESCRIPTION_NOT_FOUND", "Not found.");

      const p = snap.data() as PrescriptionDoc;
      const mine = p.patientId === req.auth!.sub || p.doctorId === req.user!.doctorId;
      if (!mine) {
        throw Problem.forbidden("NOT_YOURS", "You do not have access to this prescription.");
      }

      if (!p.pdfPath) {
        // Distinguished from "not found" on purpose: the prescription exists
        // and is valid, its document just has not been stored yet. The client
        // falls back to rendering locally rather than showing an error.
        throw Problem.notFound(
          "PRESCRIPTION_PDF_PENDING",
          "This prescription's document is still being prepared."
        );
      }

      res.json({
        url: await signedDownloadUrl(p.pdfPath),
        sha256: p.pdfSha256 ?? null,
      });
    })
  );

  /**
   * Issues a prescription against a completed or in-progress appointment.
   *
   * Every drug is re-resolved from the catalogue by id: the request carries the
   * doctor's *choices*, never the classification those choices are judged
   * against. Trusting a client-supplied `telemedicineList` would make the whole
   * check decorative.
   */
  r.post(
    "/",
    requireScope("prescription:write"),
    handler(async (req, res) => {
      const doctorId = req.user!.doctorId;
      if (!doctorId) throw Problem.forbidden("NOT_A_PROVIDER", "Only a provider may prescribe.");

      const { appointmentId, items, diagnosis, advice, followUpDate } = req.body ?? {};
      if (typeof appointmentId !== "string" || !appointmentId) {
        throw Problem.validation("Which consultation?", { appointmentId: "required" });
      }
      if (!Array.isArray(items) || items.length === 0) {
        throw Problem.validation("Add at least one medicine.", { items: "required" });
      }
      if (items.length > MAX_ITEMS) {
        throw Problem.validation(`At most ${MAX_ITEMS} medicines.`, { items: "too many" });
      }

      const apptSnap = await db().collection(C.appointments).doc(appointmentId).get();
      if (!apptSnap.exists) {
        throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");
      }
      const appt = apptSnap.data() as AppointmentDoc;
      if (appt.doctorId !== doctorId) {
        throw Problem.forbidden("NOT_YOUR_APPOINTMENT", "That is not your consultation.");
      }
      if (appt.status !== "IN_PROGRESS" && appt.status !== "COMPLETED") {
        throw Problem.conflict(
          "CONSULTATION_NOT_STARTED",
          "A prescription can only be issued during or after the consultation."
        );
      }

      // Follow-up status decides whether List B is permitted, so it is derived
      // from history rather than taken from the request.
      const priorSnap = await db()
        .collection(C.appointments)
        .where("patientId", "==", appt.patientId)
        .where("doctorId", "==", doctorId)
        .where("status", "==", "COMPLETED")
        .limit(2)
        .get();
      const isFollowUp = priorSnap.docs.some((d) => d.id !== appointmentId);

      const resolved: PrescriptionItemDoc[] = [];
      const forRuleCheck: { drugName: string; list: DrugList }[] = [];

      for (const raw of items) {
        const drugSnap = await db().collection(C.drugs).doc(String(raw?.drugId ?? "")).get();
        if (!drugSnap.exists) {
          throw Problem.validation("Unknown medicine.", { drugId: String(raw?.drugId) });
        }
        const drug = drugSnap.data() as DrugDoc;

        const durationDays = Number(raw?.durationDays);
        if (!Number.isInteger(durationDays) || durationDays < 1 || durationDays > 180) {
          throw Problem.validation("Enter a duration in days.", { durationDays: "invalid" });
        }
        if (typeof raw?.frequency !== "string" || !raw.frequency.trim()) {
          throw Problem.validation("Enter a dosing frequency.", { frequency: "required" });
        }

        resolved.push({
          drugName: drug.name,
          genericName: drug.genericName,
          strength: String(raw?.strength ?? "").trim(),
          form: drug.form,
          frequency: raw.frequency.trim(),
          durationDays,
          instructions:
            typeof raw?.instructions === "string" && raw.instructions.trim()
              ? raw.instructions.trim()
              : null,
        });
        forRuleCheck.push({ drugName: drug.name, list: drug.telemedicineList });
      }

      assertPrescribable(forRuleCheck, isFollowUp);

      const [doctorSnap, profileSnap] = await Promise.all([
        db().collection(C.doctors).doc(doctorId).get(),
        db().collection(C.patientProfiles).doc(appt.patientId).get(),
      ]);
      const doctor = doctorSnap.data() as DoctorDoc;
      const profile = profileSnap.data() as PatientProfileDoc | undefined;

      const id = randomUUID();
      const doc: PrescriptionDoc = {
        patientId: appt.patientId,
        doctorId,
        appointmentId,
        verificationCode: verificationCode(secret(), id, resolved),
        // Snapshots. A later profile edit must not rewrite an issued document.
        providerName: doctor.name,
        providerQualification: doctor.qualification,
        providerRegistrationNumber: doctor.registrationNumber,
        patientName: appt.patientName,
        patientAge: ageFrom(profile?.dateOfBirth),
        patientGender: profile?.gender ?? "Not recorded",
        issuedAt: Timestamp.now(),
        status: "ISSUED",
        items: resolved,
        diagnosis: typeof diagnosis === "string" && diagnosis.trim() ? diagnosis.trim() : null,
        advice: typeof advice === "string" && advice.trim() ? advice.trim() : null,
        followUpDate: typeof followUpDate === "string" ? followUpDate : null,
        appointmentReference: appt.referenceCode,
        isFollowUp,
        // Written as explicit nulls rather than left absent: Firestore does not
        // match a missing field against `== null`, so the sweep that repairs
        // undocumented prescriptions would never see them.
        pdfPath: null,
        pdfSha256: null,
        pdfStoredAt: null,
      };

      await db().collection(C.prescriptions).doc(id).set(doc);
      await apptSnap.ref.update({ hasPrescription: true });

      // The document is generated and frozen after the clinical act is
      // recorded, never before it. A storage outage must not be able to stop a
      // doctor prescribing; `storePrescriptionPdf` records its own failure and
      // the scheduled sweep retries.
      const stored = await storePrescriptionPdf(id, doc);

      // Names no drug. This body reaches a lock screen, and "your Sertraline
      // prescription is ready" is a disclosure to whoever is holding the phone.
      await notify({
        userId: appt.patientId,
        kind: "PRESCRIPTION_ISSUED",
        title: "Prescription ready",
        body: `From your consultation with ${doctor.name}`,
        targetId: id,
      });

      res.status(201).json(prescriptionJson(id, { ...doc, ...stored }));
    })
  );

  return r;
}

/**
 * Prescription verification, for pharmacies.
 *
 * A separate router because it must be **unauthenticated**: a pharmacist is not
 * a MiDoctor user and will never hold a token. Mounting it inside the
 * authenticated router — the obvious mistake — would make the QR code on every
 * prescription unusable by the only people it is printed for.
 *
 * It returns strictly what is needed to trust the paper in front of them: who
 * issued it, their council registration, when, and how many items. Never the
 * diagnosis, never the patient. The code is a keyed digest of the content, so
 * an altered prescription does not match its own code.
 *
 * Rate limited because it is unauthenticated and enumerable.
 */
export function prescriptionVerifyRoutes(): Router {
  const r = Router();

  r.get(
    "/:code",
    rateLimit({ name: "rx_verify", max: 60, windowSeconds: 300 }),
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.prescriptions)
        .where("verificationCode", "==", req.params.code)
        .limit(1)
        .get();

      if (snap.empty) {
        res.json({ valid: false });
        return;
      }

      const p = snap.docs[0]!.data() as PrescriptionDoc;
      res.json({
        valid: p.status === "ISSUED",
        status: p.status,
        issuedAt: p.issuedAt.toDate().toISOString(),
        providerName: p.providerName,
        providerRegistrationNumber: p.providerRegistrationNumber,
        itemCount: p.items.length,
      });
    })
  );

  return r;
}
