import { randomUUID } from "crypto";
import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { requireAuth, requireScope } from "../auth/middleware";
import {
  C,
  db,
  slotLockId,
  type AppointmentDoc,
  type AvailabilityExceptionDoc,
  type AvailabilityRuleDoc,
  type ConsultationMode,
  type DoctorDoc,
  type SlotLockDoc,
} from "../db";
import { handler, Problem } from "../errors";
import { doctorJson } from "../doctors/routes";

/** Matches `SlotHold.duration` on the client. */
const HOLD_MINUTES = 10;

/** Reference code the patient can quote to support, e.g. MD-8K2P4Q. */
function referenceCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I/O/0/1
  let out = "";
  for (let i = 0; i < 6; i++) out += alphabet[Math.floor(Math.random() * alphabet.length)];
  return `MD-${out}`;
}

export function appointmentJson(id: string, a: AppointmentDoc, doctorId: string, doctor: DoctorDoc) {
  return {
    id,
    referenceCode: a.referenceCode,
    doctor: doctorJson(doctorId, doctor),
    patientId: a.patientId,
    patientName: a.patientName,
    start: a.start.toDate().toISOString(),
    end: a.end.toDate().toISOString(),
    mode: a.mode,
    status: a.status,
    paymentStatus: a.paymentStatus,
    feeInr: a.feeInr,
    reasonForVisit: a.reasonForVisit ?? null,
    cancellationReason: a.cancellationReason ?? null,
    consultationId: a.consultationId ?? null,
    hasPrescription: a.hasPrescription,
    hasRating: a.hasRating,
  };
}

/**
 * Materialises the slots for one doctor, day and mode from their availability
 * rules, then marks the ones already held or booked as unavailable.
 *
 * Slots are computed rather than stored: a stored slot table has to be
 * generated ahead of time and pruned behind, and every bug in that job shows up
 * as a doctor whose calendar silently stops. Only *taken* slots need durable
 * rows, and those are the `slotLocks`.
 */
/**
 * Whether a doctor has blocked an IST calendar day.
 *
 * Consulted by both the listing and the booking paths. Without it a blocked day
 * still materialises its weekly rules and stays bookable — the block would show
 * in the provider's own editor and change nothing a patient sees, which is the
 * worst kind of feature: one that looks like it worked.
 */
async function isDayBlocked(doctorId: string, isoDate: string): Promise<boolean> {
  const snap = await db()
    .collection(C.availabilityExceptions)
    .where("doctorId", "==", doctorId)
    .where("date", "==", isoDate)
    .get();

  return snap.docs.some((d) => (d.data() as AvailabilityExceptionDoc).isBlocked);
}

