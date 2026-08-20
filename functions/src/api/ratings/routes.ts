import { randomUUID } from "crypto";
import { Router } from "express";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { requireAuth, requireScope } from "../auth/middleware";
import { C, db, type AppointmentDoc, type RatingDoc } from "../db";
import { handler, Problem } from "../errors";

/**
 * Ratings.
 *
 * The spec lets patients filter search results by rating and never says where a
 * rating comes from. These are the rules that close that gap, and each exists
 * because the obvious alternative is exploitable:
 *
 *  - **One per completed appointment**, keyed by appointment id, so the rating
 *    count cannot be inflated by anyone who has not actually been seen.
 *  - **Editable for 14 days**, so a patient can revise a first impression but
 *    an old rating cannot be quietly rewritten years later.
 *  - **Moderated before publication.** Search ranks on this number, so an
 *    unmoderated channel is a direct lever on which doctors get seen — and the
 *    free-text comment is a direct channel to other patients.
 */

const EDIT_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;
const MAX_COMMENT = 500;

function ratingJson(id: string, r: RatingDoc) {
  return {
    id,
    appointmentId: r.appointmentId,
    doctorName: r.doctorName,
    stars: r.stars,
    createdAt: r.createdAt.toDate().toISOString(),
    status: r.status,
    comment: r.comment ?? null,
    editedAt: r.editedAt ? r.editedAt.toDate().toISOString() : null,
  };
}

function assertStars(value: unknown): number {
  if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > 5) {
    throw Problem.validation("Choose between one and five stars.", { stars: "invalid" });
  }
  return value as number;
}

function assertComment(value: unknown): string | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") {
    throw Problem.validation("Expected text.", { comment: "invalid" });
  }
  const trimmed = value.trim();
  if (trimmed.length > MAX_COMMENT) {
    throw Problem.validation(`Keep it under ${MAX_COMMENT} characters.`, {
      comment: "too long",
    });
  }
  return trimmed || null;
}

/**
 * Recomputes a doctor's published average.
 *
 * Derived rather than incrementally maintained: a running total drifts the
 * moment a rating is edited or a moderator hides one, and the drift is silent.
 * Recomputing costs one query on a write path nobody hits often.
 */
async function recomputeDoctorRating(doctorId: string): Promise<void> {
  const snap = await db()
    .collection(C.ratings)
    .where("doctorId", "==", doctorId)
    .where("status", "==", "PUBLISHED")
    .get();

  const stars = snap.docs.map((d) => (d.data() as RatingDoc).stars);
  const count = stars.length;
  const average = count === 0 ? 0 : stars.reduce((a, b) => a + b, 0) / count;

  await db()
    .collection(C.doctors)
    .doc(doctorId)
    .update({ rating: Math.round(average * 10) / 10, ratingCount: count });
}

