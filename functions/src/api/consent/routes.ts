import { randomUUID } from "crypto";
import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { requireAuth, requireScope } from "../auth/middleware";
import {
  C,
  db,
  type AccessEventDoc,
  type ConsentGrantDoc,
  type ConsentPurpose,
  type ConsentRequestDoc,
  type ConsentScopeKind,
  type DoctorDoc,
} from "../db";
import { handler, Problem } from "../errors";

/**
 * Hard ceiling on how long any grant may last.
 *
 * Enforced here rather than only in the UI: the client offers at most 90 days,
 * but a client is a suggestion. Perpetual access to a medical record is not a
 * thing this system can express — a grant with no end is indistinguishable from
 * a copy.
 */
const MAX_GRANT_DAYS = 180;

/** A request the patient never answers lapses rather than lingering. */
const REQUEST_TTL_HOURS = 72;

const PURPOSES: ConsentPurpose[] = [
  "CONSULTATION",
  "SECOND_OPINION",
  "CONTINUITY_OF_CARE",
  "EMERGENCY",
];
const SCOPE_KINDS: ConsentScopeKind[] = ["SPECIFIC_RECORDS", "RECORD_TYPES", "ALL_RECORDS"];

function grantJson(id: string, g: ConsentGrantDoc) {
  return {
    id,
    providerId: g.providerId,
    providerName: g.providerName,
    providerSpecialty: g.providerSpecialty,
    scopeKind: g.scopeKind,
    purpose: g.purpose,
    grantedAt: g.grantedAt.toDate().toISOString(),
    expiresAt: g.expiresAt.toDate().toISOString(),
    recordIds: g.recordIds,
    recordTypeLabels: g.recordTypeLabels,
    revokedAt: g.revokedAt ? g.revokedAt.toDate().toISOString() : null,
    usesCount: g.usesCount,
    appointmentReference: g.appointmentReference ?? null,
  };
}

function requestJson(id: string, q: ConsentRequestDoc) {
  return {
    id,
    providerId: q.providerId,
    providerName: q.providerName,
    providerSpecialty: q.providerSpecialty,
    purpose: q.purpose,
    requestedAt: q.requestedAt.toDate().toISOString(),
    expiresAt: q.expiresAt.toDate().toISOString(),
    status: q.status,
    message: q.message ?? null,
    appointmentReference: q.appointmentReference ?? null,
  };
}

function eventJson(id: string, e: AccessEventDoc) {
  return {
    id,
    actorName: e.actorName,
    recordTitle: e.recordTitle,
    action: e.action,
    at: e.at.toDate().toISOString(),
    purpose: e.purpose ?? null,
  };
}

/** Appends to the access log. Never updates, never deletes. */
async function logAccess(event: AccessEventDoc): Promise<void> {
  await db().collection(C.accessLog).doc(randomUUID()).set(event);
}