/** `YYYY-MM-DD` in IST for a UTC instant. */
function istDateString(instantMs: number): string {
  const shifted = new Date(instantMs + IST_OFFSET_MS);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, "0");
  const d = String(shifted.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

async function slotsFor(
  doctorId: string,
  day: { y: number; m: number; d: number },
  mode: ConsultationMode
) {
  const firestore = db();

  const rulesSnap = await firestore
    .collection(C.availabilityRules)
    .where("doctorId", "==", doctorId)
    .where("active", "==", true)
    .get();

  const dayStartMs = istMidnightUtcMs(day);

  // A blocked day has no slots at all, whatever the weekly rules say.
  if (await isDayBlocked(doctorId, istDateString(dayStartMs))) return [];

  // Dart's DateTime.weekday is 1..7 with Monday = 1; JS getUTCDay() is 0..6 with
  // Sunday = 0. Sunday must map to 7, not 0, or every Sunday rule is dead.
  const weekday = istWeekday(dayStartMs);

  const rules = rulesSnap.docs
    .map((d) => d.data() as AvailabilityRuleDoc)
    .filter((r) => r.weekday === weekday && r.mode === mode);

  const slots: { id: string; start: Date; end: Date; mode: ConsultationMode }[] = [];

  for (const rule of rules) {
    for (let m = rule.startMinutes; m + rule.slotMinutes <= rule.endMinutes; m += rule.slotMinutes) {
      const start = new Date(dayStartMs + m * 60_000);
      const end = new Date(start.getTime() + rule.slotMinutes * 60_000);
      slots.push({ id: slotLockId(doctorId, start), start, end, mode: rule.mode });
    }
  }

  if (slots.length === 0) return [];

  // One read per slot would be N round trips; getAll batches them.
  const lockRefs = slots.map((s) => firestore.collection(C.slotLocks).doc(s.id));
  const locks = await firestore.getAll(...lockRefs);
  const nowMs = Date.now();

  return slots.map((s, i) => {
    const lock = locks[i];
    let taken = false;
    if (lock.exists) {
      const l = lock.data() as SlotLockDoc;
      // An expired hold is not a booking: the slot returns to the pool rather
      // than being lost because someone opened the screen and walked away.
      taken = l.state === "BOOKED" || (l.holdExpiresAt?.toMillis() ?? 0) > nowMs;
    }
    return {
      id: s.id,
      start: s.start.toISOString(),
      end: s.end.toISOString(),
      mode: s.mode,
      isAvailable: !taken && s.start.getTime() > nowMs,
    };
  });
}

/**
 * India Standard Time, as a fixed offset from UTC.
 *
 * A fixed number rather than a timezone database lookup because India has a
 * single timezone and has never observed daylight saving, so +05:30 is exact
 * for every instant this product will ever handle.
 *
 * Availability has to be anchored to *something*, and the two obvious wrong
 * answers are the server's local time and the caller's. Cloud Functions runs in
 * UTC, so server-local would silently shift every doctor's hours by 5.5 hours;
 * caller-local would mean the same rule produced different slots depending on
 * where the patient was standing. A doctor's "10:00 clinic" means 10:00 where
 * the clinic is.
 */
const IST_OFFSET_MS = (5 * 60 + 30) * 60_000;

/**
 * Calendar Y-M-D, read from the date string without going through an instant.
 *
 * Anchored at both ends on purpose. An earlier version matched only a prefix,
 * which meant a caller could pass a full ISO timestamp and have its *text* day
 * used: `2026-03-15T20:00:00Z` is already the 16th in IST, so the request
 * quietly returned the wrong day's slots. A calendar day and an instant are
 * different things, and the only safe way to keep them apart is to refuse to
 * accept one where the other is meant.
 *
 * The component ranges are checked too, because `Date.UTC` silently rolls
 * 2026-13-45 forward into the following year rather than failing.
 */
export function istCalendarDate(raw: string): { y: number; m: number; d: number } | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!match) return null;

  const y = Number(match[1]);
  const m = Number(match[2]);
  const d = Number(match[3]);
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;

  // Rejects 31 April and 29 February in a common year: if the components
  // survive a round trip, the day exists.
  const probe = new Date(Date.UTC(y, m - 1, d));
  if (probe.getUTCFullYear() !== y || probe.getUTCMonth() !== m - 1 || probe.getUTCDate() !== d) {
    return null;
  }

  return { y, m, d };
}

/** Midnight IST on the given calendar day, as a UTC instant. */
export function istMidnightUtcMs(date: { y: number; m: number; d: number }): number {
  return Date.UTC(date.y, date.m - 1, date.d) - IST_OFFSET_MS;
}

/** ISO weekday (1 = Monday … 7 = Sunday) of an instant, read in IST. */
export function istWeekday(instantMs: number): number {
  const shifted = new Date(instantMs + IST_OFFSET_MS);
  const day = shifted.getUTCDay();
  return day === 0 ? 7 : day;
}

/** Parses `<doctorId>__<startMillis>` back into its parts. */
export function parseSlotId(slotId: string): { doctorId: string; startMs: number } {
  const sep = slotId.lastIndexOf("__");
  if (sep < 0) throw Problem.validation("Malformed slot id.", { slotId: "invalid" });
  const doctorId = slotId.slice(0, sep);
  const startMs = Number(slotId.slice(sep + 2));
  if (!doctorId || !Number.isFinite(startMs)) {
    throw Problem.validation("Malformed slot id.", { slotId: "invalid" });
  }
  return { doctorId, startMs };
}

/**
 * Mounted at the broad `/v1` prefix, so authentication is attached per route
 * rather than with `r.use`. A router-wide guard here would run for every
 * unmatched `/v1/...` path too, turning the app's 404 into a 401 and making the
 * not-found handler unreachable.
 */
/**
 * Resolves the availability rule that makes a slot real, or refuses it.
 *
 * Shared by the hold and confirm paths so the two cannot drift: a slot that can
 * be held is by definition one that can be booked.
 */