export function ratingRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  r.get(
    "/",
    handler(async (req, res) => {
      // A patient sees the ratings they wrote; a provider sees the ones written
      // about them, and only the published ones.
      const isProvider = req.user!.role === "PROVIDER";
      const query = isProvider
        ? db()
            .collection(C.ratings)
            .where("doctorId", "==", req.user!.doctorId ?? "__none__")
            .where("status", "==", "PUBLISHED")
        : db().collection(C.ratings).where("patientId", "==", req.auth!.sub);

      const snap = await query.get();
      const items = snap.docs
        .map((d) => ({ id: d.id, r: d.data() as RatingDoc }))
        .sort((a, b) => b.r.createdAt.toMillis() - a.r.createdAt.toMillis());

      res.json(items.map(({ id, r: rating }) => ratingJson(id, rating)));
    })
  );

  r.post(
    "/",
    requireScope("rating:write"),
    handler(async (req, res) => {
      const { appointmentId } = req.body ?? {};
      const stars = assertStars(req.body?.stars);
      const comment = assertComment(req.body?.comment);

      if (typeof appointmentId !== "string" || !appointmentId) {
        throw Problem.validation("Which appointment?", { appointmentId: "required" });
      }

      const apptSnap = await db().collection(C.appointments).doc(appointmentId).get();
      if (!apptSnap.exists) {
        throw Problem.notFound("APPOINTMENT_NOT_FOUND", "Appointment not found.");
      }
      const appt = apptSnap.data() as AppointmentDoc;

      if (appt.patientId !== req.auth!.sub) {
        throw Problem.forbidden("NOT_YOUR_APPOINTMENT", "That is not your appointment.");
      }
      if (appt.status !== "COMPLETED") {
        throw Problem.conflict(
          "APPOINTMENT_NOT_COMPLETED",
          "You can rate a consultation once it has finished."
        );
      }

      // The appointment id *is* the rating id. Uniqueness is then a property of
      // the database rather than a check that can race itself.
      const ref = db().collection(C.ratings).doc(appointmentId);
      if ((await ref.get()).exists) {
        throw Problem.conflict("ALREADY_RATED", "You have already rated this consultation.");
      }

      const doctorSnap = await db().collection(C.doctors).doc(appt.doctorId).get();
      const doc: RatingDoc = {
        appointmentId,
        patientId: req.auth!.sub,
        doctorId: appt.doctorId,
        doctorName: (doctorSnap.data()?.name as string | undefined) ?? "Your doctor",
        stars,
        comment,
        // Never PUBLISHED on creation, whatever the content.
        status: "PENDING_MODERATION",
        createdAt: Timestamp.now(),
        editedAt: null,
      };

      await ref.set(doc);
      await apptSnap.ref.update({ hasRating: true });

      res.status(201).json(ratingJson(appointmentId, doc));
    })
  );

  r.put(
    "/:id",
    requireScope("rating:write"),
    handler(async (req, res) => {
      const stars = assertStars(req.body?.stars);
      const comment = assertComment(req.body?.comment);

      const ref = db().collection(C.ratings).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("RATING_NOT_FOUND", "Rating not found.");

      const rating = snap.data() as RatingDoc;
      if (rating.patientId !== req.auth!.sub) {
        throw Problem.forbidden("NOT_YOUR_RATING", "That is not your rating.");
      }
      if (rating.status === "REMOVED") {
        throw Problem.conflict("RATING_REMOVED", "This rating has been removed.");
      }
      if (Date.now() - rating.createdAt.toMillis() > EDIT_WINDOW_MS) {
        throw Problem.conflict(
          "EDIT_WINDOW_CLOSED",
          "Ratings can only be changed within 14 days."
        );
      }

      const editedAt = Timestamp.now();
      // An edited rating re-enters moderation. Otherwise the review queue is
      // trivially bypassed: submit something bland, wait for approval, rewrite.
      await ref.update({
        stars,
        comment,
        editedAt,
        status: "PENDING_MODERATION",
      });
      await recomputeDoctorRating(rating.doctorId);

      res.json(
        ratingJson(req.params.id, {
          ...rating,
          stars,
          comment,
          editedAt,
          status: "PENDING_MODERATION",
        })
      );
    })
  );

  /**
   * Moderation. Supervisors and admins only.
   *
   * Publishing is what makes a rating count towards a doctor's average, so this
   * is the only path that can move the number search ranks on.
   */
  r.post(
    "/:id/moderate",
    requireScope("provider:review"),
    handler(async (req, res) => {
      const { status } = req.body ?? {};
      if (!["PUBLISHED", "HIDDEN", "REMOVED"].includes(status)) {
        throw Problem.validation("Unknown moderation outcome.", { status: "invalid" });
      }

      const ref = db().collection(C.ratings).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("RATING_NOT_FOUND", "Rating not found.");

      await ref.update({ status, moderatedAt: FieldValue.serverTimestamp() });
      await recomputeDoctorRating((snap.data() as RatingDoc).doctorId);

      res.json({ id: req.params.id, status });
    })
  );

  return r;
}
