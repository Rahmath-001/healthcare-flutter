import { Router, type Request } from "express";

import { requireAuth, requireScope } from "../auth/middleware";
import { Timestamp } from "firebase-admin/firestore";

import {
  C,
  db,
  type DoctorDoc,
  type HospitalAffiliationRequestDoc,
  type HospitalChangeRequestDoc,
  type HospitalDoc,
} from "../db";
import { handler, Problem } from "../errors";
import { doctorJson } from "../doctors/routes";

function hospitalJson(id: string, hospital: HospitalDoc) {
  return {
    id,
    name: hospital.name,
    address: hospital.address,
    city: hospital.city,
    state: hospital.state,
    postalCode: hospital.postalCode,
    country: hospital.country,
  };
}

function requiredText(value: unknown, field: string, maxLength: number): string {
  if (typeof value !== "string" || !value.trim()) {
    throw Problem.validation("Complete all required organisation details.", { [field]: "required" });
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLength) {
    throw Problem.validation("One or more fields are too long.", { [field]: "too long" });
  }
  return trimmed;
}

async function assignedHospital(req: Request) {
  const hospitalId = req.user!.hospitalId;
  if (!hospitalId) {
    throw Problem.forbidden("HOSPITAL_NOT_ASSIGNED", "No hospital is assigned to this account.");
  }
  const snap = await db().collection(C.hospitals).doc(hospitalId).get();
  if (!snap.exists) throw Problem.notFound("HOSPITAL_NOT_FOUND", "Your hospital is no longer available.");
  return snap;
}

function requestJson(id: string, request: HospitalChangeRequestDoc | HospitalAffiliationRequestDoc) {
  return {
    id,
    status: request.status,
    kind: "patch" in request ? "PROFILE_CHANGE" : "PROVIDER_AFFILIATION",
    requestedAt: request.requestedAt.toDate().toISOString(),
    rejectionReason: request.rejectionReason ?? null,
    ...( "patch" in request ? { patch: request.patch } : { doctorId: request.doctorId }),
  };
}