async function bookableRule(
  doctorId: string,
  startMs: number,
  mode?: ConsultationMode
): Promise<{ rule: AvailabilityRuleDoc; doctor: DoctorDoc }> {
  const firestore = db();

  const doctorSnap = await firestore.collection(C.doctors).doc(doctorId).get();
  if (!doctorSnap.exists) throw Problem.notFound("DOCTOR_NOT_FOUND", "Doctor not found.");
  const doctor = doctorSnap.data() as DoctorDoc;
  if (doctor.providerStatus !== "APPROVED") {
    throw Problem.forbidden("PROVIDER_NOT_APPROVED", "This doctor is not accepting bookings.");
  }

  if (startMs <= Date.now()) {
    throw Problem.conflict("SLOT_IN_PAST", "That time has already passed.");
  }

  const rulesSnap = await firestore
    .collection(C.availabilityRules)
    .where("doctorId", "==", doctorId)
    .where("active", "==", true)
    .get();

  const weekday = istWeekday(startMs);
  // Minutes past IST midnight, derived by shifting into IST, truncating to the
  // day, and shifting back — the same arithmetic `istMidnightUtcMs` performs,
  // but starting from an instant rather than a calendar date.
  const DAY_MS = 24 * 60 * 60 * 1000;
  const dayStartMs = Math.floor((startMs + IST_OFFSET_MS) / DAY_MS) * DAY_MS - IST_OFFSET_MS;
  const minuteOfDay = (startMs - dayStartMs) / 60_000;

  const rule = rulesSnap.docs
    .map((d) => d.data() as AvailabilityRuleDoc)
    .find(
      (x) =>
        x.weekday === weekday &&
        (mode === undefined || x.mode === mode) &&
        minuteOfDay >= x.startMinutes &&
        minuteOfDay + x.slotMinutes <= x.endMinutes &&
        // Slots are materialised on a fixed stride from the rule's start, so an
        // arbitrary instant inside the window is still not a slot.
        (minuteOfDay - x.startMinutes) % x.slotMinutes === 0
    );

  if (!rule) throw Problem.conflict("SLOT_UNAVAILABLE", "That slot is no longer offered.");

  // Checked here as well as in the listing: a slot id held from before the day
  // was blocked would otherwise still confirm.
  if (await isDayBlocked(doctorId, istDateString(startMs))) {
    throw Problem.conflict("DAY_BLOCKED", "The doctor is not available that day.");
  }

  return { rule, doctor };
}

export function bookingRoutes(secret: () => string): Router {
  const r = Router();

  /**
   * Availability is part of the public doctor catalogue. A person may inspect
   * a doctor's open times before deciding to create an account; holding or
   * booking a time remains authenticated below. Keeping these distinct also
   * prevents the guest booking screen from waiting for an auth refresh before
   * it can show the calendar.
   */
  r.get(
    "/doctors/:id/slots",
    handler(async (req, res) => {
      const { date, mode } = req.query;
      if (typeof date !== "string" || typeof mode !== "string") {
        throw Problem.validation("date and mode are required.", {
          date: typeof date === "string" ? "" : "required",
          mode: typeof mode === "string" ? "" : "required",
        });
      }
      // Only the calendar day is read. Parsing the string into an instant first
      // would reintroduce the server's timezone as a hidden input.
      const day = istCalendarDate(date);
      if (!day) throw Problem.validation("Invalid date.", { date: "invalid" });

      res.json({ items: await slotsFor(req.params.id, day, mode as ConsultationMode) });
    })
  );

  /**
   * Takes a short-lived hold on a slot.
   *
   * The hold and the booking write the same document, so a hold already
   * establishes exclusivity — the confirm step then only has to check that the
   * hold is still ours.
   */
  r.post(
    "/slots/:slotId/hold",
    requireAuth(secret),
    requireScope("appointment:create"),
    handler(async (req, res) => {
      const { doctorId, startMs } = parseSlotId(req.params.slotId);
      const userId = req.auth!.sub;
      const firestore = db();

      // A slot id is a claim, not a fact — it is just a doctor id and a
      // millisecond value the caller assembled. Without this check any
      // authenticated patient could mint `slotLocks` documents for doctors who
      // do not exist, at times nobody offers, without limit, and nothing
      // collects them. The confirm path has always validated this; the hold
      // path is reached first.
      const { rule } = await bookableRule(doctorId, startMs);
      const lockRef = firestore.collection(C.slotLocks).doc(req.params.slotId);

      const expiresAt = Timestamp.fromMillis(Date.now() + HOLD_MINUTES * 60_000);

      await firestore.runTransaction(async (tx) => {
        const snap = await tx.get(lockRef);

        if (snap.exists) {
          const lock = snap.data() as SlotLockDoc;
          if (lock.state === "BOOKED") {
            throw Problem.conflict("SLOT_TAKEN", "Someone booked this slot first.");
          }
          const heldUntil = lock.holdExpiresAt?.toMillis() ?? 0;
          if (heldUntil > Date.now() && lock.heldBy !== userId) {
            throw Problem.conflict("SLOT_TAKEN", "Someone is booking this slot right now.");
          }
        }

        const doc: SlotLockDoc = {
          doctorId,
          start: Timestamp.fromMillis(startMs),
          end: Timestamp.fromMillis(startMs + rule.slotMinutes * 60_000),
          state: "HELD",
          heldBy: userId,
          holdExpiresAt: expiresAt,
          appointmentId: null,
        };
        tx.set(lockRef, doc, { merge: true });
      });

      res.json({ slotId: req.params.slotId, expiresAt: expiresAt.toDate().toISOString() });
    })
  );

  r.delete(
    "/slots/:slotId/hold",
    requireAuth(secret),
    requireScope("appointment:create"),
    handler(async (req, res) => {
      const firestore = db();
      const lockRef = firestore.collection(C.slotLocks).doc(req.params.slotId);

      await firestore.runTransaction(async (tx) => {
        const snap = await tx.get(lockRef);
        if (!snap.exists) return;
        const lock = snap.data() as SlotLockDoc;
        // Never let a release delete somebody else's booking.
        if (lock.state === "HELD" && lock.heldBy === req.auth!.sub) tx.delete(lockRef);
      });

      res.json({ ok: true });
    })
  );

  return r;
}

