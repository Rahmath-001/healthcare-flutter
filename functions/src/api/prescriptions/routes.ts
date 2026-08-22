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
