import { Router } from "express";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { requireAuth, requireScope } from "../auth/middleware";
import { C, db, type DoctorDoc, type ProviderStatus, type UserDoc } from "../db";
import { handler, Problem } from "../errors";

/**
 * Provider verification and approval.
 *
 * Approval is the one thing in this system that absolutely cannot be a client
 * decision: if the app decided, a doctor would approve themselves. It lives
 * behind `provider:approve`, which only SUPERVISOR and ADMIN hold.
 *
 * Approval is also not merely a flag. It expands the provider's scope set from
 * two entries to ten, so the change must invalidate every access token already
 * issued to that account — hence the `permissionVersion` bump, which turns the
 * provider's next request into a `TOKEN_STALE` and forces a refresh.
 */
export function providerRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  /** The signed-in provider's own verification state. */
  r.get(
    "/verification",
    handler(async (req, res) => {
      if (req.auth!.role !== "PROVIDER") {
        throw Problem.forbidden("NOT_A_PROVIDER", "You do not have access to this.");
      }
      res.json({
        providerStatus: req.user!.providerStatus,
        doctorId: req.user!.doctorId ?? null,
      });
    })
  );

  /** Moves DRAFT/REJECTED/RESUBMIT_REQUESTED to SUBMITTED. */
  r.post(
    "/verification/submit",
    requireScope("credentials:submit"),
    handler(async (req, res) => {
      const current = req.user!.providerStatus;
      if (!["DRAFT", "REJECTED", "RESUBMIT_REQUESTED"].includes(current)) {
        throw Problem.conflict("NOT_SUBMITTABLE", "Your application is already with our team.");
      }

      await db()
        .collection(C.users)
        .doc(req.auth!.sub)
        .update({ providerStatus: "SUBMITTED", updatedAt: Timestamp.now() });

      res.json({ providerStatus: "SUBMITTED" });
    })
  );

  /** Queue of providers awaiting review. Supervisors and admins only. */
  r.get(
    "/queue",
    requireScope("provider:review"),
    handler(async (_req, res) => {
      const snap = await db()
        .collection(C.users)
        .where("role", "==", "PROVIDER")
        .where("providerStatus", "in", ["SUBMITTED", "UNDER_REVIEW"])
        .limit(100)
        .get();

      res.json({
        items: snap.docs.map((d) => {
          const u = d.data() as UserDoc;
          return {
            userId: d.id,
            displayName: u.displayName ?? null,
            email: u.email ?? null,
            phone: u.phone ?? null,
            providerStatus: u.providerStatus,
            doctorId: u.doctorId ?? null,
          };
        }),
      });
    })
  );

  /**
   * Approves a provider and publishes their directory entry.
   *
   * The `doctors` document is what search reads, and it is written here rather
   * than at sign-up so an unapproved provider is not merely filtered out of
   * results — there is nothing to filter.
   *
   * NMC / State Medical Council verification is a human step that happens
   * before this call. The API records the decision; it cannot make it.
   */
  r.post(
    "/:userId/approve",
    requireScope("provider:approve"),
    handler(async (req, res) => {
      const { profile } = req.body ?? {};
      const firestore = db();
      const userRef = firestore.collection(C.users).doc(req.params.userId);

      const snap = await userRef.get();
      if (!snap.exists) throw Problem.notFound("USER_NOT_FOUND", "That account does not exist.");
      const user = snap.data() as UserDoc;
      if (user.role !== "PROVIDER") {
        throw Problem.conflict("NOT_A_PROVIDER", "That account is not a provider.");
      }
      if (!profile || typeof profile !== "object") {
        throw Problem.validation("A directory profile is required to approve.", {
          profile: "required",
        });
      }

      const doctorId = user.doctorId ?? req.params.userId;
      const specialties = Array.isArray(profile.specialties) ? profile.specialties : [];

      const doctor: DoctorDoc = {
        name: String(profile.name ?? user.displayName ?? ""),
        specialties,
        qualification: String(profile.qualification ?? ""),
        registrationNumber: String(profile.registrationNumber ?? ""),
        yearsExperience: Number(profile.yearsExperience ?? 0),
        consultationFeeInr: Number(profile.consultationFeeInr ?? 0),
        videoFeeInr: Number(profile.videoFeeInr ?? profile.consultationFeeInr ?? 0),
        rating: 0,
        ratingCount: 0,
        hospital: profile.hospital ?? { id: doctorId, name: "", city: "" },
        languages: Array.isArray(profile.languages) ? profile.languages.map(String) : [],
        modes: Array.isArray(profile.modes) ? profile.modes : ["VIDEO"],
        photoUrl: user.photoUrl ?? null,
        bio: profile.bio ?? null,
        providerStatus: "APPROVED",
        userId: req.params.userId,
        city: String(profile.hospital?.city ?? ""),
        specialtyCodes: specialties.map((s: { code: string }) => String(s.code)),
      };

      if (!doctor.registrationNumber) {
        throw Problem.validation("A council registration number is required.", {
          registrationNumber: "required",
        });
      }

      const batch = firestore.batch();
      batch.set(firestore.collection(C.doctors).doc(doctorId), doctor);
      batch.update(userRef, {
        providerStatus: "APPROVED",
        doctorId,
        // Invalidates every access token already issued to this provider, so
        // their expanded scopes take effect on the next request rather than up
        // to fifteen minutes later.
        permissionVersion: FieldValue.increment(1),
        updatedAt: Timestamp.now(),
      });
      await batch.commit();

      res.json({ userId: req.params.userId, doctorId, providerStatus: "APPROVED" });
    })
  );

  /**
   * Rejects an application, or asks for a resubmission.
   *
   * Also un-publishes the directory entry: a provider whose approval is
   * withdrawn must stop being bookable immediately, not merely stop appearing.
   */
  r.post(
    "/:userId/reject",
    requireScope("provider:reject"),
    handler(async (req, res) => {
      const { reason, allowResubmit } = req.body ?? {};
      if (typeof reason !== "string" || !reason.trim()) {
        throw Problem.validation("A reason is required.", { reason: "required" });
      }

      const firestore = db();
      const userRef = firestore.collection(C.users).doc(req.params.userId);
      const snap = await userRef.get();
      if (!snap.exists) throw Problem.notFound("USER_NOT_FOUND", "That account does not exist.");
      const user = snap.data() as UserDoc;

      const status: ProviderStatus = allowResubmit === true ? "RESUBMIT_REQUESTED" : "REJECTED";

      const batch = firestore.batch();
      batch.update(userRef, {
        providerStatus: status,
        rejectionReason: reason.trim(),
        permissionVersion: FieldValue.increment(1),
        updatedAt: Timestamp.now(),
      });
      if (user.doctorId) {
        batch.update(firestore.collection(C.doctors).doc(user.doctorId), {
          providerStatus: status,
        });
      }
      await batch.commit();

      res.json({ userId: req.params.userId, providerStatus: status });
    })
  );

  return r;
}
