import { createHash, randomUUID } from "crypto";
import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { requireAuth } from "../auth/middleware";
import {
  C,
  db,
  type AppointmentDoc,
  type ChatMessageDoc,
  type ConsultationDoc,
  type DoctorDoc,
} from "../db";
import { handler, Problem } from "../errors";
import { hmsCredentialsFrom, mintJoinToken, type HmsCredentials } from "./hms";

/**
 * Live consultations.
 *
 * A consultation is not a separate booking — it is the live phase of an
 * appointment, and its id is the appointment id. That keeps "the consultation
 * for this appointment" a fact rather than a lookup that can disagree.
 *
 * Three rules are enforced here and nowhere else, because a client cannot
 * enforce any of them against itself:
 *
 *  - **The join window.** Opens 15 minutes before the scheduled start, closes
 *    30 minutes after the scheduled end. In-person appointments are never
 *    joinable.
 *  - **Consent before connection.** The MoHFW guidelines require recorded
 *    consent; no token is minted without it.
 *  - **No recording.** Neither role in the 100ms template may start one, so
 *    FR-TEL-003 holds at the vendor rather than in the UI.
 */

const JOIN_OPENS_BEFORE_MS = 15 * 60 * 1000;
const JOIN_CLOSES_AFTER_MS = 30 * 60 * 1000;
const MAX_MESSAGE = 2000;

function consultationJson(
  id: string,
  c: ConsultationDoc,
  appointment: AppointmentDoc,
  doctor: DoctorDoc
) {
  return {
    id,
    appointmentId: id,
    mode: c.mode,
    status: c.status,
    scheduledStart: appointment.start.toDate().toISOString(),
    scheduledEnd: appointment.end.toDate().toISOString(),
    startedAt: c.startedAt ? c.startedAt.toDate().toISOString() : null,
    endedAt: c.endedAt ? c.endedAt.toDate().toISOString() : null,
    patientName: appointment.patientName,
    doctor: {
      id: appointment.doctorId,
      name: doctor.name,
      qualification: doctor.qualification,
      registrationNumber: doctor.registrationNumber,
      photoUrl: doctor.photoUrl ?? null,
      specialties: doctor.specialties,
    },
    consentCapturedAt: c.consentCapturedAt
      ? c.consentCapturedAt.toDate().toISOString()
      : null,
    // Never a stored flag that could be flipped. Recording is not implemented
    // at any layer, and this says so to the client every time.
    isRecorded: false,
    messages: (c.messages ?? []).map((m) => ({
      id: m.id,
      body: m.body,
      senderName: m.senderName,
      senderId: m.senderId,
      sentAt: m.at.toDate().toISOString(),
    })),
  };
}

/** Loads the consultation, its appointment and doctor, or refuses. */
async function loadFor(req: Express.Request, id: string) {
  const apptSnap = await db().collection(C.appointments).doc(id).get();
  if (!apptSnap.exists) {
    throw Problem.notFound("CONSULTATION_NOT_FOUND", "Consultation not found.");
  }
  const appointment = apptSnap.data() as AppointmentDoc;

  const isPatient = appointment.patientId === req.auth!.sub;
  const isProvider = appointment.doctorId === req.user!.doctorId;
  if (!isPatient && !isProvider) {
    throw Problem.forbidden("NOT_A_PARTICIPANT", "This is not your consultation.");
  }

  const doctorSnap = await db().collection(C.doctors).doc(appointment.doctorId).get();
  const doctor = doctorSnap.data() as DoctorDoc;

  const ref = db().collection(C.consultations).doc(id);
  const snap = await ref.get();

  // Materialised on first touch rather than at booking time: most appointments
  // never reach a consultation, and a row per booking would mostly be noise.
  const consultation: ConsultationDoc = snap.exists
    ? (snap.data() as ConsultationDoc)
    : {
        appointmentId: id,
        patientId: appointment.patientId,
        doctorId: appointment.doctorId,
        mode: appointment.mode,
        status: "SCHEDULED",
        messages: [],
      };

  return { ref, consultation, appointment, doctor, isPatient, isProvider };
}

function assertJoinable(appointment: AppointmentDoc): void {
  if (appointment.mode === "IN_PERSON") {
    throw Problem.conflict(
      "NOT_A_TELECONSULTATION",
      "This appointment is in person. There is nothing to join."
    );
  }
  if (appointment.status === "CANCELLED_BY_PATIENT" || appointment.status === "CANCELLED_BY_PROVIDER") {
    throw Problem.conflict("APPOINTMENT_CANCELLED", "This appointment was cancelled.");
  }

  const now = Date.now();
  const opens = appointment.start.toMillis() - JOIN_OPENS_BEFORE_MS;
  const closes = appointment.end.toMillis() + JOIN_CLOSES_AFTER_MS;

  if (now < opens) {
    throw Problem.conflict(
      "TOO_EARLY",
      "You can join 15 minutes before the appointment starts."
    );
  }
  if (now > closes) {
    throw Problem.conflict("TOO_LATE", "This consultation has closed.");
  }
}

