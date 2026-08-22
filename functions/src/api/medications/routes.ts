import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { requireAuth, requireScope } from "../auth/middleware";
import { C, db, type MedicationDoseDoc, type PrescriptionDoc } from "../db";
import { handler, Problem } from "../errors";

/**
 * The dose log.
 *
 * The patient's own account of which tablets they took. Deliberately the
 * narrowest surface in the API:
 *
 *  - **It stores no dosing instructions.** A course is derived on the client
 *    from the prescription this same database already holds, so cancelling a
 *    prescription takes its schedule with it. A second copy here is how an app
 *    ends up reminding somebody to take a drug that was withdrawn.
 *  - **It is self-report, not a clinical record.** Nothing reads it back to a
 *    doctor, and no endpoint exposes another user's log. A "patient adherence"
 *    panel on the provider side would put a tick-box in front of a clinician
 *    as if it were an observation.
 *  - **Ids are derived, never generated.** `<prescriptionId>#<itemIndex>#
 *    <yyyy-mm-dd>#<SLOT>` — so a retried PUT after a dropped response is the
 *    same write rather than a second tablet in the log.
 */

const SLOTS = ["MORNING", "AFTERNOON", "EVENING", "NIGHT"] as const;
type Slot = (typeof SLOTS)[number];

const OUTCOMES = ["TAKEN", "SKIPPED"] as const;
type Outcome = (typeof OUTCOMES)[number];

/** How far back a listing may reach. */
const MAX_LOOKBACK_DAYS = 400;

interface ParsedDoseId {
  prescriptionId: string;
  itemIndex: number;
  day: string;
  slot: Slot;
}

/**
 * Reads a dose id back into its parts.
 *
 * Strict about every one of them: the id is user input on the path, and it is
 * also the document id, so a lenient parse is a way to write documents whose
 * ids do not mean what the collection assumes they mean.
 */
export function parseDoseId(raw: string): ParsedDoseId {
  const parts = raw.split("#");
  if (parts.length !== 4) throw Problem.notFound("DOSE_NOT_FOUND", "Not found.");

  const [prescriptionId, indexText, day, slot] = parts;
  const itemIndex = Number(indexText);
  if (
    !prescriptionId ||
    !Number.isInteger(itemIndex) ||
    itemIndex < 0 ||
    !/^\d{4}-\d{2}-\d{2}$/.test(day) ||
    !SLOTS.includes(slot as Slot)
  ) {
    throw Problem.notFound("DOSE_NOT_FOUND", "Not found.");
  }

  return { prescriptionId, itemIndex, day, slot: slot as Slot };
}

/** `YYYY-MM-DD` in IST, matching how the client draws the day. */
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

