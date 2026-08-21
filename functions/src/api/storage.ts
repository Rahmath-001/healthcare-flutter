import { getStorage } from "firebase-admin/storage";

import { Problem } from "./errors";

/**
 * Object storage for clinical documents and provider credentials.
 *
 * Bytes never pass through this API. The client uploads straight to Cloud
 * Storage with a short-lived signed URL and downloads the same way, because a
 * Cloud Function is a poor file server: it is billed for the bandwidth twice,
 * capped at 32 MB per request, and holding a 25 MB buffer in a 512 MiB instance
 * to hand it onward is pure waste. What the API keeps is the part that actually
 * needs judgement — who may upload, who may download, and whether the file has
 * been cleared.
 *
 * Uploads land in a **quarantine** prefix that nothing can read. A storage
 * trigger inspects them and either promotes them to the readable prefix or
 * marks them rejected. Until that happens `scanStatus` is PENDING and every
 * download path refuses, which is why `MedicalRecord.isReadable` exists on the
 * client.
 */

/** Objects here are unreadable by any download path. */
export const QUARANTINE_PREFIX = "quarantine";

/** Objects here have passed inspection. */
export const CLEAN_PREFIX = "clean";

/**
 * Signed URLs are minted per request and die quickly.
 *
 * Fifteen minutes is long enough for a 25 MB upload on a poor mobile connection
 * and short enough that a URL leaked through a screenshot, a proxy log or a
 * chat message is worthless by the time anyone finds it.
 */
const UPLOAD_URL_TTL_MS = 15 * 60 * 1000;

/** Downloads are one-shot and immediate; they need far less room. */
const DOWNLOAD_URL_TTL_MS = 5 * 60 * 1000;

export const ALLOWED_CONTENT_TYPES = [
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/heic",
] as const;

export type AllowedContentType = (typeof ALLOWED_CONTENT_TYPES)[number];

export function assertAllowedContentType(value: unknown): AllowedContentType {
  if (typeof value !== "string" || !ALLOWED_CONTENT_TYPES.includes(value as AllowedContentType)) {
    throw Problem.validation("Only PDF, JPEG, PNG and HEIC files can be uploaded.", {
      contentType: "unsupported",
    });
  }
  return value as AllowedContentType;
}

function bucket() {
  return getStorage().bucket();
}

export function quarantinePath(kind: string, ownerId: string, id: string): string {
  return `${QUARANTINE_PREFIX}/${kind}/${ownerId}/${id}`;
}

export function cleanPath(kind: string, ownerId: string, id: string): string {
  return `${CLEAN_PREFIX}/${kind}/${ownerId}/${id}`;
}

/**
 * A URL the client may PUT exactly one object to.
 *
 * `contentType` is bound into the signature, so the upload cannot claim to be
 * something other than what was authorised. That is a convenience, not a
 * control — the trigger re-derives the real type from the file's magic bytes,
 * because a Content-Type header is only ever a claim.
 */
export async function signedUploadUrl(
  objectPath: string,
  contentType: AllowedContentType
): Promise<{ url: string; expiresAt: string }> {
  const expires = Date.now() + UPLOAD_URL_TTL_MS;
  const [url] = await bucket().file(objectPath).getSignedUrl({
    version: "v4",
    action: "write",
    expires,
    contentType,
  });
  return { url, expiresAt: new Date(expires).toISOString() };
}

export async function signedDownloadUrl(objectPath: string): Promise<string> {
  const [url] = await bucket().file(objectPath).getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + DOWNLOAD_URL_TTL_MS,
  });
  return url;
}

export async function objectExists(objectPath: string): Promise<boolean> {
  const [exists] = await bucket().file(objectPath).exists();
  return exists;
}

export async function deleteObject(objectPath: string): Promise<void> {
  // `ignoreNotFound` so deleting a record whose upload never completed is not
  // an error — the metadata document is the source of truth, not the object.
  await bucket().file(objectPath).delete({ ignoreNotFound: true });
}

export async function downloadObject(objectPath: string): Promise<Buffer> {
  const [buffer] = await bucket().file(objectPath).download();
  return buffer;
}

/**
 * Where the immutable, server-generated prescription PDFs live.
 *
 * Outside both `quarantine/` and `clean/`: those prefixes are for bytes a
 * *user* supplied and an inspector had to clear. These are produced by this
 * API from data it already validated, so there is nothing to scan — and giving
 * them their own prefix is what lets a bucket-level retention policy be
 * applied to prescriptions without also freezing every uploaded lab report.
 */
export const PRESCRIPTION_PREFIX = "prescriptions";

export function prescriptionPdfPath(prescriptionId: string): string {
  return `${PRESCRIPTION_PREFIX}/${prescriptionId}.pdf`;
}

/**
 * Writes an object and then makes it undeletable and unoverwritable.
 *
 * A prescription is a legal document. The client used to render its own PDF,
 * which meant the only artifact was one the client could alter — this is the
 * fix. The temporary hold is what makes it write-once: while it is set, Cloud
 * Storage refuses both delete and overwrite, including from the service account
 * that wrote it.
 *
 * **A hold is not the whole control.** It can be released by anyone holding
 * `storage.objects.update`. The stronger form is a bucket-level retention
 * policy with a *locked* duration, which nobody — including the project owner —
 * can shorten or remove. That is a one-way bucket configuration rather than
 * something an API should do to itself on first write, so it is an operations
 * task; see docs/SECURITY_AUDIT.md. This gets the per-object guarantee that
 * code can honestly provide, and does not pretend to more.
 */
export async function uploadImmutableObject(
  objectPath: string,
  data: Buffer,
  contentType: string
): Promise<void> {
  const file = bucket().file(objectPath);

  // A hold on an existing object makes `save` fail, which is the point: a
  // second issue of the same prescription id must not silently replace the
  // first. Surfacing it as a conflict is more useful than a 500.
  const [exists] = await file.exists();
  if (exists) {
    throw Problem.conflict(
      "PRESCRIPTION_PDF_EXISTS",
      "This prescription document has already been stored."
    );
  }

  await file.save(data, { contentType, resumable: false });
  await file.setMetadata({ temporaryHold: true });
}

export async function uploadObject(
  objectPath: string,
  data: Buffer,
  contentType: string
): Promise<void> {
  await bucket().file(objectPath).save(data, {
    contentType,
    // Public access is never appropriate here; every read goes through a signed
    // URL minted after an entitlement check.
    resumable: false,
  });
}
