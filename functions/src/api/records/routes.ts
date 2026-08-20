import { randomUUID } from "crypto";
import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { requireAuth, requireScope } from "../auth/middleware";
import { activeGrantFor, grantCovers, logAccess, noteGrantUse } from "../consent/access";
import {
  C,
  db,
  type MedicalRecordDoc,
  type RecordType,
  type ScanStatus,
} from "../db";
import { handler, Problem } from "../errors";
import {
  assertAllowedContentType,
  cleanPath,
  deleteObject,
  quarantinePath,
  signedDownloadUrl,
  signedUploadUrl,
} from "../storage";

/**
 * Medical records.
 *
 * The patient owns every record regardless of who uploaded it (FR-MR-002).
 * A provider never lists "a patient's records" — they list the intersection of
 * that patient's records and a live consent grant, which is why there is no
 * endpoint that takes a patient id without resolving one first.
 *
 * Upload is a three-step dance, and the shape is deliberate:
 *
 *   1. `POST /v1/records` creates the metadata and returns a signed URL.
 *   2. The client PUTs the bytes straight to Cloud Storage, into quarantine.
 *   3. A storage trigger inspects them and promotes or rejects the object.
 *
 * The metadata exists before the bytes because the client needs the record id
 * to know where to put them. That leaves a window where a record is PENDING
 * with nothing behind it — which is correct, and is why `scanStatus` gates
 * every read rather than the object's existence.
 */

const RECORD_TYPES: RecordType[] = [
  "LAB_REPORT",
  "SCAN",
  "XRAY",
  "PRESCRIPTION",
  "DISCHARGE_SUMMARY",
  "VACCINATION",
  "OTHER",
];

const MAX_RECORD_BYTES = 25 * 1024 * 1024;

function recordJson(id: string, r: MedicalRecordDoc) {
  return {
    id,
    title: r.title,
    type: r.type,
    source: r.source,
    recordedAt: r.recordedAt.toDate().toISOString(),
    uploadedAt: r.uploadedAt.toDate().toISOString(),
    scanStatus: r.scanStatus,
    sizeBytes: r.sizeBytes,
    contentType: r.contentType,
    issuedByName: r.issuedByName ?? null,
    notes: r.notes ?? null,
    pageCount: r.pageCount ?? null,
  };
}

function activeRecordsQuery(patientId: string) {
  return db()
    .collection(C.records)
    .where("patientId", "==", patientId)
    .orderBy("recordedAt", "desc");
}

/** A soft-deleted record is gone from every list but still auditable. */
function notDeleted(r: MedicalRecordDoc): boolean {
  return !r.deletedAt;
}