export function istDay(at: Date): string {
  return new Date(at.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
}

/** Whole days between two `YYYY-MM-DD` strings. */
export function daysBetween(from: string, to: string): number {
  const a = Date.parse(`${from}T00:00:00Z`);
  const b = Date.parse(`${to}T00:00:00Z`);
  return Math.round((b - a) / 86_400_000);
}

function doseJson(id: string, d: MedicationDoseDoc) {
  return {
    id,
    courseId: `${d.prescriptionId}#${d.itemIndex}`,
    day: d.day,
    slot: d.slot,
    outcome: d.outcome,
    markedAt: d.markedAt.toDate().toISOString(),
  };
}

/**
 * Confirms the dose belongs to a prescription this caller was issued, that the
 * prescription is still live, and that the day is inside the course.
 *
 * The date checks are the interesting ones. A client cannot be trusted to
 * refuse a future dose, and a log that accepts one produces a record of a
 * tablet nobody has taken which is indistinguishable from a record of one they
 * have.
 */
async function assertMarkable(
  userId: string,
  parsed: ParsedDoseId
): Promise<void> {
  const snap = await db()
    .collection(C.prescriptions)
    .doc(parsed.prescriptionId)
    .get();
  if (!snap.exists) {
    throw Problem.notFound("PRESCRIPTION_NOT_FOUND", "Not found.");
  }

  const prescription = snap.data() as PrescriptionDoc;
  if (prescription.patientId !== userId) {
    throw Problem.notFound("PRESCRIPTION_NOT_FOUND", "Not found.");
  }
  if (prescription.status !== "ISSUED") {
    throw Problem.conflict(
      "PRESCRIPTION_NOT_ACTIVE",
      "This prescription is no longer active."
    );
  }

  const item = prescription.items?.[parsed.itemIndex];
  if (!item) {
    throw Problem.notFound(
      "COURSE_NOT_FOUND",
      "That medicine is not on this prescription."
    );
  }

  const today = istDay(new Date());
  if (daysBetween(parsed.day, today) < 0) {
    throw Problem.validation("You can't tick off a dose that isn't due yet.", {
      day: "not_due",
    });
  }

  const startedOn = istDay(prescription.issuedAt.toDate());
  const dayIndex = daysBetween(startedOn, parsed.day);
  if (dayIndex < 0 || dayIndex > item.durationDays - 1) {
    throw Problem.validation("That day is outside this course.", {
      day: "outside_course",
    });
  }
}

export function medicationRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));
  // Reading your own prescriptions and logging what you took are the same
  // privilege: both are the patient's own medication record, and a separate
  // scope would gate nothing that this one does not already gate.
  r.use(requireScope("prescription:read_own"));

  /** `GET /v1/medications/doses?from=YYYY-MM-DD` */
  r.get(
    "/doses",
    handler(async (req, res) => {
      const from = String(req.query.from ?? "");
      if (!/^\d{4}-\d{2}-\d{2}$/.test(from)) {
        throw Problem.validation("A start date is required.", {
          from: "required",
        });
      }

      // Bounded, because the log grows a row per dose per day forever: four
      // long-term medicines is roughly 1,500 rows a year.
      const today = istDay(new Date());
      const span = daysBetween(from, today);
      const floor =
        span > MAX_LOOKBACK_DAYS
          ? istDay(new Date(Date.now() - MAX_LOOKBACK_DAYS * 86_400_000))
          : from;

      const snap = await db()
        .collection(C.medicationDoses)
        .where("userId", "==", req.auth!.sub)
        .where("day", ">=", floor)
        .orderBy("day")
        .get();

      res.json(
        snap.docs.map((d) => doseJson(d.id, d.data() as MedicationDoseDoc))
      );
    })
  );

  /** `PUT /v1/medications/doses/:id` — idempotent on a derived id. */
  r.put(
    "/doses/:id",
    handler(async (req, res) => {
      const parsed = parseDoseId(req.params.id);
      const outcome = String(req.body?.outcome ?? "");
      if (!OUTCOMES.includes(outcome as Outcome)) {
        throw Problem.validation("Unknown outcome.", { outcome: "invalid" });
      }

      await assertMarkable(req.auth!.sub, parsed);

      const doc: MedicationDoseDoc = {
        userId: req.auth!.sub,
        prescriptionId: parsed.prescriptionId,
        itemIndex: parsed.itemIndex,
        day: parsed.day,
        slot: parsed.slot,
        outcome: outcome as Outcome,
        // From the clock, not the request. "Taken, four hours late" and "taken
        // on time" are different facts, and a client-supplied timestamp lets
        // the log claim either.
        markedAt: Timestamp.now(),
      };

      await db().collection(C.medicationDoses).doc(req.params.id).set(doc);
      res.json(doseJson(req.params.id, doc));
    })
  );

  /**
   * `DELETE /v1/medications/doses/:id` — takes a mark back.
   *
   * A mis-tap has to be recoverable. This is the patient's own account of
   * their day, signed by nobody, and a tick that cannot be undone turns a fat
   * finger into a permanent claim about medication.
   */
  r.delete(
    "/doses/:id",
    handler(async (req, res) => {
      // Parsed for its validation only: a malformed id is refused before
      // it ever addresses a document.
      parseDoseId(req.params.id);
      const ref = db().collection(C.medicationDoses).doc(req.params.id);
      const snap = await ref.get();

      // Silent on a miss: deleting something that is not there is the state
      // the caller asked for, and reporting 404 differently for "never
      // existed" and "someone else's" would leak which ids are real.
      if (snap.exists) {
        const doc = snap.data() as MedicationDoseDoc;
        if (doc.userId !== req.auth!.sub) {
          throw Problem.notFound("DOSE_NOT_FOUND", "Not found.");
        }
        await ref.delete();
      }

      // A body rather than a bare 204, matching every other delete in this
      // API — `ApiClient` treats an empty response as a fault, so one
      // endpoint answering differently is a client-side error on success.
      res.json({ id: req.params.id, cleared: true });
    })
  );

  return r;
}