export function consultationRoutes(
  secret: () => string,
  hmsAccessKey: () => string | undefined,
  hmsSecret: () => string | undefined
): Router {
  const r = Router();
  r.use(requireAuth(secret));

  r.get(
    "/:id",
    handler(async (req, res) => {
      const { consultation, appointment, doctor } = await loadFor(req, req.params.id);
      res.json(consultationJson(req.params.id, consultation, appointment, doctor));
    })
  );

  /**
   * Records telemedicine consent.
   *
   * The **exact text** the patient agreed to is hashed and stored alongside its
   * version. Recording only that consent "happened" proves nothing later: the
   * whole evidentiary value is being able to show which words were on screen,
   * which is also why the consent copy is deliberately not machine-translated.
   */
  r.post(
    "/:id/consent",
    handler(async (req, res) => {
      const { ref, consultation, appointment, doctor, isPatient } = await loadFor(
        req,
        req.params.id
      );

      if (!isPatient) {
        throw Problem.forbidden("PATIENT_ONLY", "Only the patient can give consent.");
      }

      const { consentText, consentVersion } = req.body ?? {};
      if (typeof consentText !== "string" || consentText.trim().length < 20) {
        throw Problem.validation("Consent text is required.", { consentText: "required" });
      }
      if (typeof consentVersion !== "string" || !consentVersion) {
        throw Problem.validation("Consent version is required.", {
          consentVersion: "required",
        });
      }

      const capturedAt = Timestamp.now();
      const updated: ConsultationDoc = {
        ...consultation,
        consentCapturedAt: capturedAt,
        consentVersion,
        consentTextHash: createHash("sha256").update(consentText.trim()).digest("hex"),
        consentLocale: typeof req.body?.locale === "string" ? req.body.locale : "en",
      };

      await ref.set(updated, { merge: true });
      res.json(consultationJson(req.params.id, updated, appointment, doctor));
    })
  );

  /**
   * Mints a 100ms join token.
   *
   * Everything that decides whether a call may happen is checked here, because
   * possessing a token *is* permission to be in the room.
   */
  r.post(
    "/:id/join-token",
    handler(async (req, res) => {
      const { ref, consultation, appointment, doctor, isPatient } = await loadFor(
        req,
        req.params.id
      );

      assertJoinable(appointment);

      if (doctor.providerStatus !== "APPROVED") {
        throw Problem.forbidden(
          "PROVIDER_NOT_APPROVED",
          "This doctor is not currently practising on MiDoctor."
        );
      }
      if (!consultation.consentCapturedAt) {
        throw Problem.conflict(
          "CONSENT_REQUIRED",
          "Please agree to the consultation terms before joining."
        );
      }

      const credentials: HmsCredentials | null = hmsCredentialsFrom(
        hmsAccessKey(),
        hmsSecret()
      );
      if (!credentials) {
        // Explicit, because the alternative is a signature error from a library
        // three frames down that nobody can act on.
        throw Problem.internal("Video consultations are not configured yet.");
      }

      const roomId = consultation.roomId ?? randomUUID();
      const { token, expiresIn } = mintJoinToken(credentials, {
        roomId,
        userId: req.auth!.sub,
        // The doctor hosts. A patient cannot mute the doctor or end the call
        // for everyone, and neither role can start a recording.
        role: isPatient ? "guest" : "host",
      });

      await ref.set(
        {
          ...consultation,
          roomId,
          status: consultation.status === "SCHEDULED" ? "WAITING" : consultation.status,
          startedAt: consultation.startedAt ?? Timestamp.now(),
        },
        { merge: true }
      );

      if (appointment.status === "CONFIRMED" || appointment.status === "CHECKED_IN") {
        await db()
          .collection(C.appointments)
          .doc(req.params.id)
          .update({ status: "IN_PROGRESS" });
      }

      res.json({ token, roomId, expiresIn });
    })
  );

  /** Drops to audio. Not a nicety — on Indian mobile networks it saves calls. */
  r.post(
    "/:id/audio",
    handler(async (req, res) => {
      const { ref, consultation, appointment, doctor } = await loadFor(req, req.params.id);
      const updated: ConsultationDoc = { ...consultation, mode: "AUDIO" };
      await ref.set(updated, { merge: true });
      res.json(consultationJson(req.params.id, updated, appointment, doctor));
    })
  );

  r.post(
    "/:id/messages",
    handler(async (req, res) => {
      const { ref, consultation, appointment, doctor } = await loadFor(req, req.params.id);

      const body = req.body?.body;
      if (typeof body !== "string" || !body.trim()) {
        throw Problem.validation("Type a message first.", { body: "required" });
      }
      if (body.length > MAX_MESSAGE) {
        throw Problem.validation("That message is too long.", { body: "too long" });
      }

      const message: ChatMessageDoc = {
        id: randomUUID(),
        body: body.trim(),
        senderId: req.auth!.sub,
        senderName: req.user!.displayName ?? "Participant",
        at: Timestamp.now(),
      };

      // Chat is kept with the medical record, as the privacy screen states.
      const updated: ConsultationDoc = {
        ...consultation,
        messages: [...(consultation.messages ?? []), message],
      };
      await ref.set(updated, { merge: true });

      res.status(201).json(consultationJson(req.params.id, updated, appointment, doctor));
    })
  );

  r.post(
    "/:id/end",
    handler(async (req, res) => {
      const { ref, consultation, appointment, doctor, isProvider } = await loadFor(
        req,
        req.params.id
      );

      const endedAt = Timestamp.now();
      const updated: ConsultationDoc = { ...consultation, status: "ENDED", endedAt };
      await ref.set(updated, { merge: true });

      // Only the doctor ending the call completes the appointment. A patient
      // whose train goes into a tunnel has not finished their consultation.
      if (isProvider && appointment.status === "IN_PROGRESS") {
        await db()
          .collection(C.appointments)
          .doc(req.params.id)
          .update({ status: "COMPLETED" });
      }

      res.json(consultationJson(req.params.id, updated, appointment, doctor));
    })
  );

  return r;
}
