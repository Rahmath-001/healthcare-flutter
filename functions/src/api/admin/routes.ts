import { Router } from "express";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import { requireAuth, requireScope } from "../auth/middleware";
import { C, db, type AccountStatus, type Role, type UserDoc } from "../db";
import { handler, Problem } from "../errors";

/**
 * Account administration.
 *
 * Two capabilities live here that the product could not operate without, and
 * that deliberately have no client-side equivalent:
 *
 *  - **Suspension.** `AccountStatus` has supported SUSPENDED and DEACTIVATED
 *    from the start and `requireAuth` has always enforced them, but nothing
 *    could ever set them — the enforcement was unreachable code and there was
 *    no way to eject a bad actor short of editing the database by hand.
 *  - **Role assignment.** `resolveRequestedRole` correctly refuses to let a
 *    client request anything but PATIENT or PROVIDER, which also meant no
 *    SUPERVISOR could ever come into existence, which in turn meant the
 *    provider-approval endpoints could never be called by anybody. The first
 *    admin is created out-of-band by `scripts/grant-role.ts`; every subsequent
 *    one is created here.
 *
 * Every mutation bumps `permissionVersion`, so the decision reaches the target's
 * device on their next request rather than up to fifteen minutes later.
 */

const ASSIGNABLE_ROLES: Role[] = [
  "PATIENT",
  "PROVIDER",
  "SUPERVISOR",
  "SUPPORT_L1",
  "SUPPORT_L2",
  "ADMIN",
  "UNASSIGNED",
];

const SUSPENDABLE: AccountStatus[] = ["SUSPENDED", "DEACTIVATED"];

export function adminRoutes(secret: () => string) {
  const r = Router();
  r.use(requireAuth(secret));

  /** Look up one account, so an operator can confirm who they are about to act on. */
  r.get(
    "/users/:userId",
    requireScope("user:suspend"),
    handler(async (req, res) => {
      const snap = await db().collection(C.users).doc(req.params.userId).get();
      if (!snap.exists) throw Problem.notFound("USER_NOT_FOUND", "No such account.");
      const user = snap.data() as UserDoc;
      res.json({
        userId: req.params.userId,
        role: user.role,
        status: user.status,
        providerStatus: user.providerStatus,
        displayName: user.displayName ?? null,
        email: user.email ?? null,
        phone: user.phone ?? null,
      });
    })
  );

  /**
   * Suspends or deactivates an account.
   *
   * Suspension is reversible and is the lever for "something is wrong, stop
   * this now". Deactivation is the terminal state. Neither deletes anything:
   * clinical records carry a statutory retention period that outlives the
   * account, and the app shows a suspended user an explanation rather than
   * signing them out silently.
   */
  r.post(
    "/users/:userId/suspend",
    requireScope("user:suspend"),
    handler(async (req, res) => {
      const { status, reason } = req.body ?? {};
      if (!SUSPENDABLE.includes(status)) {
        throw Problem.validation("Status must be SUSPENDED or DEACTIVATED.", {
          status: "invalid",
        });
      }
      if (typeof reason !== "string" || reason.trim().length < 4) {
        throw Problem.validation("A reason is required.", { reason: "required" });
      }
      if (req.params.userId === req.auth!.sub) {
        throw Problem.validation("You cannot suspend your own account.", {
          userId: "self",
        });
      }

      const ref = db().collection(C.users).doc(req.params.userId);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("USER_NOT_FOUND", "No such account.");

      await ref.update({
        status,
        suspensionReason: reason.trim(),
        permissionVersion: FieldValue.increment(1),
        updatedAt: Timestamp.now(),
      });

      // A suspended provider must also leave the searchable directory, or
      // patients keep booking someone who can no longer be reached.
      const doctorId = (snap.data() as UserDoc).doctorId;
      if (doctorId) {
        await db()
          .collection(C.doctors)
          .doc(doctorId)
          .update({ providerStatus: "SUSPENDED" });
      }

      logger.warn("Account status changed", {
        target: req.params.userId,
        actor: req.auth!.sub,
        status,
      });

      res.json({ userId: req.params.userId, status });
    })
  );

  /** Returns a suspended account to ACTIVE. */
  r.post(
    "/users/:userId/reactivate",
    requireScope("user:suspend"),
    handler(async (req, res) => {
      const ref = db().collection(C.users).doc(req.params.userId);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("USER_NOT_FOUND", "No such account.");

      await ref.update({
        status: "ACTIVE",
        suspensionReason: FieldValue.delete(),
        permissionVersion: FieldValue.increment(1),
        updatedAt: Timestamp.now(),
      });

      logger.info("Account reactivated", {
        target: req.params.userId,
        actor: req.auth!.sub,
      });

      // Deliberately does *not* restore a provider to APPROVED. Re-entering the
      // directory is a separate decision that goes back through review.
      res.json({ userId: req.params.userId, status: "ACTIVE" });
    })
  );

  /**
   * Assigns a role.
   *
   * Admin-only, and it is the single most dangerous call in the API — granting
   * SUPERVISOR hands someone the power to approve doctors. It refuses to act on
   * the caller's own account so an admin cannot quietly demote themselves out
   * of an audit trail, or be tricked into doing so.
   */
  r.post(
    "/users/:userId/role",
    requireScope("user:set_role"),
    handler(async (req, res) => {
      const { role } = req.body ?? {};
      if (!ASSIGNABLE_ROLES.includes(role)) {
        throw Problem.validation("Unknown role.", { role: "invalid" });
      }
      if (req.params.userId === req.auth!.sub) {
        throw Problem.validation("You cannot change your own role.", { userId: "self" });
      }

      const ref = db().collection(C.users).doc(req.params.userId);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("USER_NOT_FOUND", "No such account.");

      await ref.update({
        role,
        // A non-provider has no provider status to speak of. Leaving a stale
        // APPROVED behind would survive a later switch back to PROVIDER and
        // skip review entirely.
        ...(role === "PROVIDER" ? {} : { providerStatus: "NOT_APPLICABLE" }),
        permissionVersion: FieldValue.increment(1),
        updatedAt: Timestamp.now(),
      });

      logger.warn("Role changed", {
        target: req.params.userId,
        actor: req.auth!.sub,
        role,
      });

      res.json({ userId: req.params.userId, role });
    })
  );

  return r;
}
