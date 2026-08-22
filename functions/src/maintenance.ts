import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { C, db, type AppointmentDoc, type MedicalRecordDoc } from "./api/db";
import { istWhen, notify } from "./api/notifications/send";
import { sweepMissingPrescriptionPdfs } from "./api/prescriptions/pdf_store";
import { QUARANTINE_PREFIX, deleteObject } from "./api/storage";

/**
 * Scheduled maintenance.
 *
 * Several states in this system were declared and unreachable because nothing
 * ever ran to write them: `EXPIRED` consent requests, `NO_SHOW` appointments,
 * abandoned slot holds, spent refresh tokens. Each was evaluated lazily at read
 * time, which is correct for authorization — an expiry that is only true when
 * someone remembers to check is not an expiry — but it leaves the data growing
 * without bound and the lifecycle only half-modelled.
 *
 * Everything here is idempotent and bounded. A missed run costs nothing but a
 * later cleanup; a run that dies halfway leaves a consistent database.
 */

/** Firestore refuses batches larger than this. */
const BATCH_LIMIT = 400;

async function commitInBatches(
  refs: FirebaseFirestore.DocumentReference[],
  apply: (batch: FirebaseFirestore.WriteBatch, ref: FirebaseFirestore.DocumentReference) => void
): Promise<number> {
  let written = 0;
  for (let i = 0; i < refs.length; i += BATCH_LIMIT) {
    const batch = db().batch();
    for (const ref of refs.slice(i, i + BATCH_LIMIT)) {
      apply(batch, ref);
      written++;
    }
    await batch.commit();
  }
  return written;
}

/**
 * Frequent, cheap cleanup of things that block other people.
 *
 * Abandoned slot holds are the urgent one: the booking path already treats an
 * expired hold as free, so this is not a correctness fix — it is what stops
 * `slotLocks` growing forever with documents nobody will ever read.
 */
export const sweepShortLived = onSchedule(
  { schedule: "every 15 minutes", region: "asia-south1", timeZone: "Asia/Kolkata" },
  async () => {
    const now = Timestamp.now();

    const staleHolds = await db()
      .collection(C.slotLocks)
      .where("state", "==", "HELD")
      .where("holdExpiresAt", "<", now)
      .limit(BATCH_LIMIT * 4)
      .get();

    const holds = await commitInBatches(
      staleHolds.docs.map((d) => d.ref),
      (batch, ref) => batch.delete(ref)
    );

    // A request the patient never answered lapses rather than lingering, so the
    // channel cannot be used as a standing fishing line.
    const lapsed = await db()
      .collection(C.consentRequests)
      .where("status", "==", "PENDING")
      .where("expiresAt", "<", now)
      .limit(BATCH_LIMIT * 4)
      .get();

    const requests = await commitInBatches(
      lapsed.docs.map((d) => d.ref),
      (batch, ref) => batch.update(ref, { status: "EXPIRED", resolvedAt: now })
    );

    // Prescriptions issued while object storage was unavailable. Retried here
    // rather than on the next read, because the person who needs the document
    // is usually a pharmacist holding a printout, not someone opening the app.
    const documents = await sweepMissingPrescriptionPdfs();

    const reminders = await sendDueReminders();

    if (holds || requests || documents || reminders) {
      logger.info("Short-lived sweep", { holds, requests, documents, reminders });
    }
  }
);

/**
 * Nightly, for things measured in days.
 *
 * Runs at 03:00 IST — the quietest hour for an Indian consumer product, and
 * before the morning clinic list is loaded.
 */
export const sweepNightly = onSchedule(
  { schedule: "0 3 * * *", region: "asia-south1", timeZone: "Asia/Kolkata" },
  async () => {
    const now = Timestamp.now();
    const nowMs = now.toMillis();

    // Spent and expired refresh tokens. Rotation marks the old document `usedAt`
    // and keeps it so reuse is detectable; that detection window does not need
    // to be permanent, and without this the collection only ever grows.
    const REUSE_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;
    const expiredTokens = await db()
      .collection(C.refreshTokens)
      .where("expiresAt", "<", Timestamp.fromMillis(nowMs - REUSE_WINDOW_MS))
      .limit(BATCH_LIMIT * 4)
      .get();

    const tokens = await commitInBatches(
      expiredTokens.docs.map((d) => d.ref),
      (batch, ref) => batch.delete(ref)
    );

    // Rate-limit counters are keyed by window, so yesterday's are dead weight.
    const oldCounters = await db()
      .collection(C.rateLimits)
      .where("expiresAt", "<", Timestamp.fromMillis(nowMs - 24 * 60 * 60 * 1000))
      .limit(BATCH_LIMIT * 4)
      .get();

    const counters = await commitInBatches(
      oldCounters.docs.map((d) => d.ref),
      (batch, ref) => batch.delete(ref)
    );

    // An upload that never completed leaves a PENDING record with nothing
    // behind it. After a day it is not "still uploading", it is abandoned.
    const stalled = await db()
      .collection(C.records)
      .where("scanStatus", "==", "PENDING")
      .where("uploadedAt", "<", Timestamp.fromMillis(nowMs - 24 * 60 * 60 * 1000))
      .limit(BATCH_LIMIT)
      .get();

    for (const doc of stalled.docs) {
      const record = doc.data() as MedicalRecordDoc;
      await deleteObject(`${QUARANTINE_PREFIX}/records/${record.patientId}/${doc.id}`);
    }
    const abandonedUploads = await commitInBatches(
      stalled.docs.map((d) => d.ref),
      (batch, ref) =>
        batch.update(ref, {
          scanStatus: "FAILED",
          rejectionReason: "The upload did not finish. Please try again.",
        })
    );

    // Appointments nobody attended. Marked rather than deleted: a no-show is
    // clinically and commercially meaningful, and the patient can see it.
    const missed = await db()
      .collection(C.appointments)
      .where("status", "in", ["CONFIRMED", "CHECKED_IN"])
      .where("end", "<", Timestamp.fromMillis(nowMs - 24 * 60 * 60 * 1000))
      .limit(BATCH_LIMIT)
      .get();

    const noShows = await commitInBatches(
      missed.docs.map((d) => d.ref),
      (batch, ref) => batch.update(ref, { status: "NO_SHOW_PATIENT" })
    );

    // Holds for appointments that are long over.
    const staleBooked = await db()
      .collection(C.slotLocks)
      .where("state", "==", "BOOKED")
      .where("end", "<", Timestamp.fromMillis(nowMs - 90 * 24 * 60 * 60 * 1000))
      .limit(BATCH_LIMIT * 4)
      .get();

    const oldLocks = await commitInBatches(
      staleBooked.docs.map((d) => d.ref),
      (batch, ref) => batch.delete(ref)
    );

    logger.info("Nightly sweep", {
      tokens,
      counters,
      abandonedUploads,
      noShows,
      oldLocks,
    });
  }
);

