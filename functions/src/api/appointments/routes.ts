import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { appointmentJson } from "../booking/routes";
import { requireAuth, requireScope } from "../auth/middleware";
import {
  C,
  db,
  slotLockId,
  type AppointmentDoc,
  type DoctorDoc,
  type SlotLockDoc,
} from "../db";
import { handler, Problem } from "../errors";

/** Batch-loads the doctors referenced by a set of appointments. */
async function doctorsFor(appointments: AppointmentDoc[]): Promise<Map<string, DoctorDoc>> {
  const ids = [...new Set(appointments.map((a) => a.doctorId))];
  if (ids.length === 0) return new Map();

  const refs = ids.map((id) => db().collection(C.doctors).doc(id));
  const snaps = await db().getAll(...refs);

  const out = new Map<string, DoctorDoc>();
  snaps.forEach((s) => {
    if (s.exists) out.set(s.id, s.data() as DoctorDoc);
  });
  return out;
}

export function appointmentRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  /**
   * The caller's own appointments.
   *
   * Which side of the appointment they are on is decided from the token, never
   * from a query parameter — a patient cannot ask for a provider's list by
   * passing `?role=provider`.
   */
  r.get(
    "/",
    handler(async (req, res) => {
      const userId = req.auth!.sub;
      const isProvider = req.auth!.role === "PROVIDER";

      if (isProvider && !req.user!.doctorId) {
        res.json({ items: [] });
        return;
      }

      const snap = isProvider
        ? await db()
            .collection(C.appointments)
            .where("doctorId", "==", req.user!.doctorId)
            .orderBy("start", "desc")
            .limit(200)
            .get()
        : await db()
            .collection(C.appointments)
            .where("patientId", "==", userId)
            .orderBy("start", "desc")
            .limit(200)
            .get();

      const docs = snap.docs.map((d) => ({ id: d.id, a: d.data() as AppointmentDoc }));
      const doctors = await doctorsFor(docs.map((d) => d.a));

      res.json({
        items: docs
          .filter(({ a }) => doctors.has(a.doctorId))
          .map(({ id, a }) => appointmentJson(id, a, a.doctorId, doctors.get(a.doctorId)!)),
      });
    })
  );

  r.get(
    "/:id",
    handler(async (req, res) => {
      const snap = await db().collection(C.appointments).doc(req.params.id).get();
      if (!snap.exists) throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");

      const a = snap.data() as AppointmentDoc;
      const isParticipant =
        a.patientId === req.auth!.sub || a.doctorId === req.user!.doctorId;
      if (!isParticipant) {
        throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");
      }

      const doctorSnap = await db().collection(C.doctors).doc(a.doctorId).get();
      if (!doctorSnap.exists) throw Problem.notFound("DOCTOR_NOT_FOUND", "Doctor not found.");

      res.json(appointmentJson(snap.id, a, a.doctorId, doctorSnap.data() as DoctorDoc));
    })
  );

  /**
   * Cancels an appointment and frees the slot.
   *
   * Releasing the lock in the same transaction matters: a cancelled appointment
   * whose slot stays locked is a slot nobody can ever book again.
   */
  r.post(
    "/:id/cancel",
    requireScope("appointment:cancel"),
    handler(async (req, res) => {
      const { reason } = req.body ?? {};
      if (typeof reason !== "string" || !reason.trim()) {
        throw Problem.validation("A reason is required.", { reason: "required" });
      }

      const firestore = db();
      const apptRef = firestore.collection(C.appointments).doc(req.params.id);
      const userId = req.auth!.sub;
      const isProvider = req.auth!.role === "PROVIDER";

      const updated = await firestore.runTransaction(async (tx) => {
        const snap = await tx.get(apptRef);
        if (!snap.exists) throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");

        const a = snap.data() as AppointmentDoc;
        const isParticipant = isProvider ? a.doctorId === req.user!.doctorId : a.patientId === userId;
        if (!isParticipant) {
          throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");
        }

        const cancellable =
          ["CONFIRMED", "CHECKED_IN", "PENDING_PAYMENT"].includes(a.status) &&
          a.start.toMillis() > Date.now();
        if (!cancellable) {
          throw Problem.conflict("NOT_CANCELLABLE", "This appointment can no longer be cancelled.");
        }

        const status = isProvider ? "CANCELLED_BY_PROVIDER" : "CANCELLED_BY_PATIENT";
        tx.update(apptRef, { status, cancellationReason: reason.trim(), updatedAt: Timestamp.now() });

        const lockId = `${a.doctorId}__${a.start.toMillis()}`;
        tx.delete(firestore.collection(C.slotLocks).doc(lockId));

        return { ...a, status, cancellationReason: reason.trim() } as AppointmentDoc;
      });

      const doctorSnap = await firestore.collection(C.doctors).doc(updated.doctorId).get();
      res.json(
        appointmentJson(req.params.id, updated, updated.doctorId, doctorSnap.data() as DoctorDoc)
      );
    })
  );

  /**
   * Moves an appointment to a different slot on the same doctor.
   *
   * The whole endpoint exists so this is **one transaction**. A client doing
   * cancel-then-book releases the old slot first, and a patient who then loses
   * the race for the new time has lost the appointment they already had. Here
   * the new lock is taken and the old one released together, so the failure
   * mode is "you keep your original time", which is the only acceptable one.
   *
   * The caller sends an instant, never a slot id. The id is
   * `<doctorId>__<startMillis>` and it is the entire no-double-booking
   * guarantee — a client that composes it can compose a wrong one, and two
   * clients disagreeing about the id is exactly the collision the deterministic
   * id exists to make impossible.
   */
  r.post(
    "/:id/reschedule",
    // Rescheduling consumes a slot, so it is gated on the scope that creates
    // appointments rather than the one that cancels them.
    requireScope("appointment:create"),
    handler(async (req, res) => {
      const { start } = req.body ?? {};
      const startMs = typeof start === "string" ? Date.parse(start) : NaN;
      if (!Number.isFinite(startMs)) {
        throw Problem.validation("A new start time is required.", { start: "required" });
      }
      if (startMs <= Date.now()) {
        throw Problem.validation("Pick a time in the future.", { start: "past" });
      }

      const firestore = db();
      const apptRef = firestore.collection(C.appointments).doc(req.params.id);
      const userId = req.auth!.sub;
      const isProvider = req.auth!.role === "PROVIDER";

      const updated = await firestore.runTransaction(async (tx) => {
        const snap = await tx.get(apptRef);
        if (!snap.exists) throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");

        const a = snap.data() as AppointmentDoc;
        const isParticipant = isProvider ? a.doctorId === req.user!.doctorId : a.patientId === userId;
        if (!isParticipant) {
          // Same shape as an unknown id: telling a stranger that an
          // appointment exists is itself a disclosure.
          throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");
        }

        const movable =
          ["CONFIRMED", "PENDING_PAYMENT"].includes(a.status) &&
          a.start.toMillis() > Date.now();
        if (!movable) {
          throw Problem.conflict("NOT_RESCHEDULABLE", "This appointment can no longer be moved.");
        }

        const oldStart = a.start.toDate();
        const newStart = new Date(startMs);
        const oldLockId = slotLockId(a.doctorId, oldStart);
        const newLockId = slotLockId(a.doctorId, newStart);

        if (oldLockId === newLockId) {
          throw Problem.validation("That is the time this appointment already has.", {
            start: "unchanged",
          });
        }

        // The appointment keeps its duration. Deriving the end from the old
        // one rather than trusting a client-sent value is what stops a
        // repackaged client turning a 15-minute slot into an hour.
        const durationMs = a.end.toMillis() - a.start.toMillis();
        const newEnd = new Date(startMs + durationMs);

        const newLockRef = firestore.collection(C.slotLocks).doc(newLockId);
        const newLockSnap = await tx.get(newLockRef);

        if (newLockSnap.exists) {
          const lock = newLockSnap.data() as SlotLockDoc;
          const heldByUs =
            lock.state === "HELD" &&
            lock.heldBy === userId &&
            (lock.holdExpiresAt?.toMillis() ?? 0) > Date.now();
          const lapsed =
            lock.state === "HELD" && (lock.holdExpiresAt?.toMillis() ?? 0) <= Date.now();

          if (!heldByUs && !lapsed) {
            throw Problem.conflict("SLOT_TAKEN", "That time was just booked by someone else.");
          }
        }

        const at = Timestamp.now();

        // Take the new slot first, release the old one second. Both land in
        // the same commit, so the ordering is about intent rather than timing
        // — but it is the ordering the fixture mirrors, and a reader comparing
        // the two should find the same story.
        tx.set(newLockRef, {
          doctorId: a.doctorId,
          start: Timestamp.fromDate(newStart),
          end: Timestamp.fromDate(newEnd),
          state: "BOOKED",
          heldBy: null,
          holdExpiresAt: null,
          appointmentId: req.params.id,
        } satisfies SlotLockDoc);

        tx.delete(firestore.collection(C.slotLocks).doc(oldLockId));

        const patch = {
          start: Timestamp.fromDate(newStart),
          end: Timestamp.fromDate(newEnd),
          updatedAt: at,
        };
        tx.update(apptRef, patch);

        return { ...a, ...patch } as AppointmentDoc;
      });

      const doctorSnap = await firestore.collection(C.doctors).doc(updated.doctorId).get();
      res.json(
        appointmentJson(req.params.id, updated, updated.doctorId, doctorSnap.data() as DoctorDoc)
      );
    })
  );

  /** Provider-side check-in, moving CONFIRMED to CHECKED_IN. */
  r.post(
    "/:id/check-in",
    requireScope("appointments:read_own"),
    handler(async (req, res) => {
      const firestore = db();
      const apptRef = firestore.collection(C.appointments).doc(req.params.id);

      const updated = await firestore.runTransaction(async (tx) => {
        const snap = await tx.get(apptRef);
        if (!snap.exists) throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");

        const a = snap.data() as AppointmentDoc;
        if (a.doctorId !== req.user!.doctorId) {
          throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");
        }
        if (a.status !== "CONFIRMED") {
          throw Problem.conflict("NOT_CHECKABLE", "This appointment cannot be checked in.");
        }

        tx.update(apptRef, { status: "CHECKED_IN" });
        return { ...a, status: "CHECKED_IN" } as AppointmentDoc;
      });

      const doctorSnap = await firestore.collection(C.doctors).doc(updated.doctorId).get();
      res.json(
        appointmentJson(req.params.id, updated, updated.doctorId, doctorSnap.data() as DoctorDoc)
      );
    })
  );

  return r;
}
