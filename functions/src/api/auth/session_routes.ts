import { FieldValue } from "firebase-admin/firestore";
import { Router } from "express";

import { requireAuth } from "./middleware";
import { revokeSession } from "./tokens";
import { C, db, type SessionDoc } from "../db";
import { handler, Problem } from "../errors";

/**
 * Where an account is signed in, and how to end one of those sessions.
 *
 * The remedy that would otherwise not exist here. Identity is Google, Apple or
 * a phone OTP, so there is no password to change: without this, a patient who
 * handed their phone to somebody in a waiting room has no way to undo it.
 *
 * ## What is returned, and what is not
 *
 * Platform, app version, created, last seen. **No IP address and no location.**
 * A "signed in from Mumbai, 49.36.x.x" line reads as reassuring security
 * detail and is really a location history of the account holder, retained
 * indefinitely and shown to whoever is holding an unlocked phone — including
 * the person a patient might be hiding a consultation from. The DPDP Act's
 * minimisation duty points the same way: the question this answers is "is
 * there a session here I do not recognise", and platform plus last-seen
 * answers it.
 *
 * ## Why revoking bumps `permissionVersion`
 *
 * `requireAuth` reads `users`, never `sessions`. Marking a session revoked
 * therefore does nothing to an access token already in an attacker's hands —
 * it stays valid for the rest of its fifteen minutes. Incrementing
 * `permissionVersion` is what turns the next request from that token into
 * `TOKEN_STALE`, which is the whole point of pressing the button.
 */

function sessionJson(id: string, s: SessionDoc, currentSid: string) {
  return {
    id,
    platform: s.platform,
    appVersion: s.appVersion,
    createdAt: s.createdAt.toDate().toISOString(),
    lastSeenAt: s.lastSeenAt.toDate().toISOString(),
    // Decided here, not by the client comparing ids. A client that got this
    // wrong would offer "sign out everywhere else" and sign the user out of
    // the device in their hand.
    isCurrent: id === currentSid,
  };
}

/** Every authorization change increments it, so the change lands next request. */
async function bumpPermissionVersion(userId: string): Promise<void> {
  await db()
    .collection(C.users)
    .doc(userId)
    .update({ permissionVersion: FieldValue.increment(1) });
}

export function sessionRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  /** `GET /v1/auth/sessions` — live sessions for the caller. */
  r.get(
    "/",
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.sessions)
        .where("userId", "==", req.auth!.sub)
        .get();

      const live = snap.docs
        .filter((d) => !(d.data() as SessionDoc).revokedAt)
        .map((d) => sessionJson(d.id, d.data() as SessionDoc, req.auth!.sid))
        .sort((a, b) => {
          // The device in your hand first: it is the one row a person has to
          // identify before deciding anything about the others.
          if (a.isCurrent !== b.isCurrent) return a.isCurrent ? -1 : 1;
          return b.lastSeenAt.localeCompare(a.lastSeenAt);
        });

      res.json(live);
    })
  );

  /** `DELETE /v1/auth/sessions/:id` — end one session, including this one. */
  r.delete(
    "/:id",
    handler(async (req, res) => {
      const ref = db().collection(C.sessions).doc(req.params.id);
      const snap = await ref.get();

      // Same answer whether it never existed or belongs to somebody else:
      // distinguishing them would report whose session ids are real.
      if (!snap.exists || (snap.data() as SessionDoc).userId !== req.auth!.sub) {
        throw Problem.notFound("SESSION_NOT_FOUND", "Not found.");
      }

      await revokeSession(req.params.id);
      await bumpPermissionVersion(req.auth!.sub);

      res.json({ id: req.params.id, revoked: true });
    })
  );

  /**
   * `POST /v1/auth/sessions/revoke-others` — everything but this session.
   *
   * The button people actually want. It is also the one an attacker would
   * press, which is why it bumps `permissionVersion` like every other
   * authorization change and why the client files an account notification:
   * being signed out of your own devices must not be something that happens
   * quietly.
   */
  r.post(
    "/revoke-others",
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.sessions)
        .where("userId", "==", req.auth!.sub)
        .get();

      const others = snap.docs.filter(
        (d) => d.id !== req.auth!.sid && !(d.data() as SessionDoc).revokedAt
      );

      for (const doc of others) await revokeSession(doc.id);
      if (others.length) await bumpPermissionVersion(req.auth!.sub);

      res.json({ revoked: others.length });
    })
  );

  return r;
}
