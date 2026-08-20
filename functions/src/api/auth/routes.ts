import { Router } from "express";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import {
  C,
  db,
  slotLockId,
  type AppointmentDoc,
  type ConsentGrantDoc,
  type ErasureRequestDoc,
  type PatientProfileDoc,
  type UserDoc,
} from "../db";
import { handler, Problem } from "../errors";
import { rateLimit } from "../rate_limit";
import { requireAuth } from "./middleware";
import { resolveRequestedRole, scopesFor } from "./scopes";
import {
  createSession,
  mintAccessToken,
  revokeAllSessionsForUser,
  revokeSession,
  rotateRefreshToken,
} from "./tokens";

/**
 * How long clinical records outlive an erasure request.
 *
 * Three years, matching the retention the app already states on its privacy
 * screen. This is a placeholder for a documented legal position, not a
 * substitute for one.
 */
const CLINICAL_RETENTION_DAYS = 3 * 365;

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

const GENDERS = ["FEMALE", "MALE", "OTHER", "UNDISCLOSED"];

const BLOOD_GROUPS = [
  "A_POSITIVE",
  "A_NEGATIVE",
  "B_POSITIVE",
  "B_NEGATIVE",
  "AB_POSITIVE",
  "AB_NEGATIVE",
  "O_POSITIVE",
  "O_NEGATIVE",
];

/**
 * The JSON body of `POST /v1/auth/session` and `/refresh`.
 *
 * Field names and casing are dictated by `Session.fromJson` on the client —
 * `status` (not accountStatus), UPPER_SNAKE enum values, `expiresIn` in
 * seconds. Changing any of them silently breaks sign-in.
 */
function sessionPayload(
  userId: string,
  sessionId: string,
  user: UserDoc,
  accessToken: string,
  expiresIn: number,
  refreshToken: string
) {
  return {
    userId,
    sessionId,
    accessToken,
    expiresIn,
    refreshToken,
    role: user.role,
    status: user.status,
    providerStatus: user.providerStatus,
    scopes: scopesFor(user.role, user.providerStatus),
    permissionVersion: user.permissionVersion,
    displayName: user.displayName ?? null,
    phone: user.phone ?? null,
    email: user.email ?? null,
    photoUrl: user.photoUrl ?? null,
  };
}

