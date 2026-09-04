import { Router } from "express";

import { C, db, type DoctorDoc } from "../db";
import { handler, Problem } from "../errors";

export function doctorJson(id: string, d: DoctorDoc) {
  return {
    id,
    name: d.name,
    specialties: d.specialties,
    qualification: d.qualification,
    registrationNumber: d.registrationNumber,
    yearsExperience: d.yearsExperience,
    consultationFeeInr: d.consultationFeeInr,
    videoFeeInr: d.videoFeeInr,
    rating: d.rating,
    ratingCount: d.ratingCount,
    hospital: d.hospital,
    languages: d.languages,
    modes: d.modes,
    photoUrl: d.photoUrl ?? null,
    bio: d.bio ?? null,
  };
}

export function doctorRoutes(secret: () => string): Router {
  const r = Router();

  /**
   * `GET /v1/doctors` — public approved-provider directory (FR-SRCH-001/002).
   *
   * The client wireframe makes doctor discovery available before sign-in. Only
   * approved, deliberately public provider-profile fields are returned; every
   * booking, record, and account action remains authenticated.
   *
   * Firestore cannot express "name contains X" or combine several range
   * filters, so the query narrows on the dimensions it *can* index
   * (approval status, specialty, city, mode) and the remaining filters —
   * free text, fee ceiling, minimum rating — are applied in memory over that
   * narrowed set. That is correct at closed-beta scale; a directory large
   * enough to outgrow it needs a search index (Algolia/Typesense), not a
   * cleverer Firestore query.
   */
  r.get(
    "/",
    handler(async (req, res) => {
      const { query, specialtyCode, city, maxFeeInr, minRating, mode } = req.query;

      let q = db()
        .collection(C.doctors)
        // An unapproved provider has no search visibility at all.
        .where("providerStatus", "==", "APPROVED") as FirebaseFirestore.Query;

      if (typeof specialtyCode === "string" && specialtyCode) {
        q = q.where("specialtyCodes", "array-contains", specialtyCode);
      }
      if (typeof city === "string" && city) {
        q = q.where("city", "==", city);
      }

      const snap = await q.limit(200).get();

      const text = typeof query === "string" ? query.trim().toLowerCase() : "";
      const feeCeiling = maxFeeInr ? Number(maxFeeInr) : undefined;
      const ratingFloor = minRating ? Number(minRating) : undefined;
      const wantedMode = typeof mode === "string" ? mode : undefined;

      const results = snap.docs
        .map((doc) => ({ id: doc.id, d: doc.data() as DoctorDoc }))
        .filter(({ d }) => {
          if (text) {
            const haystack = [
              d.name,
              d.qualification,
              d.hospital.name,
              d.city,
              ...d.specialties.map((s) => s.name),
            ]
              .join(" ")
              .toLowerCase();
            if (!haystack.includes(text)) return false;
          }
          if (wantedMode && !d.modes.includes(wantedMode as DoctorDoc["modes"][number])) return false;
          if (feeCeiling !== undefined && Math.min(d.consultationFeeInr, d.videoFeeInr) > feeCeiling) {
            return false;
          }
          if (ratingFloor !== undefined && d.rating < ratingFloor) return false;
          return true;
        })
        .map(({ id, d }) => doctorJson(id, d));

      res.json({ items: results });
    })
  );

  r.get(
    "/specialties",
    handler(async (_req, res) => {
      const snap = await db().collection(C.specialties).orderBy("name").get();
      res.json({
        items: snap.docs.map((d) => ({ code: d.id, name: (d.data() as { name: string }).name })),
      });
    })
  );

  /** Distinct cities that have at least one approved doctor. */
  r.get(
    "/cities",
    handler(async (_req, res) => {
      const snap = await db()
        .collection(C.doctors)
        .where("providerStatus", "==", "APPROVED")
        .select("city")
        .get();
      const cities = [...new Set(snap.docs.map((d) => (d.data() as { city: string }).city))].sort();
      res.json({ items: cities });
    })
  );

  r.get(
    "/:id",
    handler(async (req, res) => {
      const snap = await db().collection(C.doctors).doc(req.params.id).get();
      if (!snap.exists) throw Problem.notFound("DOCTOR_NOT_FOUND", "Doctor not found.");

      const d = snap.data() as DoctorDoc;
      if (d.providerStatus !== "APPROVED") {
        // 404 rather than 403: whether an unapproved doctor exists is itself
        // information a patient has no business learning.
        throw Problem.notFound("DOCTOR_NOT_FOUND", "Doctor not found.");
      }

      res.json(doctorJson(snap.id, d));
    })
  );

  return r;
}