/**
 * Completes erasure requests whose clinical retention has lapsed.
 *
 * The account was deactivated and its consent grants revoked at request time;
 * this is the part that had to wait. Records are removed here, not earlier,
 * because medical records carry a statutory retention period that outlives the
 * account — telling a patient their data is gone while keeping it would be the
 * lie the request document exists to prevent.
 */
export const completeErasures = onSchedule(
  { schedule: "0 4 * * *", region: "asia-south1", timeZone: "Asia/Kolkata" },
  async () => {
    const now = Timestamp.now();

    const due = await db()
      .collection(C.erasureRequests)
      .where("status", "==", "REQUESTED")
      .where("clinicalRetentionUntil", "<", now)
      .limit(50)
      .get();

    for (const doc of due.docs) {
      const userId = doc.id;

      const records = await db()
        .collection(C.records)
        .where("patientId", "==", userId)
        .get();

      for (const rec of records.docs) {
        const record = rec.data() as MedicalRecordDoc;
        if (record.objectPath) await deleteObject(record.objectPath);
      }
      await commitInBatches(
        records.docs.map((d) => d.ref),
        (batch, ref) => batch.delete(ref)
      );

      // Appointments are anonymised rather than deleted: aggregate clinical and
      // billing history has to survive, the person attached to it does not.
      const appointments = await db()
        .collection(C.appointments)
        .where("patientId", "==", userId)
        .get();

      await commitInBatches(
        appointments.docs.map((d) => d.ref),
        (batch, ref) =>
          batch.update(ref, {
            patientName: "Deleted user",
            reasonForVisit: null,
          })
      );

      await doc.ref.update({ status: "COMPLETED", completedAt: now });
      logger.info("Erasure completed", {
        userId,
        records: records.size,
        appointments: appointments.size,
      });
    }
  }
);

/**
 * Appointment reminders, roughly 24 hours and 1 hour ahead.
 *
 * Runs on the 15-minute sweep rather than a per-appointment scheduled task.
 * One job that asks "what is due?" survives a deploy, a retry and a
 * clock skew; ten thousand individually scheduled tasks are ten thousand
 * things that can be scheduled once and then silently not fire — and the
 * failure is invisible until a patient misses a consultation.
 *
 * Idempotent through `remindersSent`, an array on the appointment. A sweep
 * that ran twice would otherwise send the same reminder twice, and the second
 * one teaches people to ignore the first.
 */
const REMINDER_OFFSETS: { key: string; leadMs: number }[] = [
  { key: "T24H", leadMs: 24 * 60 * 60 * 1000 },
  { key: "T1H", leadMs: 60 * 60 * 1000 },
];

/** How far past the ideal moment a reminder is still worth sending. */
const REMINDER_GRACE_MS = 30 * 60 * 1000;

export async function sendDueReminders(limit = 100): Promise<number> {
  const now = Date.now();
  const furthest = Math.max(...REMINDER_OFFSETS.map((o) => o.leadMs));

  const snap = await db()
    .collection(C.appointments)
    .where("status", "==", "CONFIRMED")
    .where("start", ">", Timestamp.fromMillis(now))
    .where("start", "<", Timestamp.fromMillis(now + furthest))
    .limit(limit)
    .get();

  let sent = 0;

  for (const doc of snap.docs) {
    const a = doc.data() as AppointmentDoc;
    const already: string[] = (a as { remindersSent?: string[] }).remindersSent ?? [];
    const startMs = a.start.toMillis();

    for (const offset of REMINDER_OFFSETS) {
      if (already.includes(offset.key)) continue;

      const dueAt = startMs - offset.leadMs;
      // Not yet, or so long ago that the next reminder is more useful than a
      // stale one.
      if (now < dueAt || now > dueAt + REMINDER_GRACE_MS) continue;

      const id = await notify({
        userId: a.patientId,
        kind: "APPOINTMENT_REMINDER",
        title: offset.key === "T1H" ? "Your consultation is in an hour" : "Consultation tomorrow",
        // No condition, no reason for visit. This lands on a lock screen.
        body: istWhen(a.start.toDate()),
        targetId: doc.id,
      });

      // Marked regardless of whether a push went out: the user's own
      // preferences may have suppressed it, and retrying every 15 minutes
      // against a preference that will not change is a loop, not a retry.
      await doc.ref.update({
        remindersSent: FieldValue.arrayUnion(offset.key),
      });

      if (id) sent++;
    }
  }

  return sent;
}