export function authRoutes(secret: () => string): Router {
  const r = Router();

  /**
   * Exchanges a Firebase ID token for a MiDoctor session.
   *
   * Firebase proves *who* the caller is; everything about what they may do is
   * decided here and stored in Postgres-equivalent state (Firestore `users`),
   * never read from the Firebase token. That separation is what stops a
   * compromised identity provider from also granting authority.
   */
  r.post(
    "/session",
    // Unauthenticated, and the most expensive endpoint in the API: a
    // Firebase token verification plus up to three writes. Generous enough
    // that a user fumbling an OTP never notices it.
    rateLimit({ name: "auth_session", max: 20, windowSeconds: 300 }),
    handler(async (req, res) => {
      const { firebaseIdToken, deviceId, platform, appVersion, requestedRole } = req.body ?? {};

      if (typeof firebaseIdToken !== "string" || !firebaseIdToken) {
        throw Problem.validation("Missing sign-in token.", { firebaseIdToken: "required" });
      }
      if (typeof deviceId !== "string" || !deviceId) {
        throw Problem.validation("Missing device id.", { deviceId: "required" });
      }

      let decoded;
      try {
        // checkRevoked: a user signed out everywhere on another device must not
        // be able to mint a fresh session from a cached Firebase token.
        decoded = await getAuth().verifyIdToken(firebaseIdToken, true);
      } catch {
        throw Problem.unauthorized("FIREBASE_TOKEN_INVALID", "Please sign in again.");
      }

      const uid = decoded.uid;
      const userRef = db().collection(C.users).doc(uid);
      const snap = await userRef.get();
      const at = Timestamp.now();

      let user: UserDoc;
      if (snap.exists) {
        user = snap.data() as UserDoc;
        // Identity details can change between sign-ins (Apple only reveals a
        // name once, phone users add one later), so refresh them — but never
        // touch role or status here: those are authorization, not identity.
        const patch = {
          displayName: decoded.name ?? user.displayName ?? null,
          phone: decoded.phone_number ?? user.phone ?? null,
          email: decoded.email ?? user.email ?? null,
          photoUrl: decoded.picture ?? user.photoUrl ?? null,
          updatedAt: at,
        };
        await userRef.update(patch);
        user = { ...user, ...patch };
      } else {
        const role = resolveRequestedRole(requestedRole);
        user = {
          role,
          status: "ACTIVE",
          // A new provider starts at DRAFT, so the client routes them into
          // verification rather than into the provider shell.
          providerStatus: role === "PROVIDER" ? "DRAFT" : "NOT_APPLICABLE",
          permissionVersion: 1,
          displayName: decoded.name ?? null,
          phone: decoded.phone_number ?? null,
          email: decoded.email ?? null,
          photoUrl: decoded.picture ?? null,
          doctorId: null,
          createdAt: at,
          updatedAt: at,
        };
        await userRef.set(user);
      }

      const { sessionId, refreshToken } = await createSession(
        uid,
        deviceId,
        typeof platform === "string" ? platform : "unknown",
        typeof appVersion === "string" ? appVersion : "0.0.0"
      );
      const { token, expiresIn } = mintAccessToken(secret(), uid, sessionId, user);

      res.json(sessionPayload(uid, sessionId, user, token, expiresIn, refreshToken));
    })
  );

  /** Rotates the refresh token and mints a fresh access token. */
  r.post(
    "/refresh",
    // A legitimate client refreshes at most once per access-token lifetime
    // per device, and `RefreshCoordinator` makes concurrent refreshes
    // single-flight, so this ceiling is far above honest traffic.
    rateLimit({ name: "auth_refresh", max: 60, windowSeconds: 300 }),
    handler(async (req, res) => {
      const { refreshToken } = req.body ?? {};
      if (typeof refreshToken !== "string" || !refreshToken) {
        throw Problem.validation("Missing refresh token.", { refreshToken: "required" });
      }

      const rotated = await rotateRefreshToken(refreshToken);

      const snap = await db().collection(C.users).doc(rotated.userId).get();
      if (!snap.exists) throw Problem.unauthorized("USER_NOT_FOUND", "Please sign in again.");
      const user = snap.data() as UserDoc;

      if (user.status !== "ACTIVE") {
        throw Problem.forbidden("ACCOUNT_NOT_ACTIVE", "This account is not active.");
      }

      const { token, expiresIn } = mintAccessToken(secret(), rotated.userId, rotated.sessionId, user);

      res.json(
        sessionPayload(rotated.userId, rotated.sessionId, user, token, expiresIn, rotated.newToken)
      );
    })
  );

  /** Revokes this session server-side. The client clears local state regardless. */
  r.post(
    "/logout",
    requireAuth(secret),
    handler(async (req, res) => {
      await revokeSession(req.auth!.sid);
      res.json({ ok: true });
    })
  );

  return r;
}