export function recordRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  /** The caller's own records. */
  r.get(
    "/",
    requireScope("records:read_own"),
    handler(async (req, res) => {
      const snap = await activeRecordsQuery(req.auth!.sub).get();
      res.json(
        snap.docs
          .map((d) => ({ id: d.id, r: d.data() as MedicalRecordDoc }))
          .filter(({ r: rec }) => notDeleted(rec))
          .map(({ id, r: rec }) => recordJson(id, rec))
      );
    })
  );

  /**
   * Creates a record and returns somewhere to put the file.
   *
   * `sizeBytes` and `contentType` are the client's declaration. Both are
   * re-derived after upload; this pair exists to fail a hopeless upload before
   * the user spends their data allowance on it.
   */
  r.post(
    "/",
    requireScope("records:write_own"),
    handler(async (req, res) => {
      const { title, type, recordedAt, contentType, sizeBytes, notes } = req.body ?? {};

      if (typeof title !== "string" || title.trim().length < 2) {
        throw Problem.validation("Give the record a title.", { title: "required" });
      }
      if (!RECORD_TYPES.includes(type)) {
        throw Problem.validation("Unknown record type.", { type: "invalid" });
      }
      const declaredType = assertAllowedContentType(contentType);

      const size = Number(sizeBytes);
      if (!Number.isInteger(size) || size <= 0) {
        throw Problem.validation("The file appears to be empty.", { sizeBytes: "invalid" });
      }
      if (size > MAX_RECORD_BYTES) {
        throw Problem.validation("Files must be smaller than 25 MB.", {
          sizeBytes: "too large",
        });
      }

      const recordedMs = Date.parse(typeof recordedAt === "string" ? recordedAt : "");
      if (Number.isNaN(recordedMs)) {
        throw Problem.validation("When was this taken?", { recordedAt: "invalid" });
      }
      if (recordedMs > Date.now()) {
        throw Problem.validation("A record cannot be dated in the future.", {
          recordedAt: "future",
        });
      }

      const id = randomUUID();
      const now = Timestamp.now();
      const doc: MedicalRecordDoc = {
        patientId: req.auth!.sub,
        title: title.trim(),
        type,
        source: "PATIENT",
        recordedAt: Timestamp.fromMillis(recordedMs),
        uploadedAt: now,
        scanStatus: "PENDING",
        contentType: declaredType,
        sizeBytes: size,
        objectPath: null,
        notes: typeof notes === "string" && notes.trim() ? notes.trim() : null,
        deletedAt: null,
      };

      await db().collection(C.records).doc(id).set(doc);

      const upload = await signedUploadUrl(
        quarantinePath("records", req.auth!.sub, id),
        declaredType
      );

      res.status(201).json({
        record: recordJson(id, doc),
        upload: {
          url: upload.url,
          method: "PUT",
          expiresAt: upload.expiresAt,
          // The signature is bound to this value; sending anything else fails.
          headers: { "Content-Type": declaredType },
        },
      });
    })
  );

  /**
   * A short-lived URL to read the file.
   *
   * Entitlement is re-checked here rather than trusted from the list call, and
   * the read is logged before the URL is minted — a log written only on success
   * is a log that omits exactly the events worth reviewing.
   */
  r.get(
    "/:id/download",
    handler(async (req, res) => {
      const snap = await db().collection(C.records).doc(req.params.id).get();
      if (!snap.exists) throw Problem.notFound("RECORD_NOT_FOUND", "Record not found.");

      const record = snap.data() as MedicalRecordDoc;
      if (!notDeleted(record)) {
        throw Problem.notFound("RECORD_NOT_FOUND", "Record not found.");
      }

      const isOwner = record.patientId === req.auth!.sub;
      let grantId: string | null = null;

      if (!isOwner) {
        const resolved = await activeGrantFor(req.auth!.sub, record.patientId);
        const covered = resolved && grantCovers(resolved.grant, req.params.id, record);

        if (!resolved || !covered) {
          // A denial is recorded as deliberately as a read. A burst of these is
          // the clearest fraud signal the system produces, and a patient asking
          // "who looked at my records" is entitled to know who *tried*.
          await logAccess({
            patientId: record.patientId,
            actorId: req.auth!.sub,
            actorName: req.user!.displayName ?? "A provider",
            recordTitle: record.title,
            action: "DENIED",
            purpose: resolved?.grant.purpose ?? null,
            at: Timestamp.now(),
          });
          throw Problem.forbidden("NO_CONSENT", "You do not have access to this record.");
        }

        grantId = resolved.id;
      }

      if (record.scanStatus !== "CLEAN" || !record.objectPath) {
        throw Problem.conflict(
          "RECORD_NOT_READY",
          record.scanStatus === "PENDING"
            ? "This file is still being checked."
            : "This file failed its safety check and cannot be opened."
        );
      }

      await logAccess({
        patientId: record.patientId,
        actorId: req.auth!.sub,
        actorName: isOwner ? "You" : (req.user!.displayName ?? "A provider"),
        recordTitle: record.title,
        action: "VIEW",
        purpose: null,
        at: Timestamp.now(),
      });
      if (grantId) await noteGrantUse(grantId);

      res.json({ url: await signedDownloadUrl(record.objectPath), expiresInSeconds: 300 });
    })
  );

  /**
   * Records a provider may read for one patient.
   *
   * Always the intersection of the patient's records and a live grant; there is
   * no call that returns a patient's records without one.
   */
  r.get(
    "/granted/:patientId",
    requireScope("records:read_granted"),
    handler(async (req, res) => {
      const resolved = await activeGrantFor(req.auth!.sub, req.params.patientId);
      if (!resolved) {
        await logAccess({
          patientId: req.params.patientId,
          actorId: req.auth!.sub,
          actorName: req.user!.displayName ?? "A provider",
          recordTitle: "All records",
          action: "DENIED",
          purpose: null,
          at: Timestamp.now(),
        });
        throw Problem.forbidden("NO_CONSENT", "You do not have access to these records.");
      }

      const snap = await activeRecordsQuery(req.params.patientId).get();
      const visible = snap.docs
        .map((d) => ({ id: d.id, r: d.data() as MedicalRecordDoc }))
        .filter(({ r: rec }) => notDeleted(rec))
        .filter(({ id, r: rec }) => grantCovers(resolved.grant, id, rec));

      await logAccess({
        patientId: req.params.patientId,
        actorId: req.auth!.sub,
        actorName: req.user!.displayName ?? "A provider",
        recordTitle: `${visible.length} record(s)`,
        action: "VIEW_METADATA",
        purpose: resolved.grant.purpose,
        at: Timestamp.now(),
      });
      await noteGrantUse(resolved.id);

      res.json(visible.map(({ id, r: rec }) => recordJson(id, rec)));
    })
  );

  /**
   * Deletes one of the caller's own records.
   *
   * The object goes immediately; the metadata is tombstoned rather than removed
   * so the access log keeps referring to something real. A log entry pointing at
   * a record that no longer exists is not an audit trail.
   */
  r.delete(
    "/:id",
    requireScope("records:write_own"),
    handler(async (req, res) => {
      const ref = db().collection(C.records).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("RECORD_NOT_FOUND", "Record not found.");

      const record = snap.data() as MedicalRecordDoc;
      if (record.patientId !== req.auth!.sub) {
        throw Problem.forbidden("NOT_YOUR_RECORD", "You can only delete your own records.");
      }

      await deleteObject(record.objectPath ?? quarantinePath("records", record.patientId, req.params.id));
      await deleteObject(cleanPath("records", record.patientId, req.params.id));
      await ref.update({ deletedAt: Timestamp.now(), objectPath: null });

      res.json({ ok: true });
    })
  );

  return r;
}

/** Exported for the storage trigger, which writes the same states. */
export const SCAN_STATES: ScanStatus[] = ["PENDING", "CLEAN", "INFECTED", "FAILED"];
