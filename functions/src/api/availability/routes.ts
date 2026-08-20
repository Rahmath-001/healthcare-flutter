import { randomUUID } from "crypto";
import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { requireAuth, requireScope } from "../auth/middleware";
import {
  C,
  db,
  type AvailabilityExceptionDoc,
  type AvailabilityRuleDoc,
  type ConsultationMode,
} from "../db";
import { handler, Problem } from "../errors";

/**
 * A provider's own working hours.
 *
 * Slots are never stored — they are materialised on demand from these rules
 * (see `booking/routes.ts`). That means editing a rule takes effect instantly
 * and there is no generation job to fall behind, but it also means these
 * documents are the only description of when a doctor works: a bad write here
 * silently empties a calendar.
 *
 * All times are minutes past midnight **IST**. India has one timezone and no
 * daylight saving, so a wall-clock time is unambiguous — but it is only
 * unambiguous because everything reading it agrees on the offset.
 */

const MODES: ConsultationMode[] = ["VIDEO", "AUDIO", "IN_PERSON"];

/**
 * Slot lengths a practice may choose.
 *
 * A closed set rather than any integer: slots are materialised on a fixed
 * stride from the rule's start, and `bookableRule` re-derives that stride when
 * validating a hold. An 7-minute slot would work but makes every downstream
 * calculation harder to reason about for no clinical gain.
 */
const SLOT_MINUTES = [10, 15, 20, 30, 45, 60];

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

function ruleJson(id: string, r: AvailabilityRuleDoc) {
  return {
    id,
    weekday: r.weekday,
    startMinutes: r.startMinutes,
    endMinutes: r.endMinutes,
    mode: r.mode,
    slotMinutes: r.slotMinutes,
    active: r.active,
  };
}

function exceptionJson(id: string, e: AvailabilityExceptionDoc) {
  return {
    id,
    date: e.date,
    isBlocked: e.isBlocked,
    startMinutes: e.startMinutes ?? null,
    endMinutes: e.endMinutes ?? null,
    reason: e.reason ?? null,
  };
}

/** The doctor profile the caller owns, or a refusal. */
function doctorIdOf(req: Express.Request): string {
  const doctorId = req.user!.doctorId;
  if (!doctorId) {
    throw Problem.forbidden("NOT_A_PROVIDER", "Only a provider has availability.");
  }
  return doctorId;
}