/** `GET /v1/me` and `PUT /v1/me`. */
export function meRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  r.get(
    "/",
    handler(async (req, res) => {
      const user = req.user!;
      const profileSnap = await db()
        .collection(C.patientProfiles)
        .doc(req.auth!.sub)
        .get();
      const profile = (profileSnap.data() as PatientProfileDoc | undefined) ?? undefined;

      res.json({
        userId: req.auth!.sub,
        role: user.role,
        status: user.status,
        providerStatus: user.providerStatus,
        permissionVersion: user.permissionVersion,
        displayName: user.displayName ?? null,
        phone: user.phone ?? null,
        email: user.email ?? null,
        photoUrl: user.photoUrl ?? null,
        dateOfBirth: profile?.dateOfBirth ?? null,
        gender: profile?.gender ?? null,
        bloodGroup: profile?.bloodGroup ?? null,
        allergies: profile?.allergies ?? [],
        chronicConditions: profile?.chronicConditions ?? [],
        emergencyContactName: profile?.emergencyContactName ?? null,
        emergencyContactPhone: profile?.emergencyContactPhone ?? null,
      });
    })
  );

  /**
   * Partial update. An absent key means "leave alone"; it never clears a field.
   *
   * The identity half lands in `users`, the clinical half in `patientProfiles`.
   * Enum values are checked against the closed sets the client sends rather
   * than stored as free text, because a doctor reads them.
   */
  r.put(
    "/",
    handler(async (req, res) => {
      const body = req.body ?? {};
      const userPatch: Record<string, unknown> = { updatedAt: Timestamp.now() };
      const profilePatch: Record<string, unknown> = { updatedAt: Timestamp.now() };

      if (body.displayName !== undefined) {
        if (typeof body.displayName !== "string" || body.displayName.trim().length < 2) {
          throw Problem.validation("Enter your name.", { displayName: "too short" });
        }
        userPatch.displayName = body.displayName.trim();
      }

      if (body.dateOfBirth !== undefined) {
        if (typeof body.dateOfBirth !== "string" || !DATE_ONLY.test(body.dateOfBirth)) {
          throw Problem.validation("Enter a valid date of birth.", {
            dateOfBirth: "invalid",
          });
        }
        if (Date.parse(`${body.dateOfBirth}T00:00:00Z`) > Date.now()) {
          throw Problem.validation("A date of birth cannot be in the future.", {
            dateOfBirth: "future",
          });
        }
        profilePatch.dateOfBirth = body.dateOfBirth;
      }

      if (body.gender !== undefined) {
        if (!GENDERS.includes(body.gender)) {
          throw Problem.validation("Unknown value.", { gender: "invalid" });
        }
        profilePatch.gender = body.gender;
      }

      if (body.bloodGroup !== undefined) {
        if (!BLOOD_GROUPS.includes(body.bloodGroup)) {
          throw Problem.validation("Unknown value.", { bloodGroup: "invalid" });
        }
        profilePatch.bloodGroup = body.bloodGroup;
      }

      for (const key of ["allergies", "chronicConditions"] as const) {
        if (body[key] === undefined) continue;
        if (!Array.isArray(body[key])) {
          throw Problem.validation("Expected a list.", { [key]: "invalid" });
        }
        profilePatch[key] = (body[key] as unknown[])
          .map((v) => String(v).trim())
          .filter((v) => v.length > 0)
          .slice(0, 50);
      }

      for (const key of ["emergencyContactName", "emergencyContactPhone"] as const) {
        if (body[key] === undefined) continue;
        if (typeof body[key] !== "string") {
          throw Problem.validation("Expected text.", { [key]: "invalid" });
        }
        profilePatch[key] = (body[key] as string).trim().slice(0, 120);
      }

      const writes: Promise<unknown>[] = [
        db().collection(C.users).doc(req.auth!.sub).update(userPatch),
      ];
      // More than the timestamp means there is clinical data to write.
      if (Object.keys(profilePatch).length > 1) {
        writes.push(
          db()
            .collection(C.patientProfiles)
            .doc(req.auth!.sub)
            .set(profilePatch, { merge: true })
        );
      }
      await Promise.all(writes);

      res.json({ ok: true });
    })
  );

  /**
   * DPDP s.11 — the right to access. Returns everything held about the caller.
   *
   * Served synchronously rather than emailed later because the data is small,
   * the caller is already authenticated, and a promise to send something within
   * 48 hours is not an implementation of a right.
   *
   * Clinical documents are described, not embedded: their bytes live behind the
   * records download path and this response has to stay a bounded JSON object.
   */
  r.get(
    "/export",
    handler(async (req, res) => {
      const firestore = db();
      const userId = req.auth!.sub;
      const user = req.user!;

      const [appointments, grants, requests, accessLog, sessions] = await Promise.all([
        firestore.collection(C.appointments).where("patientId", "==", userId).get(),
        firestore.collection(C.consentGrants).where("patientId", "==", userId).get(),
        firestore.collection(C.consentRequests).where("patientId", "==", userId).get(),
        firestore.collection(C.accessLog).where("patientId", "==", userId).get(),
        firestore.collection(C.sessions).where("userId", "==", userId).get(),
      ]);

      const plain = (d: FirebaseFirestore.QueryDocumentSnapshot) => ({
        id: d.id,
        ...JSON.parse(JSON.stringify(d.data())),
      });

      res.json({
        generatedAt: new Date().toISOString(),
        account: {
          userId,
          role: user.role,
          status: user.status,
          displayName: user.displayName ?? null,
          email: user.email ?? null,
          phone: user.phone ?? null,
        },
        appointments: appointments.docs.map(plain),
        consentGrants: grants.docs.map(plain),
        consentRequests: requests.docs.map(plain),
        recordAccessLog: accessLog.docs.map(plain),
        // Device ids only; no token material is ever returned.
        devices: sessions.docs.map((d) => ({
          id: d.id,
          deviceId: d.data().deviceId,
          platform: d.data().platform,
          createdAt: d.data().createdAt?.toDate?.()?.toISOString() ?? null,
          revokedAt: d.data().revokedAt?.toDate?.()?.toISOString() ?? null,
        })),
      });
    })
  );

  /**
   * DPDP s.12 — the right to erasure. Also App Store Review 5.1.1(v), which
   * requires account deletion to be initiable inside the app.
   *
   * What happens immediately: every consent grant is revoked, so no provider
   * retains access; upcoming appointments are cancelled; every session and
   * refresh token is destroyed, so the caller is signed out everywhere; and the
   * account is DEACTIVATED, which `requireAuth` refuses.
   *
   * What deliberately does not happen: the clinical tail is not deleted. It is
   * held for the statutory retention period recorded on the request and
   * destroyed then. Promising otherwise would be a lie a regulator can check.
   */
  r.delete(
    "/",
    handler(async (req, res) => {
      const firestore = db();
      const userId = req.auth!.sub;
      const at = Timestamp.now();

      const [grants, upcoming] = await Promise.all([
        firestore
          .collection(C.consentGrants)
          .where("patientId", "==", userId)
          .get(),
        firestore
          .collection(C.appointments)
          .where("patientId", "==", userId)
          .where("status", "==", "CONFIRMED")
          .get(),
      ]);

      const batch = firestore.batch();

      grants.forEach((g) => {
        if (!(g.data() as ConsentGrantDoc).revokedAt) {
          batch.update(g.ref, { revokedAt: at });
        }
      });

      upcoming.forEach((a) => {
        if ((a.data() as AppointmentDoc).start.toMillis() > at.toMillis()) {
          batch.update(a.ref, {
            status: "CANCELLED_BY_PATIENT",
            cancellationReason: "Account deleted",
          });
          // The slot returns to the pool rather than being lost.
          batch.delete(
            firestore
              .collection(C.slotLocks)
              .doc(slotLockId((a.data() as AppointmentDoc).doctorId, (a.data() as AppointmentDoc).start.toDate()))
          );
        }
      });

      const retentionUntil = Timestamp.fromMillis(
        at.toMillis() + CLINICAL_RETENTION_DAYS * 24 * 60 * 60 * 1000
      );

      batch.set(firestore.collection(C.erasureRequests).doc(userId), {
        userId,
        requestedAt: at,
        clinicalRetentionUntil: retentionUntil,
        status: "REQUESTED",
        completedAt: null,
      } satisfies ErasureRequestDoc);

      batch.update(firestore.collection(C.users).doc(userId), {
        status: "DEACTIVATED",
        displayName: FieldValue.delete(),
        email: FieldValue.delete(),
        phone: FieldValue.delete(),
        photoUrl: FieldValue.delete(),
        permissionVersion: FieldValue.increment(1),
        updatedAt: at,
      });

      await batch.commit();

      // Signs the caller out on every device. Runs after the commit so a failure
      // here cannot leave the account live but tokenless.
      await revokeAllSessionsForUser(userId);

      logger.info("Erasure requested", { userId });

      res.json({
        status: "REQUESTED",
        clinicalRetentionUntil: retentionUntil.toDate().toISOString(),
      });
    })
  );

  return r;
}
