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

/** IST, always: the "day" a queue belongs to is the doctor's calendar day. */
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
import { istWhen, notify } from "../notifications/send";
import { announceFreeSlot } from "../booking/waitlist_routes";

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

      // The slot is back in the pool, so anybody waiting for it should hear.
      // This is what makes a cancellation useful to someone other than the
      // person cancelling.
      await announceFreeSlot({
        doctorId: updated.doctorId,
        start: updated.start.toDate(),
        mode: updated.mode,
      });

      // Only when the *provider* cancelled. A patient who just tapped cancel
      // does not need to be told; sending it anyway is how an app teaches
      // people that its notifications are noise.
      if (isProvider) {
        await notify({
          userId: updated.patientId,
          kind: "APPOINTMENT_CHANGED",
          title: "Appointment cancelled",
          body: (doctorSnap.data() as DoctorDoc | undefined)?.name ?? "Your consultation",
          targetId: req.params.id,
        });
      }

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

      const result = await firestore.runTransaction(async (tx) => {
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

        // The freed slot is the *old* start, and it is only knowable inside
        // the transaction — `patch` has already overwritten it on the way out.
        return {
          appointment: { ...a, ...patch } as AppointmentDoc,
          freedSlotStart: oldStart,
        };
      });

      const updated = result.appointment;
      const freedSlotStart = result.freedSlotStart;

      const doctorSnap = await firestore.collection(C.doctors).doc(updated.doctorId).get();

      // Moving away frees the old time just as surely as cancelling does.
      await announceFreeSlot({
        doctorId: updated.doctorId,
        start: freedSlotStart,
        mode: updated.mode,
      });

      // Mandatory kind, and unconditional. Even when the patient moved it
      // themselves, this is the receipt — and when the provider moved it, it
      // is the only thing standing between them and travelling to the old time.
      await notify({
        userId: updated.patientId,
        kind: "APPOINTMENT_CHANGED",
        title: "Appointment moved",
        body: `Now ${istWhen(updated.start.toDate())}`,
        targetId: req.params.id,
      });

      res.json(
        appointmentJson(req.params.id, updated, updated.doctorId, doctorSnap.data() as DoctorDoc)
      );
    })
  );

  /**
   * Where this appointment stands in the doctor's queue today.
   *
   * Returns **four numbers and nothing else**. The derivation needs every other
   * appointment in that clinic — their times, statuses and, in the documents,
   * their patients' names — and a patient asking where they are in a queue has
   * no business receiving any of it. Computing this client-side would have
   * meant shipping the whole day's list to every phone in the waiting room.
   *
   * Not stored, either. A stored position needs rewriting every time anyone
   * checks in, is seen or cancels, and every missed recompute is a patient told
   * they are third when they are next.
   */
  r.get(
    "/:id/queue",
    handler(async (req, res) => {
      const firestore = db();
      const snap = await firestore.collection(C.appointments).doc(req.params.id).get();
      if (!snap.exists) throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");

      const mine = snap.data() as AppointmentDoc;
      const isProvider = req.auth!.role === "PROVIDER";
      const isParticipant = isProvider
        ? mine.doctorId === req.user!.doctorId
        : mine.patientId === req.auth!.sub;
      if (!isParticipant) {
        throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");
      }

      // The IST calendar day this appointment falls on. Bounded by instants
      // rather than filtered in memory: a busy doctor's whole history is not
      // something to read on every poll.
      const start = mine.start.toDate();
      const istMidnight = new Date(
        Math.floor((start.getTime() + IST_OFFSET_MS) / DAY_MS) * DAY_MS - IST_OFFSET_MS
      );

      const sameDay = await firestore
        .collection(C.appointments)
        .where("doctorId", "==", mine.doctorId)
        .where("start", ">=", Timestamp.fromDate(istMidnight))
        .where("start", "<", Timestamp.fromMillis(istMidnight.getTime() + DAY_MS))
        .get();

      let aheadOfYou = 0;
      let someoneInProgress = false;

      for (const doc of sameDay.docs) {
        if (doc.id === req.params.id) continue;
        const other = doc.data() as AppointmentDoc;

        if (other.status === "IN_PROGRESS") {
          // Being seen, not waiting — reported separately so a patient who is
          // next is not told the queue is empty while the doctor is busy.
          someoneInProgress = true;
        } else if (other.status === "CHECKED_IN") {
          // Counts regardless of slot time: arriving early is what checking in
          // means.
          aheadOfYou++;
        } else if (
          other.status === "CONFIRMED" &&
          other.start.toMillis() < mine.start.toMillis()
        ) {
          aheadOfYou++;
        }
        // Cancelled, completed and no-show drop out. They are why a queue
        // moves faster than the clock suggests.
      }

      const slotMinutes = Math.round(
        (mine.end.toMillis() - mine.start.toMillis()) / 60000
      );

      res.json({
        aheadOfYou,
        someoneInProgress,
        isCheckedIn: mine.status === "CHECKED_IN",
        averageConsultationMinutes: slotMinutes > 0 ? slotMinutes : 15,
      });
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