export function availabilityRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  r.get(
    "/rules",
    requireScope("availability:write"),
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.availabilityRules)
        .where("doctorId", "==", doctorIdOf(req))
        .get();

      const rules = snap.docs
        .map((d) => ({ id: d.id, r: d.data() as AvailabilityRuleDoc }))
        .sort((a, b) =>
          a.r.weekday === b.r.weekday
            ? a.r.startMinutes - b.r.startMinutes
            : a.r.weekday - b.r.weekday
        );

      res.json(rules.map(({ id, r: rule }) => ruleJson(id, rule)));
    })
  );

  r.post(
    "/rules",
    requireScope("availability:write"),
    handler(async (req, res) => {
      const doctorId = doctorIdOf(req);
      const { weekday, startMinutes, endMinutes, mode, slotMinutes } = req.body ?? {};

      if (!Number.isInteger(weekday) || weekday < 1 || weekday > 7) {
        throw Problem.validation("Pick a day of the week.", { weekday: "invalid" });
      }
      if (!MODES.includes(mode)) {
        throw Problem.validation("Unknown consultation mode.", { mode: "invalid" });
      }
      if (!SLOT_MINUTES.includes(slotMinutes)) {
        throw Problem.validation("Unsupported appointment length.", {
          slotMinutes: "invalid",
        });
      }
      if (
        !Number.isInteger(startMinutes) ||
        !Number.isInteger(endMinutes) ||
        startMinutes < 0 ||
        endMinutes > 24 * 60
      ) {
        throw Problem.validation("Enter valid times.", { startMinutes: "invalid" });
      }
      if (endMinutes - startMinutes < slotMinutes) {
        throw Problem.validation("That window is shorter than one appointment.", {
          endMinutes: "too early",
        });
      }

      // Overlapping windows for the same day and mode would materialise the
      // same instant twice, and the two copies would carry different slot
      // lengths. The slot id is derived from the start instant alone, so the
      // second one is not a second slot — it is a collision.
      const existing = await db()
        .collection(C.availabilityRules)
        .where("doctorId", "==", doctorId)
        .where("active", "==", true)
        .get();

      const clash = existing.docs
        .map((d) => d.data() as AvailabilityRuleDoc)
        .find(
          (x) =>
            x.weekday === weekday &&
            x.mode === mode &&
            startMinutes < x.endMinutes &&
            endMinutes > x.startMinutes
        );
      if (clash) {
        throw Problem.conflict(
          "RULE_OVERLAPS",
          "That overlaps hours you have already set for this day."
        );
      }

      const id = randomUUID();
      const doc: AvailabilityRuleDoc = {
        doctorId,
        weekday,
        startMinutes,
        endMinutes,
        mode,
        slotMinutes,
        active: true,
      };
      await db().collection(C.availabilityRules).doc(id).set(doc);
      res.status(201).json(ruleJson(id, doc));
    })
  );

  r.post(
    "/rules/:id/toggle",
    requireScope("availability:write"),
    handler(async (req, res) => {
      const { active } = req.body ?? {};
      if (typeof active !== "boolean") {
        throw Problem.validation("Expected true or false.", { active: "invalid" });
      }

      const ref = db().collection(C.availabilityRules).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists || (snap.data() as AvailabilityRuleDoc).doctorId !== doctorIdOf(req)) {
        throw Problem.notFound("RULE_NOT_FOUND", "Those hours no longer exist.");
      }

      await ref.update({ active });
      res.json(ruleJson(req.params.id, {
        ...(snap.data() as AvailabilityRuleDoc),
        active,
      }));
    })
  );

  /**
   * Removes a rule.
   *
   * Appointments already booked inside it are untouched: they are commitments
   * to a patient, not a projection of the rule. A doctor who stops offering
   * Tuesday mornings still owes the people who booked one.
   */
  r.delete(
    "/rules/:id",
    requireScope("availability:write"),
    handler(async (req, res) => {
      const ref = db().collection(C.availabilityRules).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists || (snap.data() as AvailabilityRuleDoc).doctorId !== doctorIdOf(req)) {
        throw Problem.notFound("RULE_NOT_FOUND", "Those hours no longer exist.");
      }
      await ref.delete();
      res.json({ ok: true });
    })
  );

  r.get(
    "/exceptions",
    requireScope("availability:write"),
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.availabilityExceptions)
        .where("doctorId", "==", doctorIdOf(req))
        .get();

      const items = snap.docs
        .map((d) => ({ id: d.id, e: d.data() as AvailabilityExceptionDoc }))
        .sort((a, b) => a.e.date.localeCompare(b.e.date));

      res.json(items.map(({ id, e }) => exceptionJson(id, e)));
    })
  );

  /**
   * Blocks a single day.
   *
   * Existing appointments are reported back rather than silently cancelled —
   * deciding what happens to a patient who has already booked is the doctor's
   * call, not a side effect of tapping a date.
   */
  r.post(
    "/exceptions",
    requireScope("availability:write"),
    handler(async (req, res) => {
      const doctorId = doctorIdOf(req);
      const { date, reason } = req.body ?? {};

      if (typeof date !== "string" || !DATE_ONLY.test(date)) {
        throw Problem.validation("Pick a date.", { date: "invalid" });
      }

      const id = randomUUID();
      const doc: AvailabilityExceptionDoc = {
        doctorId,
        date,
        isBlocked: true,
        reason: typeof reason === "string" && reason.trim() ? reason.trim() : null,
        createdAt: Timestamp.now(),
      };
      await db().collection(C.availabilityExceptions).doc(id).set(doc);

      const dayStart = Date.parse(`${date}T00:00:00+05:30`);
      const booked = await db()
        .collection(C.appointments)
        .where("doctorId", "==", doctorId)
        .where("status", "==", "CONFIRMED")
        .get();

      const affected = booked.docs.filter((d) => {
        const startMs = (d.data().start as Timestamp).toMillis();
        return startMs >= dayStart && startMs < dayStart + 24 * 60 * 60 * 1000;
      }).length;

      res.status(201).json({ ...exceptionJson(id, doc), existingAppointments: affected });
    })
  );

  r.delete(
    "/exceptions/:id",
    requireScope("availability:write"),
    handler(async (req, res) => {
      const ref = db().collection(C.availabilityExceptions).doc(req.params.id);
      const snap = await ref.get();
      if (
        !snap.exists ||
        (snap.data() as AvailabilityExceptionDoc).doctorId !== doctorIdOf(req)
      ) {
        throw Problem.notFound("EXCEPTION_NOT_FOUND", "That day is no longer blocked.");
      }
      await ref.delete();
      res.json({ ok: true });
    })
  );

  return r;
}
