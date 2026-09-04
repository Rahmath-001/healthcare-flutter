import { Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

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
 * Shared inspection pipeline for Cloud Storage and the local development
 * object store. The caller receives no success shortcut: both paths perform
 * ownership, file-type and metadata checks before a document becomes readable.
 */
export async function inspectUploadedObject(objectPath: string | undefined): Promise<void> {
  if (!objectPath?.startsWith(`${QUARANTINE_PREFIX}/`)) return;

  const [, kind, ownerId, id] = objectPath.split("/");
  if (!kind || !ownerId || !id) {
    logger.error("Unparseable quarantine path", { objectPath });
    return;
  }
  if (kind !== "records" && kind !== "credentials") return;

  const isRecord = kind === "records";
  const ref = db().collection(isRecord ? C.records : C.credentials).doc(id);
  const snap = await ref.get();
  if (!snap.exists) {
    logger.warn("Upload with no metadata document; discarding", { objectPath });
    await deleteObject(objectPath);
    return;
  }

  const meta = snap.data() as MedicalRecordDoc | CredentialDoc;
  const metaOwner = isRecord
    ? (meta as MedicalRecordDoc).patientId
    : (meta as CredentialDoc).userId;
  if (metaOwner !== ownerId) {
    logger.error("Owner mismatch on upload", { objectPath, metaOwner });
    await reject(ref, objectPath, "Ownership could not be verified.", isRecord);
    return;
  }

  try {
    const data = await downloadObject(objectPath);
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

    const { data: cleaned, metadataStripped } = stripMetadata(data, detected);
    const destination = `${CLEAN_PREFIX}/${kind}/${ownerId}/${id}`;
    await uploadObject(destination, cleaned, detected);
    await deleteObject(objectPath);

    await ref.update({
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
    await ref.update(
      isRecord
        ? {
            scanStatus: "FAILED",
            rejectionReason: "We could not check this file. Please try uploading it again.",
          }
        : {
            status: "NOT_SUBMITTED",
            reviewerNote: "We could not check this file. Please try uploading it again.",
          }
    );
  }
}

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
