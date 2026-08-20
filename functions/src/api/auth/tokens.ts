import { createHash, randomBytes, randomUUID } from "crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import jwt from "jsonwebtoken";

import { C, db, type RefreshTokenDoc, type SessionDoc, type UserDoc } from "../db";
import { Problem } from "../errors";
import { scopesFor } from "./scopes";

/** Short, because revocation only bites when tokens are short-lived. */
export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;

/** Long, because the refresh token is rotated on every single use. */
const REFRESH_TOKEN_TTL_DAYS = 60;

export interface AccessClaims {
  sub: string;
  sid: string;
  role: string;
  status: string;
  providerStatus: string;
  scopes: string[];
  /** Mirrors `users.permissionVersion`; a mismatch means the token is stale. */
  ver: number;
}

export function mintAccessToken(
  secret: string,
  userId: string,
  sessionId: string,
  user: UserDoc
): { token: string; expiresIn: number; scopes: string[] } {
  const scopes = scopesFor(user.role, user.providerStatus);
  const claims: AccessClaims = {
    sub: userId,
    sid: sessionId,
    role: user.role,
    status: user.status,
    providerStatus: user.providerStatus,
    scopes,
    ver: user.permissionVersion,
  };

  const token = jwt.sign(claims, secret, {
    algorithm: "HS256",
    expiresIn: ACCESS_TOKEN_TTL_SECONDS,
    issuer: "midoctor",
    audience: "midoctor-mobile",
  });

  return { token, expiresIn: ACCESS_TOKEN_TTL_SECONDS, scopes };
}

export function verifyAccessToken(secret: string, token: string): AccessClaims {
  try {
    return jwt.verify(token, secret, {
      algorithms: ["HS256"],
      issuer: "midoctor",
      audience: "midoctor-mobile",
    }) as AccessClaims;
  } catch {
    throw Problem.unauthorized("TOKEN_INVALID", "Please sign in again.");
  }
}

/** Tokens are stored hashed so a database dump is not a set of live credentials. */
function hashToken(raw: string): string {
  return createHash("sha256").update(raw).digest("hex");
}

/**
 * Issues a refresh token and records its hash.
 *
 * [familyId] ties every token descended from one sign-in together, so reuse
 * detection can revoke the whole lineage rather than just the presented token.
 */
export async function issueRefreshToken(
  userId: string,
  sessionId: string,
  familyId: string
): Promise<string> {
  const raw = randomBytes(32).toString("hex");
  const expiresAt = Timestamp.fromMillis(
    Date.now() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000
  );

  const doc: RefreshTokenDoc = { userId, sessionId, familyId, expiresAt, usedAt: null, revokedAt: null };
  await db().collection(C.refreshTokens).doc(hashToken(raw)).set(doc);
  return raw;
}

/**
 * Single-use rotation with reuse detection.
 *
 * Presenting a token that has already been rotated means either an attacker
 * replaying a stolen token or a legitimate client that raced itself. Both are
 * handled the same way — revoke the entire family — because the server cannot
 * distinguish them and the safe reading is theft.
 *
 * This is precisely why the Flutter client has `RefreshCoordinator`: without
 * single-flight refresh on the client, two concurrent 401s would present the
 * same token twice and log the user out for doing nothing wrong.
 */
export async function rotateRefreshToken(
  presented: string
): Promise<{ userId: string; sessionId: string; newToken: string }> {
  const firestore = db();
  const tokenRef = firestore.collection(C.refreshTokens).doc(hashToken(presented));

  const familyToRevoke = await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(tokenRef);
    if (!snap.exists) throw Problem.unauthorized("REFRESH_INVALID", "Please sign in again.");

    const doc = snap.data() as RefreshTokenDoc;

    if (doc.revokedAt) throw Problem.unauthorized("REFRESH_REVOKED", "Please sign in again.");
    if (doc.expiresAt.toMillis() < Date.now()) {
      throw Problem.unauthorized("REFRESH_EXPIRED", "Please sign in again.");
    }

    if (doc.usedAt) {
      // Reuse detected. Mark the family and let the caller revoke it outside
      // the transaction, where an unbounded query is safe to run.
      return doc.familyId;
    }

    tx.update(tokenRef, { usedAt: Timestamp.now() });
    return null;
  });

  if (familyToRevoke) {
    await revokeFamily(familyToRevoke);
    logger.warn("Refresh token reuse detected; family revoked", { familyId: familyToRevoke });
    throw Problem.unauthorized("REFRESH_REUSED", "Please sign in again.");
  }

  const doc = (await tokenRef.get()).data() as RefreshTokenDoc;
  const newToken = await issueRefreshToken(doc.userId, doc.sessionId, doc.familyId);
  return { userId: doc.userId, sessionId: doc.sessionId, newToken };
}

