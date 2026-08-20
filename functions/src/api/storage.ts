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
