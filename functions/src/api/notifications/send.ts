import { Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";

import {
  C,
  db,
  type DeviceDoc,
  type NotificationDoc,
  type NotificationKind,
  type NotificationPreferencesDoc,
  type QuietHoursDoc,
} from "../db";

/**
 * Composing, filtering and delivering notifications.
 *
 * The rules below are the same ones the Dart domain carries. They are stated
 * twice on purpose — the client needs them to render an honest preference
 * screen, and the server needs them because a client-side filter only stops
 * the app from *displaying* something the phone has already buzzed about and
 * put on the lock screen. This file is the one that decides.
 */

/** Kinds nobody may switch off. */
const MANDATORY: NotificationKind[] = ["APPOINTMENT_CHANGED", "ACCOUNT_UPDATE"];

/** Kinds allowed to arrive at 3am. */
const BYPASSES_QUIET_HOURS: NotificationKind[] = [
  "APPOINTMENT_CHANGED",
  "ACCOUNT_UPDATE",
];

const DEFAULT_QUIET_HOURS: QuietHoursDoc = { startHour: 22, endHour: 7 };

const DEFAULT_ENABLED: NotificationKind[] = [
  "APPOINTMENT_REMINDER",
  "PRESCRIPTION_ISSUED",
  "CONSENT_REQUESTED",
  "RECORD_READY",
  "RATING_REQUESTED",
];

/**
 * IST, always. Quiet hours are the user's evening, and Cloud Functions runs in
 * UTC — evaluating 22:00–07:00 against a UTC clock puts the quiet window in the
 * middle of an Indian afternoon. The same fixed-offset reasoning as
 * `booking/routes.ts`: India has one timezone and no DST, so an offset is
 * exact.
 */
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

export function istHour(at: Date): number {
  return new Date(at.getTime() + IST_OFFSET_MS).getUTCHours();
}

export function isQuiet(quietHours: QuietHoursDoc, at: Date): boolean {
  const { startHour, endHour } = quietHours;
  if (startHour === endHour) return false;
  const hour = istHour(at);
  // Wraps past midnight: with 22–07 both 23:00 and 02:00 are quiet, which a
  // naive `hour >= start && hour < end` gets exactly backwards.
  if (startHour < endHour) return hour >= startHour && hour < endHour;
  return hour >= startHour || hour < endHour;
}

/** Whether this kind may be delivered to this user, right now. */
export function allows(
  preferences: NotificationPreferencesDoc,
  kind: NotificationKind,
  at: Date
): boolean {
  // Mandatory kinds ignore both the toggle and the window. Someone finding out
  // at 9am that they travelled to a cancelled appointment at 8am is worse than
  // being woken.
  if (MANDATORY.includes(kind)) return true;
  if (!preferences.enabled.includes(kind)) return false;
  if (BYPASSES_QUIET_HOURS.includes(kind)) return true;
  return !isQuiet(preferences.quietHours, at);
}

export async function preferencesFor(
  userId: string
): Promise<NotificationPreferencesDoc> {
  const snap = await db().collection(C.notificationPreferences).doc(userId).get();
  if (!snap.exists) {
    return {
      enabled: DEFAULT_ENABLED,
      quietHours: DEFAULT_QUIET_HOURS,
      updatedAt: Timestamp.now(),
    };
  }
  return snap.data() as NotificationPreferencesDoc;
}

/**
 * Files a notification and pushes it, if the user's preferences allow.
 *
 * Returns the id when one was filed, or null when the preferences suppressed
 * it. Suppressed notifications are **not** stored: a notification centre that
 * fills up with things the user asked not to receive is the toggle failing to
 * work, just more quietly.
 */
export async function notify(params: {
  userId: string;
  kind: NotificationKind;
  title: string;
  body: string;
  targetId?: string | null;
  at?: Date;
}): Promise<string | null> {
  const at = params.at ?? new Date();
  const preferences = await preferencesFor(params.userId);
  if (!allows(preferences, params.kind, at)) return null;

  const doc: NotificationDoc = {
    userId: params.userId,
    kind: params.kind,
    title: params.title,
    body: params.body,
    targetId: params.targetId ?? null,
    createdAt: Timestamp.fromDate(at),
    readAt: null,
    pushedAt: null,
  };

  const ref = await db().collection(C.notifications).add(doc);
  const pushed = await push(params.userId, doc);
  if (pushed) await ref.update({ pushedAt: Timestamp.now() });

  return ref.id;
}

/**
 * Delivers to every device this user has registered.
 *
 * Failure is not propagated. The notification is already filed and will be
 * visible in the centre next time the app opens; failing the caller — which is
 * usually something like "issue this prescription" — would undo a clinical
 * action because a push gateway was briefly unavailable.
 */
async function push(userId: string, doc: NotificationDoc): Promise<boolean> {
  const devices = await db()
    .collection(C.devices)
    .where("userId", "==", userId)
    .get();

  if (devices.empty) return false;

  const tokens = devices.docs.map((d) => d.id);

  try {
    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title: doc.title, body: doc.body },
      // The routing hint goes in `data`, which is delivered identically
      // whether the app is foreground, background or terminated. The
      // `notification` block is not: Android does not hand it to the app when
      // the app is in the foreground.
      data: {
        kind: doc.kind,
        ...(doc.targetId ? { targetId: doc.targetId } : {}),
      },
      android: { priority: "high" },
      apns: {
        payload: {
          aps: {
            // Lets iOS group by kind rather than stacking every notification
            // from the app into one undifferentiated pile.
            threadId: doc.kind,
          },
        },
      },
    });

    await pruneDeadTokens(response.responses, tokens);
    return response.successCount > 0;
  } catch (e) {
    logger.error("Push delivery failed", {
      userId,
      kind: doc.kind,
      error: e instanceof Error ? e.message : "unknown",
    });
    return false;
  }
}

/**
 * Removes tokens FCM says no longer exist.
 *
 * Without this the device collection only grows, and every send to a
 * reinstalled app wastes a request and logs an error forever.
 */
async function pruneDeadTokens(
  responses: { success: boolean; error?: { code: string } }[],
  tokens: string[]
): Promise<void> {
  const dead: string[] = [];
  responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error?.code ?? "";
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token"
    ) {
      dead.push(tokens[i]);
    }
  });

  if (dead.length === 0) return;

  const batch = db().batch();
  dead.forEach((t) => batch.delete(db().collection(C.devices).doc(t)));
  await batch.commit();
}

/**
 * "23 Aug at 4:30 PM", in IST.
 *
 * Every notification that mentions a time formats it here. Cloud Functions
 * runs in UTC, so an appointment rendered from the raw instant tells an Indian
 * patient their 4:30 PM consultation is at 11:00 AM — the same trap
 * `booking/routes.ts` documents for slot arithmetic, arriving by a different
 * road.
 */
export function istWhen(at: Date): string {
  const ist = new Date(at.getTime() + IST_OFFSET_MS);
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  const h24 = ist.getUTCHours();
  const h = h24 % 12 === 0 ? 12 : h24 % 12;
  const m = ist.getUTCMinutes().toString().padStart(2, "0");
  return `${ist.getUTCDate()} ${months[ist.getUTCMonth()]} at ${h}:${m} ${h24 < 12 ? "AM" : "PM"}`;
}

/** The default preferences, for the GET endpoint and for tests. */
export const defaults = {
  enabled: DEFAULT_ENABLED,
  quietHours: DEFAULT_QUIET_HOURS,
};

export { MANDATORY, BYPASSES_QUIET_HOURS };