export function consentRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  r.get(
    "/grants",
    requireScope("consent:grant"),
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.consentGrants)
        .where("patientId", "==", req.auth!.sub)
        .orderBy("grantedAt", "desc")
        .limit(200)
        .get();
      res.json({ items: snap.docs.map((d) => grantJson(d.id, d.data() as ConsentGrantDoc)) });
    })
  );

  r.get(
    "/requests",
    requireScope("consent:grant"),
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.consentRequests)
        .where("patientId", "==", req.auth!.sub)
        .where("status", "==", "PENDING")
        .orderBy("requestedAt", "desc")
        .limit(100)
        .get();

      // A lapsed request is reported as expired rather than pending, so the
      // patient is never shown a decision they can no longer make.
      const nowMs = Date.now();
      res.json({
        items: snap.docs
          .map((d) => ({ id: d.id, q: d.data() as ConsentRequestDoc }))
          .filter(({ q }) => q.expiresAt.toMillis() > nowMs)
          .map(({ id, q }) => requestJson(id, q)),
      });
    })
  );

  r.get(
    "/access-log",
    requireScope("consent:view_log"),
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.accessLog)
        .where("patientId", "==", req.auth!.sub)
        .orderBy("at", "desc")
        .limit(200)
        .get();
      res.json({ items: snap.docs.map((d) => eventJson(d.id, d.data() as AccessEventDoc)) });
    })
  );

  /** Patient-initiated grant. */
  r.post(
    "/grants",
    requireScope("consent:grant"),
    handler(async (req, res) => {
      const {
        providerId,
        scopeKind,
        purpose,
        durationDays,
        recordIds,
        recordTypeLabels,
        appointmentReference,
      } = req.body ?? {};

      if (typeof providerId !== "string" || !providerId) {
        throw Problem.validation("A provider is required.", { providerId: "required" });
      }
      if (!SCOPE_KINDS.includes(scopeKind)) {
        throw Problem.validation("Unknown scope.", { scopeKind: "invalid" });
      }
      if (!PURPOSES.includes(purpose)) {
        throw Problem.validation("Unknown purpose.", { purpose: "invalid" });
      }

      const days = Number(durationDays);
      if (!Number.isFinite(days) || days <= 0) {
        throw Problem.validation("A grant must have an expiry.", { durationDays: "required" });
      }
      if (days > MAX_GRANT_DAYS) {
        throw Problem.validation(`Access cannot last longer than ${MAX_GRANT_DAYS} days.`, {
          durationDays: "too long",
        });
      }

      // The provider's identity is resolved here rather than taken from the
      // body. A grant is the one object in this system that hands a third party
      // access to someone's medical records, so the name shown on it has to be
      // the name in the directory — otherwise a patient can be walked through a
      // consent screen that reads "Dr Anjali Rao" while the id underneath
      // belongs to somebody else entirely. It also refuses ids that are not an
      // approved provider at all.
      const doctorSnap = await db().collection(C.doctors).doc(providerId).get();
      const doctor = doctorSnap.data() as DoctorDoc | undefined;
      if (!doctorSnap.exists || !doctor || doctor.providerStatus !== "APPROVED") {
        throw Problem.validation("That doctor is not available.", { providerId: "unknown" });
      }

      const id = randomUUID();
      const grantedAt = Timestamp.now();
      const grant: ConsentGrantDoc = {
        patientId: req.auth!.sub,
        providerId,
        providerName: doctor.name,
        providerSpecialty: doctor.specialties[0]?.name ?? "",
        scopeKind,
        purpose,
        recordIds: Array.isArray(recordIds) ? recordIds.map(String) : [],
        recordTypeLabels: Array.isArray(recordTypeLabels) ? recordTypeLabels.map(String) : [],
        appointmentReference: typeof appointmentReference === "string" ? appointmentReference : null,
        grantedAt,
        expiresAt: Timestamp.fromMillis(grantedAt.toMillis() + days * 24 * 60 * 60 * 1000),
        revokedAt: null,
        usesCount: 0,
      };

      await db().collection(C.consentGrants).doc(id).set(grant);
      await logAccess({
        patientId: grant.patientId,
        actorId: req.auth!.sub,
        actorName: req.user!.displayName ?? "You",
        recordTitle: `Access granted to ${grant.providerName}`,
        action: "VIEW_METADATA",
        purpose: grant.purpose,
        at: grantedAt,
      });

      res.status(201).json(grantJson(id, grant));
    })
  );

  /**
   * Revokes a grant.
   *
   * Server-side and immediate, which is the entire reason consent cannot live
   * on the client: if the provider's app decided whether it may still read a
   * record, revocation would be theatre — a patched build simply stops asking.
   */
  r.post(
    "/grants/:id/revoke",
    requireScope("consent:revoke"),
    handler(async (req, res) => {
      const ref = db().collection(C.consentGrants).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("GRANT_NOT_FOUND", "That permission no longer exists.");

      const grant = snap.data() as ConsentGrantDoc;
      if (grant.patientId !== req.auth!.sub) {
        throw Problem.notFound("GRANT_NOT_FOUND", "That permission no longer exists.");
      }

      const revokedAt = Timestamp.now();
      if (!grant.revokedAt) {
        await ref.update({ revokedAt });
        await logAccess({
          patientId: grant.patientId,
          actorId: req.auth!.sub,
          actorName: req.user!.displayName ?? "You",
          recordTitle: `Access revoked for ${grant.providerName}`,
          action: "VIEW_METADATA",
          purpose: grant.purpose,
          at: revokedAt,
        });
      }

      res.json(grantJson(req.params.id, { ...grant, revokedAt: grant.revokedAt ?? revokedAt }));
    })
  );

  /** Approving a request creates a grant, so approval and grant share one path. */
  r.post(
    "/requests/:id/approve",
    requireScope("consent:grant"),
    handler(async (req, res) => {
      const { durationDays, scopeKind, recordIds } = req.body ?? {};

      const reqRef = db().collection(C.consentRequests).doc(req.params.id);
      const snap = await reqRef.get();
      if (!snap.exists) throw Problem.notFound("REQUEST_NOT_FOUND", "That request no longer exists.");

      const request = snap.data() as ConsentRequestDoc;
      if (request.patientId !== req.auth!.sub) {
        throw Problem.notFound("REQUEST_NOT_FOUND", "That request no longer exists.");
      }
      if (request.status !== "PENDING") {
        throw Problem.conflict("REQUEST_RESOLVED", "That request has already been answered.");
      }
      if (request.expiresAt.toMillis() < Date.now()) {
        throw Problem.conflict("REQUEST_EXPIRED", "That request has expired.");
      }

      const days = Number(durationDays);
      if (!Number.isFinite(days) || days <= 0 || days > MAX_GRANT_DAYS) {
        throw Problem.validation(`Choose an expiry of up to ${MAX_GRANT_DAYS} days.`, {
          durationDays: "invalid",
        });
      }

      const id = randomUUID();
      const grantedAt = Timestamp.now();
      const grant: ConsentGrantDoc = {
        patientId: request.patientId,
        providerId: request.providerId,
        providerName: request.providerName,
        providerSpecialty: request.providerSpecialty,
        scopeKind: SCOPE_KINDS.includes(scopeKind) ? scopeKind : "ALL_RECORDS",
        purpose: request.purpose,
        recordIds: Array.isArray(recordIds) ? recordIds.map(String) : [],
        recordTypeLabels: [],
        appointmentReference: request.appointmentReference ?? null,
        grantedAt,
        expiresAt: Timestamp.fromMillis(grantedAt.toMillis() + days * 24 * 60 * 60 * 1000),
        revokedAt: null,
        usesCount: 0,
      };

      const batch = db().batch();
      batch.set(db().collection(C.consentGrants).doc(id), grant);
      batch.update(reqRef, { status: "APPROVED", resolvedAt: grantedAt });
      await batch.commit();

      res.status(201).json(grantJson(id, grant));
    })
  );

  r.post(
    "/requests/:id/deny",
    requireScope("consent:grant"),
    handler(async (req, res) => {
      const reqRef = db().collection(C.consentRequests).doc(req.params.id);
      const snap = await reqRef.get();
      if (!snap.exists) throw Problem.notFound("REQUEST_NOT_FOUND", "That request no longer exists.");

      const request = snap.data() as ConsentRequestDoc;
      if (request.patientId !== req.auth!.sub) {
        throw Problem.notFound("REQUEST_NOT_FOUND", "That request no longer exists.");
      }

      const at = Timestamp.now();
      await reqRef.update({ status: "DENIED", resolvedAt: at });

      // A denial is logged as deliberately as a read: a burst of refused
      // attempts is the clearest fraud signal the system produces.
      await logAccess({
        patientId: request.patientId,
        actorId: request.providerId,
        actorName: request.providerName,
        recordTitle: "Access request",
        action: "DENIED",
        purpose: request.purpose,
        at,
      });

      res.json({ ok: true });
    })
  );

  /**
   * Provider asking a patient for access.
   *
   * Gated on an existing appointment relationship — without that check the
   * request channel becomes a way to fish for records from strangers.
   */
  r.post(
    "/requests",
    requireScope("records:request_access"),
    handler(async (req, res) => {
      const { patientId, purpose, message, appointmentReference } = req.body ?? {};
      if (typeof patientId !== "string" || !patientId) {
        throw Problem.validation("A patient is required.", { patientId: "required" });
      }
      if (!PURPOSES.includes(purpose)) {
        throw Problem.validation("Unknown purpose.", { purpose: "invalid" });
      }

      const relationship = await db()
        .collection(C.appointments)
        .where("doctorId", "==", req.user!.doctorId ?? "__none__")
        .where("patientId", "==", patientId)
        .limit(1)
        .get();
      if (relationship.empty) {
        throw Problem.forbidden("NO_RELATIONSHIP", "You can only ask patients you have seen.");
      }

      const doctorSnap = await db().collection(C.doctors).doc(req.user!.doctorId!).get();
      const doctor = doctorSnap.data() as { name: string; specialties: { name: string }[] };

      const id = randomUUID();
      const requestedAt = Timestamp.now();
      const request: ConsentRequestDoc = {
        patientId,
        providerId: req.user!.doctorId!,
        providerName: doctor.name,
        providerSpecialty: doctor.specialties.map((s) => s.name).join(", "),
        purpose,
        message: typeof message === "string" ? message : null,
        appointmentReference: typeof appointmentReference === "string" ? appointmentReference : null,
        requestedAt,
        expiresAt: Timestamp.fromMillis(requestedAt.toMillis() + REQUEST_TTL_HOURS * 60 * 60 * 1000),
        status: "PENDING",
        resolvedAt: null,
      };

      await db().collection(C.consentRequests).doc(id).set(request);
      res.status(201).json(requestJson(id, request));
    })
  );

  return r;
}