/**
 * Mounted at `/v1/appointments`, separately from [bookingRoutes], so that
 * creating an appointment lives under the same path that lists them and no
 * route depends on Express fall-through order to be reached.
 */
export function appointmentCreateRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  /**
   * Confirms a booking.
   *
   * The whole no-double-booking guarantee lives in this transaction. Both
   * callers address the *same* `slotLocks` document id, derived from the doctor
   * and the exact start instant, so Firestore serialises them: the second
   * commit sees the first one's write and aborts. This is the Firestore
   * equivalent of a Postgres exclusion constraint, and it is the reason slot
   * ids are deterministic rather than random.
   */
  r.post(
    "/",
    requireScope("appointment:create"),
    handler(async (req, res) => {
      const { slotId, mode, patientName, reasonForVisit } = req.body ?? {};
      if (typeof slotId !== "string" || typeof mode !== "string") {
        throw Problem.validation("slotId and mode are required.", {
          slotId: typeof slotId === "string" ? "" : "required",
          mode: typeof mode === "string" ? "" : "required",
        });
      }

      const { doctorId, startMs } = parseSlotId(slotId);
      const userId = req.auth!.sub;
      const firestore = db();

      // Doctor exists and is approved, the slot is in the future, and it lands
      // on a real stride of a live availability rule offering this mode. Slot
      // length comes from that rule, so a 20-minute practice does not silently
      // become 30.
      const { rule, doctor } = await bookableRule(doctorId, startMs, mode as ConsultationMode);
      const endMs = startMs + rule.slotMinutes * 60_000;
      const appointmentId = randomUUID();
      const lockRef = firestore.collection(C.slotLocks).doc(slotId);
      const apptRef = firestore.collection(C.appointments).doc(appointmentId);

      const appointment: AppointmentDoc = {
        referenceCode: referenceCode(),
        doctorId,
        patientId: userId,
        patientName:
          typeof patientName === "string" && patientName.trim()
            ? patientName.trim()
            : (req.user!.displayName ?? "Patient"),
        start: Timestamp.fromMillis(startMs),
        end: Timestamp.fromMillis(endMs),
        mode: mode as ConsultationMode,
        // Payments are deferred (BookingPolicy.requiresPayment is false on the
        // client), so a held slot goes straight to CONFIRMED. Turning payments
        // on inserts PENDING_PAYMENT here and changes nothing else.
        status: "CONFIRMED",
        paymentStatus: "NOT_REQUIRED",
        feeInr: mode === "IN_PERSON" ? doctor.consultationFeeInr : doctor.videoFeeInr,
        reasonForVisit: typeof reasonForVisit === "string" ? reasonForVisit : null,
        cancellationReason: null,
        consultationId: mode === "IN_PERSON" ? null : appointmentId,
        hasPrescription: false,
        hasRating: false,
        createdAt: Timestamp.now(),
      };

      await firestore.runTransaction(async (tx) => {
        const snap = await tx.get(lockRef);

        if (snap.exists) {
          const lock = snap.data() as SlotLockDoc;
          if (lock.state === "BOOKED") {
            throw Problem.conflict("SLOT_TAKEN", "Someone booked this slot first.");
          }
          const heldUntil = lock.holdExpiresAt?.toMillis() ?? 0;
          if (heldUntil > Date.now() && lock.heldBy !== userId) {
            throw Problem.conflict("SLOT_TAKEN", "Someone booked this slot first.");
          }
        }

        const lockDoc: SlotLockDoc = {
          doctorId,
          start: Timestamp.fromMillis(startMs),
          end: Timestamp.fromMillis(endMs),
          state: "BOOKED",
          heldBy: userId,
          holdExpiresAt: null,
          appointmentId,
        };
        tx.set(lockRef, lockDoc);
        tx.set(apptRef, appointment);
      });

      res.status(201).json(appointmentJson(appointmentId, appointment, doctorId, doctor));
    })
  );

  return r;
}