/**
 * Revokes every refresh token and session in one lineage, and invalidates the
 * access tokens that were minted alongside them.
 *
 * The access-token half matters more than it looks. Stamping `sessions.revokedAt`
 * alone changes nothing a caller can feel: `requireAuth` reads `users`, not
 * `sessions`, so a token stolen before a logout would keep working for the
 * remainder of its 15-minute life — including after reuse detection, which is
 * exactly the case where it must not.
 *
 * Bumping `permissionVersion` closes that window using machinery that already
 * exists: the next request carrying an older `ver` fails as `TOKEN_STALE`, the
 * client refreshes, and the refresh fails because the token it would present
 * has just been revoked. The alternative — reading the session document on every
 * authenticated request — doubles the per-request Firestore cost to enforce the
 * same thing.
 *
 * The cost is that a logout on one device forces the user's other devices to
 * refresh once on their next call. They hold valid refresh tokens in a different
 * family, so they recover silently.
 */
export async function revokeFamily(familyId: string): Promise<void> {
  const firestore = db();
  const tokens = await firestore
    .collection(C.refreshTokens)
    .where("familyId", "==", familyId)
    .get();

  const batch = firestore.batch();
  const revokedAt = Timestamp.now();
  const userIds = new Set<string>();

  tokens.forEach((t) => {
    batch.update(t.ref, { revokedAt });
    userIds.add((t.data() as RefreshTokenDoc).userId);
  });

  const sessions = await firestore
    .collection(C.sessions)
    .where("familyId", "==", familyId)
    .get();
  sessions.forEach((s) => {
    batch.update(s.ref, { revokedAt });
    userIds.add((s.data() as SessionDoc).userId);
  });

  for (const userId of userIds) {
    batch.update(firestore.collection(C.users).doc(userId), {
      permissionVersion: FieldValue.increment(1),
      updatedAt: revokedAt,
    });
  }

  await batch.commit();
}

/**
 * Signs a user out on every device.
 *
 * `revokeFamily` covers one sign-in lineage, which is the right unit for a
 * logout or a stolen-token event. Deactivation and erasure are account-level and
 * have to reach lineages the caller is not currently holding.
 */
export async function revokeAllSessionsForUser(userId: string): Promise<void> {
  const firestore = db();
  const [tokens, sessions] = await Promise.all([
    firestore.collection(C.refreshTokens).where("userId", "==", userId).get(),
    firestore.collection(C.sessions).where("userId", "==", userId).get(),
  ]);

  const batch = firestore.batch();
  const revokedAt = Timestamp.now();
  tokens.forEach((t) => batch.update(t.ref, { revokedAt }));
  sessions.forEach((sn) => batch.update(sn.ref, { revokedAt }));
  await batch.commit();
}

export async function revokeSession(sessionId: string): Promise<void> {
  const firestore = db();
  const sessionRef = firestore.collection(C.sessions).doc(sessionId);
  const snap = await sessionRef.get();
  if (!snap.exists) return;
  await revokeFamily((snap.data() as SessionDoc).familyId);
}

export async function createSession(
  userId: string,
  deviceId: string,
  platform: string,
  appVersion: string
): Promise<{ sessionId: string; refreshToken: string }> {
  const sessionId = randomUUID();
  const familyId = randomUUID();
  const at = Timestamp.now();

  const session: SessionDoc = {
    userId,
    deviceId,
    platform,
    appVersion,
    familyId,
    createdAt: at,
    lastSeenAt: at,
    revokedAt: null,
  };

  await db().collection(C.sessions).doc(sessionId).set(session);
  const refreshToken = await issueRefreshToken(userId, sessionId, familyId);
  return { sessionId, refreshToken };
}
