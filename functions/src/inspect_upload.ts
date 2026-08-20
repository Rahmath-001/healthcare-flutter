import { Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onObjectFinalized } from "firebase-functions/v2/storage";

import {
  detectContentType,
  scanForMalware,
  stripMetadata,
} from "./api/content_inspection";
import { C, db, type CredentialDoc, type MedicalRecordDoc } from "./api/db";
import {
  CLEAN_PREFIX,
  QUARANTINE_PREFIX,
  deleteObject,
  downloadObject,
  uploadObject,
} from "./api/storage";

/**
 * Promotes an uploaded file out of quarantine, or rejects it.
 *
 * Runs on object finalisation rather than being called by the API, because the
 * client uploads straight to Cloud Storage — the API never sees the bytes and
 * so cannot be the thing that inspects them. This is the only code that can
 * move an object into the readable prefix, which is what makes "unreadable
 * until cleared" a property of the system rather than a convention.
 *
 * Failure is closed. Any error leaves the record non-CLEAN and the object in
 * quarantine, so a crash here means a file nobody can open, never a file nobody
 * checked.
 */
export const inspectUpload = onObjectFinalized(
  {
    region: "asia-south1",
    // 25 MB objects are read into memory, rewritten and written back.
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (event) => {
    const objectPath = event.data.name;
    if (!objectPath?.startsWith(`${QUARANTINE_PREFIX}/`)) return;

    // quarantine/<kind>/<ownerId>/<id>
    const [, kind, ownerId, id] = objectPath.split("/");
    if (!kind || !ownerId || !id) {
      logger.error("Unparseable quarantine path", { objectPath });
      return;
    }

    // Records and provider credentials share this pipeline. They differ only in
    // which collection carries the metadata and what "cleared" is called there.
    if (kind !== "records" && kind !== "credentials") return;

    const isRecord = kind === "records";
    const ref = db()
      .collection(isRecord ? C.records : C.credentials)
      .doc(id);
    const snap = await ref.get();
    if (!snap.exists) {
      // An object with no metadata is an orphan — most likely a record deleted
      // between the signed URL being issued and the upload finishing.
      logger.warn("Upload with no metadata document; discarding", { objectPath });
      await deleteObject(objectPath);
      return;
    }

    const meta = snap.data() as MedicalRecordDoc | CredentialDoc;
    const metaOwner = isRecord
      ? (meta as MedicalRecordDoc).patientId
      : (meta as CredentialDoc).userId;

    if (metaOwner !== ownerId) {
      // The path is derived server-side from the authenticated caller, so this
      // should be unreachable. If it ever fires, something is very wrong.
      logger.error("Owner mismatch on upload", { objectPath, metaOwner });
      await reject(ref, objectPath, "Ownership could not be verified.", isRecord);
      return;
    }

    try {
      const data = await downloadObject(objectPath);

      // The real type, from the bytes. A Content-Type header is a claim, and a
      // .pdf that is really HTML will happily render as a script in a browser.
      const detected = detectContentType(data);
      if (!detected) {
        await reject(ref, objectPath, "The file format is not one we accept.", isRecord);
        return;
      }
      if (detected !== meta.contentType) {
        await reject(
          ref,
          objectPath,
          "The file is not the kind of file it claimed to be.",
          isRecord
        );
        return;
      }

      const { verdict, scanner } = await scanForMalware(data);
      if (verdict === "infected") {
        await reject(ref, objectPath, "The file failed a virus check.", isRecord);
        return;
      }

      // GPS coordinates, device serial and capture time live in EXIF. None of
      // it is clinical, all of it is personal data, and it goes before anyone
      // else can read the file.
      const { data: cleaned, metadataStripped } = stripMetadata(data, detected);

      const destination = `${CLEAN_PREFIX}/${kind}/${ownerId}/${id}`;
      await uploadObject(destination, cleaned, detected);
      await deleteObject(objectPath);

      await ref.update({
        // A record is "clean"; a credential is "submitted" and awaiting a
        // reviewer. Same gate, different vocabulary.
        ...(isRecord
          ? { scanStatus: "CLEAN", metadataStripped, scanner, rejectionReason: null }
          : { status: "SUBMITTED", reasonCode: null, reviewerNote: null }),
        objectPath: destination,
        contentType: detected,
        sizeBytes: cleaned.length,
      });

      logger.info("Upload cleared", { id, kind, metadataStripped });
    } catch (err) {
      logger.error("Inspection failed", { objectPath, err });
      // FAILED, not INFECTED: the file was never shown to be harmful, only
      // never shown to be safe. The user is told to try again.
      await ref.update(
        isRecord
          ? {
              scanStatus: "FAILED",
              rejectionReason:
                "We could not check this file. Please try uploading it again.",
            }
          : {
              status: "NOT_SUBMITTED",
              reviewerNote:
                "We could not check this file. Please try uploading it again.",
            }
      );
    }
  }
);

async function reject(
  ref: FirebaseFirestore.DocumentReference,
  objectPath: string,
  reason: string,
  isRecord: boolean
): Promise<void> {
  await deleteObject(objectPath);
  await ref.update({
    ...(isRecord
      ? { scanStatus: "INFECTED", rejectionReason: reason }
      : { status: "NOT_SUBMITTED", reviewerNote: reason }),
    objectPath: null,
    updatedAt: Timestamp.now(),
  });
  logger.warn("Upload rejected", { objectPath, reason });
}
