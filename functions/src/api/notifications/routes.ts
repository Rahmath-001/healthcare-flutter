import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { requireAuth } from "../auth/middleware";
import {
  C,
  db,
  type DeviceDoc,
  type NotificationDoc,
  type NotificationKind,
  type NotificationPreferencesDoc,
} from "../db";
import { handler, Problem } from "../errors";
import { defaults, MANDATORY } from "./send";

const KINDS: NotificationKind[] = [
  "APPOINTMENT_REMINDER",
  "APPOINTMENT_CHANGED",
  "PRESCRIPTION_ISSUED",
  "CONSENT_REQUESTED",
  "RECORD_READY",
  "RATING_REQUESTED",
  "ACCOUNT_UPDATE",
];

/** How much history the centre shows. */
const PAGE_LIMIT = 100;

function notificationJson(id: string, n: NotificationDoc) {
  return {
    id,
    kind: n.kind,
    title: n.title,
    body: n.body,
    targetId: n.targetId ?? null,
    createdAt: n.createdAt.toDate().toISOString(),
    readAt: n.readAt?.toDate().toISOString() ?? null,
  };
}

export function notificationRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  /**
   * The notification centre.
   *
   * Scoped to the caller by query rather than by a path parameter: a
   * `/v1/notifications/:userId` shape would make it possible to ask for
   * someone else's, and then the only thing standing between a patient and a
   * stranger's appointment history is a comparison somebody remembered to
   * write.
   */
  r.get(
    "/",
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.notifications)
        .where("userId", "==", req.auth!.sub)
        .orderBy("createdAt", "desc")
        .limit(PAGE_LIMIT)
        .get();

      res.json(
        snap.docs.map((d) => notificationJson(d.id, d.data() as NotificationDoc))
      );
    })
  );

  r.post(
    "/read-all",
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.notifications)
        .where("userId", "==", req.auth!.sub)
        .where("readAt", "==", null)
        .limit(500)
        .get();

      const batch = db().batch();
      const at = Timestamp.now();
      snap.docs.forEach((d) => batch.update(d.ref, { readAt: at }));
      await batch.commit();

      res.json({ ok: true, marked: snap.size });
    })
  );

  r.post(
    "/:id/read",
    handler(async (req, res) => {
      const ref = db().collection(C.notifications).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("NOTIFICATION_NOT_FOUND", "Not found.");

      const n = snap.data() as NotificationDoc;
      if (n.userId !== req.auth!.sub) {
        // Same shape as an unknown id. Confirming that a notification exists
        // but belongs to someone else is itself information.
        throw Problem.notFound("NOTIFICATION_NOT_FOUND", "Not found.");
      }

      if (!n.readAt) await ref.update({ readAt: Timestamp.now() });
      res.json({ ok: true });
    })
  );

  r.get(
    "/preferences",
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.notificationPreferences)
        .doc(req.auth!.sub)
        .get();

      const prefs = snap.exists
        ? (snap.data() as NotificationPreferencesDoc)
        : { ...defaults, updatedAt: Timestamp.now() };

      res.json({
        enabled: prefs.enabled,
        quietHours: prefs.quietHours,
      });
    })
  );

  r.put(
    "/preferences",
    handler(async (req, res) => {
      const body = req.body ?? {};

      if (!Array.isArray(body.enabled)) {
        throw Problem.validation("Expected a list of kinds.", { enabled: "invalid" });
      }

      const enabled = (body.enabled as unknown[])
        .filter((k): k is NotificationKind => KINDS.includes(k as NotificationKind))
        // Mandatory kinds are dropped rather than stored. Keeping them in the
        // list would imply the toggle means something, and the day someone
        // "unchecks" one by omitting it, the omission must not silence an
        // appointment cancellation.
        .filter((k) => !MANDATORY.includes(k));

      const quiet = body.quietHours ?? {};
      const startHour = Number(quiet.startHour);
      const endHour = Number(quiet.endHour);
      const validHour = (h: number) => Number.isInteger(h) && h >= 0 && h <= 23;

      if (!validHour(startHour) || !validHour(endHour)) {
        throw Problem.validation("Quiet hours must be whole hours.", {
          quietHours: "invalid",
        });
      }

      const doc: NotificationPreferencesDoc = {
        enabled,
        quietHours: { startHour, endHour },
        updatedAt: Timestamp.now(),
      };

      await db()
        .collection(C.notificationPreferences)
        .doc(req.auth!.sub)
        .set(doc);

      res.json({ enabled: doc.enabled, quietHours: doc.quietHours });
    })
  );

  /**
   * Registers this install's push token.
   *
   * The token is the document id, so re-registering the same token is an
   * update rather than a duplicate — which matters because the client
   * registers on every launch and on every rotation.
   *
   * Re-registering a token that belonged to someone else **reassigns** it.
   * Phones get handed over and reinstalled; a token still mapped to the
   * previous user would deliver their appointments to whoever is holding the
   * device now.
   */
  r.post(
    "/devices",
    handler(async (req, res) => {
      const { token, platform } = req.body ?? {};
      if (typeof token !== "string" || token.length < 16) {
        throw Problem.validation("A device token is required.", { token: "required" });
      }

      const at = Timestamp.now();
      await db()
        .collection(C.devices)
        .doc(token)
        .set(
          {
            userId: req.auth!.sub,
            platform: typeof platform === "string" ? platform : "unknown",
            createdAt: at,
            lastSeenAt: at,
          } satisfies DeviceDoc,
          // `createdAt` is overwritten on re-registration, which is a small
          // inaccuracy accepted in exchange for not reading before writing on
          // a call that happens every launch.
          { merge: false }
        );

      res.json({ ok: true });
    })
  );

  /**
   * Detaches every device belonging to the caller.
   *
   * All of them rather than the one presenting: sign-out is "stop sending to
   * me", and a client cannot always produce its token at the moment it signs
   * out — the token call can fail, and the sign-out must not.
   */
  r.delete(
    "/devices",
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.devices)
        .where("userId", "==", req.auth!.sub)
        .get();

      const batch = db().batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();

      res.json({ ok: true, removed: snap.size });
    })
  );

  return r;
}

/** Deletes every notification for a user. Used by the erasure path. */
export async function deleteNotificationsFor(userId: string): Promise<number> {
  const snap = await db()
    .collection(C.notifications)
    .where("userId", "==", userId)
    .limit(500)
    .get();

  const batch = db().batch();
  snap.docs.forEach((d) => batch.delete(d.ref));
  batch.delete(db().collection(C.notificationPreferences).doc(userId));
  await batch.commit();

  return snap.size;
}
