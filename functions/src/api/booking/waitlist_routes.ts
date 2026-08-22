import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import { requireAuth } from "../auth/middleware";
import { C, db, type DoctorDoc, type WaitlistEntryDoc } from "../db";
import { handler, Problem } from "../errors";
import { notify } from "../notifications/send";

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;
const MODES = ["IN_PERSON", "VIDEO", "AUDIO"];

/** How long an "any day" entry stays alive. */
const OPEN_ENDED_DAYS = 30;

/**
 * A cap on how many people hear about one freed slot.
 *
 * Not fairness — everyone matching is notified, in the order they joined — but
 * a limit on the size of a single fan-out. A popular doctor cancelling one
 * afternoon should not send two thousand pushes in one request.
 */
const MAX_ANNOUNCE = 50;

function waitlistJson(id: string, e: WaitlistEntryDoc) {
  return {
    id,
    doctorId: e.doctorId,
    doctorName: e.doctorName,
    mode: e.mode,
    createdAt: e.createdAt.toDate().toISOString(),
    status: e.status,
    preferredDate: e.preferredDate ?? null,
    notifiedAt: e.notifiedAt ? e.notifiedAt.toDate().toISOString() : null,
  };
}

export function waitlistRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  r.get(
    "/",
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.waitlist)
        .where("patientId", "==", req.auth!.sub)
        .orderBy("createdAt", "desc")
        .limit(50)
        .get();

      res.json(
        snap.docs.map((d) => waitlistJson(d.id, d.data() as WaitlistEntryDoc))
      );
    })
  );

  /**
   * Joins the list for a doctor.
   *
   * The doctor's name is snapshotted here from the directory rather than
   * accepted from the request: a client that could supply it could put itself
   * on a list under any name it liked, and the entry is shown back to the user
   * later as fact.
   */
  r.post(
    "/",
    handler(async (req, res) => {
      const { doctorId, mode, preferredDate } = req.body ?? {};

      if (typeof doctorId !== "string" || !doctorId) {
        throw Problem.validation("Which doctor?", { doctorId: "required" });
      }
      if (!MODES.includes(mode)) {
        throw Problem.validation("Unknown consultation type.", { mode: "invalid" });
      }
      if (preferredDate !== undefined && preferredDate !== null) {
        if (typeof preferredDate !== "string" || !DATE_ONLY.test(preferredDate)) {
          throw Problem.validation("Invalid date.", { preferredDate: "invalid" });
        }
      }

      const doctorSnap = await db().collection(C.doctors).doc(doctorId).get();
      if (!doctorSnap.exists) throw Problem.notFound("DOCTOR_NOT_FOUND", "Not found.");
      const doctor = doctorSnap.data() as DoctorDoc;

      const existing = await db()
        .collection(C.waitlist)
        .where("patientId", "==", req.auth!.sub)
        .where("doctorId", "==", doctorId)
        .where("status", "==", "WAITING")
        .get();

      const duplicate = existing.docs.some((d) => {
        const e = d.data() as WaitlistEntryDoc;
        return e.mode === mode && (e.preferredDate ?? null) === (preferredDate ?? null);
      });
      if (duplicate) {
        throw Problem.conflict("ALREADY_WAITING", "You are already on the list for this doctor.");
      }

      const doc: WaitlistEntryDoc = {
        patientId: req.auth!.sub,
        doctorId,
        doctorName: doctor.name,
        mode,
        preferredDate: preferredDate ?? null,
        createdAt: Timestamp.now(),
        status: "WAITING",
        notifiedAt: null,
      };

      const ref = await db().collection(C.waitlist).add(doc);
      res.status(201).json(waitlistJson(ref.id, doc));
    })
  );

  r.delete(
    "/:id",
    handler(async (req, res) => {
      const ref = db().collection(C.waitlist).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("WAITLIST_NOT_FOUND", "Not found.");

      const entry = snap.data() as WaitlistEntryDoc;
      if (entry.patientId !== req.auth!.sub) {
        throw Problem.notFound("WAITLIST_NOT_FOUND", "Not found.");
      }

      await ref.update({ status: "CANCELLED" });
      res.json(waitlistJson(req.params.id, { ...entry, status: "CANCELLED" }));
    })
  );

  return r;
}

/**
 * Tells everyone waiting that a slot opened.
 *
 * Called wherever a slot returns to the pool — a cancellation, or a reschedule
 * moving away from it.
 *
 * **Everyone matching, not the first in line.** Holding a freed slot for
 * whoever happens to be at the top of a list means it sits empty while they
 * are asleep, on a train or no longer interested, which is exactly the waste
 * the cancellation was supposed to recover. The notification says it is first
 * come, first served.
 *
 * Each entry is marked NOTIFIED, which is terminal: one that stayed active
 * would ping the same person on every cancellation for the rest of the month,
 * and the third of those is where people turn notifications off — which on
 * this app also silences their appointment reminders.
 *
 * Never throws. It runs after a cancellation that has already been committed,
 * and a push failure must not roll back somebody's cancellation.
 */
export async function announceFreeSlot(params: {
  doctorId: string;
  start: Date;
  mode: string;
}): Promise<number> {
  try {
    const now = new Date();
    const day = istDay(params.start);

    const snap = await db()
      .collection(C.waitlist)
      .where("doctorId", "==", params.doctorId)
      .where("status", "==", "WAITING")
      .where("mode", "==", params.mode)
      .limit(MAX_ANNOUNCE)
      .get();

    // A slot that has already started helps nobody.
    if (params.start.getTime() <= now.getTime()) return 0;

    const matches = snap.docs
      .map((d) => ({ id: d.id, e: d.data() as WaitlistEntryDoc }))
      .filter(({ e }) => {
        if (e.preferredDate) return e.preferredDate === day;
        const ageMs = now.getTime() - e.createdAt.toMillis();
        return ageMs < OPEN_ENDED_DAYS * 24 * 60 * 60 * 1000;
      })
      // Oldest first: the order people joined is the only ordering anybody
      // would call fair, even though all of them are told.
      .sort((a, b) => a.e.createdAt.toMillis() - b.e.createdAt.toMillis());

    if (matches.length === 0) return 0;

    const batch = db().batch();
    const at = Timestamp.now();
    for (const { id } of matches) {
      batch.update(db().collection(C.waitlist).doc(id), {
        status: "NOTIFIED",
        notifiedAt: at,
      });
    }
    await batch.commit();

    for (const { e } of matches) {
      await notify({
        userId: e.patientId,
        kind: "APPOINTMENT_REMINDER",
        title: "A slot opened",
        body: `${e.doctorName} · first come, first served`,
        targetId: e.doctorId,
      });
    }

    return matches.length;
  } catch (err) {
    logger.error("Waitlist announcement failed", {
      doctorId: params.doctorId,
      error: err instanceof Error ? err.message : "unknown",
    });
    return 0;
  }
}

/** The IST calendar day of an instant, as `YYYY-MM-DD`. */
function istDay(at: Date): string {
  const ist = new Date(at.getTime() + 5.5 * 60 * 60 * 1000);
  return ist.toISOString().slice(0, 10);
}
