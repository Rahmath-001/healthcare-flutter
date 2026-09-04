import { onObjectFinalized } from "firebase-functions/v2/storage";

import { inspectUploadedObject } from "./upload_inspection";

/**
 * Production Cloud Storage entry point. The inspection itself lives separately
 * so the local development object adapter runs exactly the same pipeline
 * without constructing a Cloud Functions storage trigger.
 */
export const inspectUpload = onObjectFinalized(
  {
    region: "asia-south1",
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (event) => inspectUploadedObject(event.data.name)
);