/** Public, operator-verified hospital directory. No submitted application is visible here. */
export function hospitalRoutes(secret: () => string): Router {
  const r = Router();

  // Keep this before `/:id`: otherwise the word "mine" is treated as a
  // public hospital id and a signed-in hospital cannot reach its own profile.
  r.get(
    "/mine",
    requireAuth(secret),
    requireScope("hospital:read_own"),
    handler(async (req, res) => {
      const snap = await assignedHospital(req);
      res.json(hospitalJson(snap.id, snap.data() as HospitalDoc));
    })
  );

  /** Pending profile proposals and affiliation requests for the signed-in hospital. */
  r.get(
    "/mine/requests",
    requireAuth(secret),
    requireScope("hospital:read_own"),
    handler(async (req, res) => {
      const hospital = await assignedHospital(req);
      const firestore = db();
      // Filter status in memory to keep this endpoint deployable without a
      // new composite Firestore index. Each hospital's request history is
      // intentionally small and bounded here.
      const [changes, affiliations] = await Promise.all([
        firestore.collection(C.hospitalChangeRequests).where("hospitalId", "==", hospital.id).limit(100).get(),
        firestore.collection(C.hospitalAffiliationRequests).where("hospitalId", "==", hospital.id).limit(100).get(),
      ]);
      const affiliationItems = await Promise.all(
        affiliations.docs.map(async (doc) => {
          const request = doc.data() as HospitalAffiliationRequestDoc;
          const doctor = await firestore.collection(C.doctors).doc(request.doctorId).get();
          return {
            ...requestJson(doc.id, request),
            providerName: doctor.exists ? (doctor.data() as DoctorDoc).name : "Provider no longer available",
          };
        })
      );
      const items = [
        ...changes.docs.map((doc) => requestJson(doc.id, doc.data() as HospitalChangeRequestDoc)),
        ...affiliationItems,
      ].sort((a, b) => b.requestedAt.localeCompare(a.requestedAt));
      res.json({ items });
    })
  );

  /** Proposes an amendment; it does not mutate the published hospital record. */
  r.post(
    "/mine/change-requests",
    requireAuth(secret),
    requireScope("hospital:request_change"),
    handler(async (req, res) => {
      const hospital = await assignedHospital(req);
      const body = req.body ?? {};
      const patch: HospitalChangeRequestDoc["patch"] = {
        name: requiredText(body.name, "name", 160),
        address: requiredText(body.address, "address", 500),
        city: requiredText(body.city, "city", 120),
        postalCode: requiredText(body.postalCode, "postalCode", 20),
        state: requiredText(body.state, "state", 120),
      };
      const previous = hospital.data() as HospitalDoc;
      if (Object.entries(patch).every(([key, value]) => previous[key as keyof typeof patch] === value)) {
        throw Problem.validation("Change at least one organisation detail before submitting.", {
          profile: "unchanged",
        });
      }
      const existing = await db()
        .collection(C.hospitalChangeRequests)
        .where("hospitalId", "==", hospital.id)
        .limit(100)
        .get();
      if (existing.docs.some((doc) => (doc.data() as HospitalChangeRequestDoc).status === "PENDING")) {
        throw Problem.conflict("PROFILE_CHANGE_PENDING", "An organisation update is already awaiting review.");
      }
      const request: HospitalChangeRequestDoc = {
        hospitalId: hospital.id,
        requestedBy: req.auth!.sub,
        status: "PENDING",
        patch,
        requestedAt: Timestamp.now(),
      };
      const ref = await db().collection(C.hospitalChangeRequests).add(request);
      res.status(201).json(requestJson(ref.id, request));
    })
  );

  /** Requests operations verification of an existing MiDoctor provider affiliation. */
  r.post(
    "/mine/affiliation-requests",
    requireAuth(secret),
    requireScope("hospital:request_affiliation"),
    handler(async (req, res) => {
      const hospital = await assignedHospital(req);
      const doctorId = typeof req.body?.doctorId === "string" ? req.body.doctorId.trim() : "";
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(doctorId)) {
        throw Problem.validation("Enter a valid MiDoctor provider ID.", { doctorId: "invalid" });
      }
      const firestore = db();
      const doctor = await firestore.collection(C.doctors).doc(doctorId).get();
      if (!doctor.exists || (doctor.data() as DoctorDoc).providerStatus !== "APPROVED") {
        throw Problem.validation("That provider is not available for affiliation.", { doctorId: "not approved" });
      }
      const existing = await firestore
        .collection(C.hospitalAffiliationRequests)
        .where("hospitalId", "==", hospital.id)
        .limit(100)
        .get();
      if (existing.docs.some((doc) => {
        const request = doc.data() as HospitalAffiliationRequestDoc;
        return request.doctorId === doctorId && request.status === "PENDING";
      })) {
        throw Problem.conflict("AFFILIATION_PENDING", "This provider affiliation is already awaiting review.");
      }
      const request: HospitalAffiliationRequestDoc = {
        hospitalId: hospital.id,
        doctorId,
        requestedBy: req.auth!.sub,
        status: "PENDING",
        requestedAt: Timestamp.now(),
      };
      const ref = await firestore.collection(C.hospitalAffiliationRequests).add(request);
      res.status(201).json({ ...requestJson(ref.id, request), providerName: (doctor.data() as DoctorDoc).name });
    })
  );

  r.get(
    "/",
    handler(async (req, res) => {
      const query = typeof req.query.query === "string" ? req.query.query.trim().toLowerCase() : "";
      const city = typeof req.query.city === "string" ? req.query.city.trim().toLowerCase() : "";
      const snap = await db().collection(C.hospitals).limit(200).get();
      const items = snap.docs
        .map((doc) => ({ id: doc.id, hospital: doc.data() as HospitalDoc }))
        .filter(({ hospital }) => {
          if (city && hospital.city.toLowerCase() !== city) return false;
          if (!query) return true;
          return [hospital.name, hospital.city, hospital.state].join(" ").toLowerCase().includes(query);
        })
        .sort((a, b) => a.hospital.name.localeCompare(b.hospital.name))
        .map(({ id, hospital }) => hospitalJson(id, hospital));
      res.json({ items });
    })
  );

  r.get(
    "/:id",
    handler(async (req, res) => {
      const snap = await db().collection(C.hospitals).doc(req.params.id).get();
      if (!snap.exists) throw Problem.notFound("HOSPITAL_NOT_FOUND", "Hospital not found.");
      res.json(hospitalJson(snap.id, snap.data() as HospitalDoc));
    })
  );

  r.get(
    "/:id/doctors",
    handler(async (req, res) => {
      const hospital = await db().collection(C.hospitals).doc(req.params.id).get();
      if (!hospital.exists) throw Problem.notFound("HOSPITAL_NOT_FOUND", "Hospital not found.");
      const doctors = await db().collection(C.doctors).where("providerStatus", "==", "APPROVED").limit(200).get();
      const items = doctors.docs
        .map((doc) => ({ id: doc.id, doctor: doc.data() as DoctorDoc }))
        .filter(({ doctor }) => doctor.hospital.id === req.params.id)
        .map(({ id, doctor }) => doctorJson(id, doctor));
      res.json({ items });
    })
  );

  return r;
}
