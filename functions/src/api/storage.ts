import { getStorage } from "firebase-admin/storage";
import { createHmac, timingSafeEqual } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";

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

/**
 * The local API can use an on-disk object store while Firebase Storage is not
 * available on a Spark project.  It exists exclusively to exercise the real
 * API, Firestore metadata and RBAC flow on a developer machine; Cloud
 * Functions never set these variables, so production keeps using Cloud
 * Storage.  URLs remain short-lived capabilities rather than becoming an
 * unauthenticated file server.
 */
const LOCAL_STORAGE_DIR = "LOCAL_DOCUMENT_STORAGE_DIR";
const LOCAL_STORAGE_BASE_URL = "LOCAL_DOCUMENT_STORAGE_BASE_URL";
const LOCAL_STORAGE_SECRET = "LOCAL_DOCUMENT_STORAGE_SECRET";

function localConfig(): { directory: string; baseUrl: string; secret: string } | null {
  const directory = process.env[LOCAL_STORAGE_DIR];
  const baseUrl = process.env[LOCAL_STORAGE_BASE_URL];
  const secret = process.env[LOCAL_STORAGE_SECRET];
  if (!directory || !baseUrl || !secret) return null;
  return {
    directory: path.resolve(directory),
    baseUrl: baseUrl.replace(/\/$/, ""),
    secret,
  };
}

export function usingLocalDocumentStorage(): boolean {
  return localConfig() !== null;
}

function localFilePath(objectPath: string): string {
  const config = localConfig();
  if (!config) throw new Error("Local document storage is not configured.");
  if (!/^(quarantine|clean|prescriptions)\/[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*$/.test(objectPath)) {
    throw new Error("Invalid local document object path.");
  }
  const target = path.resolve(config.directory, ...objectPath.split("/"));
  if (target !== config.directory && !target.startsWith(`${config.directory}${path.sep}`)) {
    throw new Error("Invalid local document object path.");
  }
  return target;
}

function localSignature(
  method: "PUT" | "GET",
  objectPath: string,
  expires: number,
  contentType = ""
): string {
  const config = localConfig();
  if (!config) throw new Error("Local document storage is not configured.");
  return createHmac("sha256", config.secret)
    .update(`${method}\n${objectPath}\n${expires}\n${contentType}`)
    .digest("base64url");
}

function localCapabilityUrl(
  method: "PUT" | "GET",
  objectPath: string,
  expires: number,
  contentType = ""
): string {
  const config = localConfig();
  if (!config) throw new Error("Local document storage is not configured.");
  const params = new URLSearchParams({
    path: objectPath,
    expires: String(expires),
    signature: localSignature(method, objectPath, expires, contentType),
  });
  if (contentType) params.set("contentType", contentType);
  return `${config.baseUrl}/v1/local-documents/${method === "PUT" ? "upload" : "download"}?${params}`;
}

/** Validates the opaque, short-lived local URL capability. */
export function hasValidLocalDocumentCapability(
  method: "PUT" | "GET",
  objectPath: unknown,
  expires: unknown,
  signature: unknown,
  contentType = ""
): objectPath is string {
  if (
    typeof objectPath !== "string" ||
    typeof expires !== "string" ||
    typeof signature !== "string" ||
    !/^[0-9]+$/.test(expires)
  ) {
    return false;
  }
  const expiresAt = Number(expires);
  if (!Number.isSafeInteger(expiresAt) || expiresAt < Date.now()) return false;
  try {
    // Runs the same strict path validation before calculating the signature.
    localFilePath(objectPath);
    const expected = Buffer.from(localSignature(method, objectPath, expiresAt, contentType));
    const supplied = Buffer.from(signature);
    return supplied.length === expected.length && timingSafeEqual(supplied, expected);
  } catch {
    return false;
  }
}

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
  if (usingLocalDocumentStorage()) {
    return {
      url: localCapabilityUrl("PUT", objectPath, expires, contentType),
      expiresAt: new Date(expires).toISOString(),
    };
  }
  const [url] = await bucket().file(objectPath).getSignedUrl({
    version: "v4",
    action: "write",
    expires,
    contentType,
  });
  return { url, expiresAt: new Date(expires).toISOString() };
}

export async function signedDownloadUrl(objectPath: string): Promise<string> {
  if (usingLocalDocumentStorage()) {
    return localCapabilityUrl("GET", objectPath, Date.now() + DOWNLOAD_URL_TTL_MS);
  }
  const [url] = await bucket().file(objectPath).getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + DOWNLOAD_URL_TTL_MS,
  });
  return url;
}

export async function objectExists(objectPath: string): Promise<boolean> {
  if (usingLocalDocumentStorage()) {
    try {
      await fs.access(localFilePath(objectPath));
      return true;
    } catch {
      return false;
    }
  }
  const [exists] = await bucket().file(objectPath).exists();
  return exists;
}

export async function deleteObject(objectPath: string): Promise<void> {
  if (usingLocalDocumentStorage()) {
    await fs.rm(localFilePath(objectPath), { force: true });
    return;
  }
  // `ignoreNotFound` so deleting a record whose upload never completed is not
  // an error — the metadata document is the source of truth, not the object.
  await bucket().file(objectPath).delete({ ignoreNotFound: true });
}

export async function downloadObject(objectPath: string): Promise<Buffer> {
  if (usingLocalDocumentStorage()) return fs.readFile(localFilePath(objectPath));
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
  if (usingLocalDocumentStorage()) {
    if (await objectExists(objectPath)) {
      throw Problem.conflict(
        "PRESCRIPTION_PDF_EXISTS",
        "This prescription document has already been stored."
      );
    }
    await uploadObject(objectPath, data, contentType);
    return;
  }
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
  if (usingLocalDocumentStorage()) {
    const target = localFilePath(objectPath);
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, data);
    return;
  }
  await bucket().file(objectPath).save(data, {
    contentType,
    // Public access is never appropriate here; every read goes through a signed
    // URL minted after an entitlement check.
    resumable: false,
  });
}
