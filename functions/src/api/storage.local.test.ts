import { afterEach, describe, expect, it } from "vitest";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  deleteObject,
  downloadObject,
  hasValidLocalDocumentCapability,
  signedDownloadUrl,
  signedUploadUrl,
  uploadObject,
  usingLocalDocumentStorage,
} from "./storage";

const keys = [
  "LOCAL_DOCUMENT_STORAGE_DIR",
  "LOCAL_DOCUMENT_STORAGE_BASE_URL",
  "LOCAL_DOCUMENT_STORAGE_SECRET",
] as const;
const before = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
let directory: string | undefined;

afterEach(async () => {
  if (directory) await fs.rm(directory, { recursive: true, force: true });
  directory = undefined;
  for (const key of keys) {
    const value = before[key];
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

describe("local document storage", () => {
  it("uses expiring signed capabilities and confines files to its own directory", async () => {
    directory = await fs.mkdtemp(path.join(os.tmpdir(), "midoctor-documents-"));
    process.env.LOCAL_DOCUMENT_STORAGE_DIR = directory;
    process.env.LOCAL_DOCUMENT_STORAGE_BASE_URL = "http://10.0.2.2:5002";
    process.env.LOCAL_DOCUMENT_STORAGE_SECRET = "test-secret";

    expect(usingLocalDocumentStorage()).toBe(true);
    const objectPath = "quarantine/records/user_1/record_1";
    const upload = await signedUploadUrl(objectPath, "application/pdf");
    const uploadUrl = new URL(upload.url);
    expect(
      hasValidLocalDocumentCapability(
        "PUT",
        uploadUrl.searchParams.get("path"),
        uploadUrl.searchParams.get("expires"),
        uploadUrl.searchParams.get("signature"),
        uploadUrl.searchParams.get("contentType") ?? ""
      )
    ).toBe(true);
    expect(
      hasValidLocalDocumentCapability(
        "PUT",
        "quarantine/records/user_1/other_record",
        uploadUrl.searchParams.get("expires"),
        uploadUrl.searchParams.get("signature"),
        "application/pdf"
      )
    ).toBe(false);

    const bytes = Buffer.from("%PDF-1.7 local document", "binary");
    await uploadObject(objectPath, bytes, "application/pdf");
    expect(await downloadObject(objectPath)).toEqual(bytes);

    const download = await signedDownloadUrl(objectPath);
    const downloadUrl = new URL(download);
    expect(
      hasValidLocalDocumentCapability(
        "GET",
        downloadUrl.searchParams.get("path"),
        downloadUrl.searchParams.get("expires"),
        downloadUrl.searchParams.get("signature")
      )
    ).toBe(true);

    await deleteObject(objectPath);
    await expect(downloadObject(objectPath)).rejects.toMatchObject({ code: "ENOENT" });
  });
});
