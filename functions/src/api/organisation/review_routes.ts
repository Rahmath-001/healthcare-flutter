import { Timestamp } from "firebase-admin/firestore";
import { Router } from "express";

import { requireAuth, requireScope } from "../auth/middleware";
import { C, db, type HospitalDoc, type OrganisationRegistrationDoc } from "../db";
import { handler, Problem } from "../errors";

/** Operator-only hospital application queue and decision path. */
export function organisationReviewRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret), requireScope("provider:approve"));

  r.get(
    "/organisations",
    handler(async (_req, res) => {
      const snap = await db()
        .collection(C.organisationRegistrations)
        .where("type", "==", "HOSPITAL")
        .where("status", "==", "SUBMITTED")
        .limit(100)
        .get();
      const items = snap.docs
        .map((doc) => ({ id: doc.id, ...(doc.data() as OrganisationRegistrationDoc) }))
        .sort((a, b) => a.submittedAt.toMillis() - b.submittedAt.toMillis())
        .map(({ submittedAt, ...application }) => ({ ...application, submittedAt: submittedAt.toDate().toISOString() }));
      res.json({ items });
    })
  );

  r.post(
    "/organisations/:id/approve",
    handler(async (req, res) => {
      const firestore = db();
      const registrationRef = firestore.collection(C.organisationRegistrations).doc(req.params.id);
      await firestore.runTransaction(async (transaction) => {
        const registrationSnap = await transaction.get(registrationRef);
        if (!registrationSnap.exists) throw Problem.notFound("ORGANISATION_NOT_FOUND", "Hospital application not found.");
        const registration = registrationSnap.data() as OrganisationRegistrationDoc;
        if (registration.type !== "HOSPITAL") throw Problem.conflict("NOT_A_HOSPITAL", "Only hospital applications can be approved here.");
        if (registration.status !== "SUBMITTED") throw Problem.conflict("ORGANISATION_ALREADY_DECIDED", "This hospital application has already been decided.");
        const now = Timestamp.now();
        const hospital: HospitalDoc = {
          name: registration.name,
          registrationNumber: registration.registrationNumber,
          address: registration.address,
          city: registration.city,
          postalCode: registration.postalCode,
          state: registration.state,
          country: registration.country,
          registrationId: registrationRef.id,
          approvedAt: now,
        };
        transaction.create(firestore.collection(C.hospitals).doc(registrationRef.id), hospital);
        transaction.update(registrationRef, { status: "APPROVED", reviewedAt: now, reviewedBy: req.auth!.sub });
      });
      res.status(201).json({ id: req.params.id, status: "APPROVED" });
    })
  );

  r.post(
    "/organisations/:id/reject",
    handler(async (req, res) => {
      const reason = typeof req.body?.reason === "string" ? req.body.reason.trim() : "";
      if (reason.length < 10) throw Problem.validation("Give the applicant a clear reason.", { reason: "minimum 10 characters" });
      const ref = db().collection(C.organisationRegistrations).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("ORGANISATION_NOT_FOUND", "Hospital application not found.");
      const registration = snap.data() as OrganisationRegistrationDoc;
      if (registration.type !== "HOSPITAL" || registration.status !== "SUBMITTED") {
        throw Problem.conflict("ORGANISATION_ALREADY_DECIDED", "This hospital application cannot be rejected.");
      }
      await ref.update({ status: "REJECTED", reviewedAt: Timestamp.now(), reviewedBy: req.auth!.sub, rejectionReason: reason });
      res.json({ id: req.params.id, status: "REJECTED" });
    })
  );

  return r;
}
