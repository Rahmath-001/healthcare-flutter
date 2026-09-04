/*
 * Local REST API for Android testing against the selected Firebase project's
 * hosted Firestore database. This deliberately runs only on the developer's
 * machine; it is not a Cloud Functions deployment.
 */
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { applicationDefault, initializeApp } = require("firebase-admin/app");

const root = __dirname;
const serviceAccount = path.join(root, "service-account.local.json");
const localSecrets = path.join(root, ".secret.local");
const port = Number(process.env.PORT || 5001);

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  process.env.GOOGLE_APPLICATION_CREDENTIALS = serviceAccount;
}

if (!fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS)) {
  throw new Error(
    "Missing service-account.local.json. Keep the Firebase Admin SDK key in functions/service-account.local.json."
  );
}

// The Cloud Functions runtime receives `storageBucket` through FIREBASE_CONFIG,
// but this local server only has Application Default Credentials.  Initialise
// it explicitly so `/v1/records` and `/v1/credentials/documents` can create
// signed URLs against the selected Firebase project's default bucket.  Older
// projects that still use an appspot.com bucket can override the derived value.
const credentialInfo = JSON.parse(
  fs.readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, "utf8")
);
const storageBucket =
  process.env.FIREBASE_STORAGE_BUCKET ||
  `${credentialInfo.project_id}.firebasestorage.app`;

if (fs.existsSync(localSecrets)) {
  for (const line of fs.readFileSync(localSecrets, "utf8").split(/\r?\n/)) {
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2];
  }
}

// Firebase Storage needs Blaze for new projects. For no-cost emulator testing,
// keep test files on this machine while preserving the real Firestore metadata,
// API RBAC and inspection pipeline. This mode is never used by deployed
// Functions; override the base URL for a physical device on the local network.
process.env.LOCAL_DOCUMENT_STORAGE_DIR ||= path.join(root, ".local-documents");
process.env.LOCAL_DOCUMENT_STORAGE_BASE_URL ||=
  `http://10.0.2.2:${port}`;
process.env.LOCAL_DOCUMENT_STORAGE_SECRET ||= crypto.randomBytes(32).toString("base64url");

const { buildApp } = require("./lib/api/app");

initializeApp({ credential: applicationDefault(), storageBucket });

const app = buildApp({
  secret: () => process.env.JWT_SECRET || "local-development-only",
  hmsAccessKey: () => undefined,
  hmsSecret: () => undefined,
});

app.listen(port, "0.0.0.0", () => {
  console.log(`MiDoctor local API listening at http://127.0.0.1:${port}/v1`);
  console.log("Firestore target: hosted Firebase project credentials");
  console.log(`Cloud Storage target: ${storageBucket}`);
  console.log(`Local document storage: ${process.env.LOCAL_DOCUMENT_STORAGE_DIR}`);
});
