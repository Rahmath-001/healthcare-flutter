import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";

import { C, type Role } from "./api/db";

/**
 * Assigns a role from a trusted shell. This is the bootstrap.
 *
 * The API deliberately cannot create the first privileged account. Sign-up
 * resolves `requestedRole` to PATIENT or PROVIDER and nothing else, and
 * `POST /v1/admin/users/:id/role` needs `user:set_role`, which only an ADMIN
 * holds. That is a correct design — a client that can ask for SUPERVISOR is a
 * client that can approve its own doctors — but it leaves a chicken-and-egg
 * problem: with no admin, the provider-approval queue can never be worked, and
 * no doctor can ever be approved.
 *
 * This script is the out-of-band answer. It authenticates with Application
 * Default Credentials rather than a token, so running it already requires
 * privileged access to the project. Use it exactly once to create the first
 * ADMIN; after that, use the API, which logs who did what.
 *
 * Usage:
 *   pnpm run grant-role -- --email you@example.com --role ADMIN
 *   pnpm run grant-role -- --uid abc123 --role SUPERVISOR
 *
 * Against the emulator, export FIRESTORE_EMULATOR_HOST and
 * FIREBASE_AUTH_EMULATOR_HOST first.
 */

const ROLES: Role[] = [
  "PATIENT",
  "PROVIDER",
  "SUPERVISOR",
  "SUPPORT_L1",
  "SUPPORT_L2",
  "ADMIN",
  "UNASSIGNED",
];

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

async function main() {
  const role = arg("role") as Role | undefined;
  const uidArg = arg("uid");
  const email = arg("email");

  if (!role || !ROLES.includes(role)) {
    throw new Error(`--role must be one of: ${ROLES.join(", ")}`);
  }
  if (!uidArg && !email) {
    throw new Error("Pass either --uid or --email.");
  }

  initializeApp();
  const db = getFirestore();

  // The uid is the Firebase Auth uid, which is also the `users` document id.
  const uid = uidArg ?? (await getAuth().getUserByEmail(email!)).uid;

  const ref = db.collection(C.users).doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new Error(
      `No users/${uid} document. The account must sign in through the app once ` +
        "before a role can be assigned — that first sign-in is what creates it."
    );
  }

  await ref.update({
    role,
    ...(role === "PROVIDER" ? {} : { providerStatus: "NOT_APPLICABLE" }),
    // Any access token the account is already holding claims the old role.
    // Bumping the version makes the next request fail as TOKEN_STALE, which the
    // client answers by refreshing into the new one.
    permissionVersion: FieldValue.increment(1),
    updatedAt: Timestamp.now(),
  });

  console.log(`users/${uid} is now ${role}.`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e instanceof Error ? e.message : e);
    process.exit(1);
  });
