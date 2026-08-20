import { createHash } from "crypto";
import { Router } from "express";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import { requireAuth, requireScope } from "../auth/middleware";
import {
  C,
  db,
  type CredentialDoc,
  type CredentialKind,
  type CredentialReviewStatus,
  type ProviderVerificationDoc,
} from "../db";
import { handler, Problem } from "../errors";
import { assertAllowedContentType, quarantinePath, signedUploadUrl } from "../storage";
import {
  generateRecoveryCodes,
  generateSecret,
  otpauthUri,
  verifyTotp,
} from "./totp";

/**
 * Provider credential submission.
 *
 * Three things must be true before a provider may submit for review, and the
 * gate is enforced here rather than in the UI: every document present, a
 * registration number recorded, and MFA enrolled.
 *
 * MFA is part of the gate deliberately. An approved provider can read patient
 * records and issue prescriptions, so the account has to be hard to take over
 * *before* it gains those powers, not after.
 *
 * Note what is absent: there is no Aadhaar credential kind, and no code path
 * stores an Aadhaar number or image. Identity is proven through DigiLocker, from
 * which only name, date of birth and the last four digits are retained —
 * anything more is a serious liability under the Aadhaar Act.
 */

const KINDS: CredentialKind[] = [
  "DEGREE_CERTIFICATE",
  "MEDICAL_REGISTRATION",
  "IDENTITY_PROOF",
  "HOSPITAL_AFFILIATION",
];

const MAX_CREDENTIAL_BYTES = 15 * 1024 * 1024;

/**
 * NMC / State Medical Council registration numbers.
 *
 * Councils format these inconsistently, so this checks shape rather than
 * validity — the real check is a human looking it up on the council register,
 * which no API here can do.
 */
const REGISTRATION_SHAPE = /^[A-Za-z0-9][A-Za-z0-9/-]{3,29}$/;

function credentialJson(kind: CredentialKind, c: CredentialDoc | undefined) {
  return {
    kind,
    status: c?.status ?? "NOT_SUBMITTED",
    fileName: c?.fileName ?? null,
    uploadedAt: c?.uploadedAt ? c.uploadedAt.toDate().toISOString() : null,
    reasonCode: c?.reasonCode ?? null,
    reviewerNote: c?.reviewerNote ?? null,
  };
}

async function checklistFor(userId: string) {
  const [docsSnap, verificationSnap] = await Promise.all([
    db().collection(C.credentials).where("userId", "==", userId).get(),
    db().collection(C.providerVerifications).doc(userId).get(),
  ]);

  const byKind = new Map<CredentialKind, CredentialDoc>();
  for (const d of docsSnap.docs) {
    const doc = d.data() as CredentialDoc;
    byKind.set(doc.kind, doc);
  }

  const verification = verificationSnap.data() as ProviderVerificationDoc | undefined;

  return {
    credentials: KINDS.map((k) => credentialJson(k, byKind.get(k))),
    registrationNumber: verification?.registrationNumber ?? null,
    // Never leaks the secret or the recovery hashes — only whether it is done.
    mfaEnrolled: verification?.mfaEnrolledAt != null,
  };
}

/** Document id, so re-uploading a kind replaces it rather than accumulating. */
function credentialId(userId: string, kind: CredentialKind): string {
  return `${userId}__${kind}`;
}

export function credentialRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  r.get(
    "/",
    requireScope("credentials:submit"),
    handler(async (req, res) => {
      res.json(await checklistFor(req.auth!.sub));
    })
  );

  /**
   * Records a credential document and returns somewhere to put the file.
   *
   * Same three-step upload as medical records, and the same quarantine: a
   * provider's degree certificate is inspected before any reviewer opens it,
   * because a reviewer opening an attacker-supplied file is exactly the attack.
   */
  r.post(
    "/documents",
    requireScope("credentials:submit"),
    handler(async (req, res) => {
      const { kind, fileName, contentType, sizeBytes } = req.body ?? {};

      if (!KINDS.includes(kind)) {
        throw Problem.validation("Unknown document type.", { kind: "invalid" });
      }
      if (kind === "IDENTITY_PROOF") {
        // Identity is DigiLocker-only. Accepting a file here would be accepting
        // a photograph of an ID document, which is the thing this design exists
        // to avoid storing.
        throw Problem.validation(
          "Identity is verified through DigiLocker, not by uploading a document.",
          { kind: "not_uploadable" }
        );
      }

      const declaredType = assertAllowedContentType(contentType);
      const size = Number(sizeBytes);
      if (!Number.isInteger(size) || size <= 0 || size > MAX_CREDENTIAL_BYTES) {
        throw Problem.validation("Files must be smaller than 15 MB.", {
          sizeBytes: "invalid",
        });
      }

      const id = credentialId(req.auth!.sub, kind);
      const doc: CredentialDoc = {
        userId: req.auth!.sub,
        kind,
        // Not SUBMITTED until the file has actually passed inspection.
        status: "PENDING_UPLOAD",
        fileName: typeof fileName === "string" ? fileName : null,
        contentType: declaredType,
        sizeBytes: size,
        objectPath: null,
        uploadedAt: Timestamp.now(),
        reasonCode: null,
        reviewerNote: null,
      };

      await db().collection(C.credentials).doc(id).set(doc);

      const upload = await signedUploadUrl(
        quarantinePath("credentials", req.auth!.sub, id),
        declaredType
      );

      res.status(201).json({
        checklist: await checklistFor(req.auth!.sub),
        upload: {
          url: upload.url,
          method: "PUT",
          expiresAt: upload.expiresAt,
          headers: { "Content-Type": declaredType },
        },
      });
    })
  );

  /**
   * DigiLocker identity verification.
   *
   * **Stubbed.** A real integration is an OAuth flow against MeitY's DigiLocker
   * partner API, which needs a registered client and a signed agreement — an
   * account, not code. What is real here is the *shape* of the result: only the
   * minimal verified fields are retained, and no document image ever is.
   *
   * It is left obviously unimplemented rather than faked convincingly, because
   * an identity check that silently passes everyone is worse than none.
   */
  r.post(
    "/identity/digilocker",
    requireScope("credentials:submit"),
    handler(async (_req, _res) => {
      throw Problem.internal(
        "DigiLocker verification is not connected yet. Your reviewer will " +
          "verify your identity manually for now."
      );
    })
  );

  r.put(
    "/registration-number",
    requireScope("credentials:submit"),
    handler(async (req, res) => {
      const { registrationNumber } = req.body ?? {};
      if (
        typeof registrationNumber !== "string" ||
        !REGISTRATION_SHAPE.test(registrationNumber.trim())
      ) {
        throw Problem.validation("Enter your council registration number.", {
          registrationNumber: "invalid",
        });
      }

      const number = registrationNumber.trim().toUpperCase();

      // One account per registration number. Two providers sharing one is
      // either a data-entry error or someone practising under another doctor's
      // credentials, and both need a human to look.
      const clash = await db()
        .collection(C.providerVerifications)
        .where("registrationNumber", "==", number)
        .limit(2)
        .get();

      if (clash.docs.some((d) => d.id !== req.auth!.sub)) {
        throw Problem.conflict(
          "REGISTRATION_IN_USE",
          "An account already exists for that registration number."
        );
      }

      await db()
        .collection(C.providerVerifications)
        .doc(req.auth!.sub)
        .set({ registrationNumber: number, updatedAt: Timestamp.now() }, { merge: true });

      res.json(await checklistFor(req.auth!.sub));
    })
  );

  /**
   * Begins TOTP enrolment.
   *
   * The secret is returned exactly once, here, and stored unconfirmed. It does
   * not count as enrolment until a code proves the provider actually scanned it
   * — otherwise a provider could be locked out by a secret they never captured.
   */
  r.post(
    "/mfa/begin",
    requireScope("credentials:submit"),
    handler(async (req, res) => {
      const ref = db().collection(C.providerVerifications).doc(req.auth!.sub);
      const existing = (await ref.get()).data() as ProviderVerificationDoc | undefined;

      if (existing?.mfaEnrolledAt) {
        throw Problem.conflict(
          "MFA_ALREADY_ENROLLED",
          "Two-factor authentication is already set up."
        );
      }

      const totpSecret = generateSecret();
      await ref.set(
        { mfaSecret: totpSecret, mfaEnrolledAt: null, updatedAt: Timestamp.now() },
        { merge: true }
      );

      const account = req.user!.email ?? req.user!.phone ?? req.auth!.sub;
      res.json({ secret: totpSecret, otpauthUri: otpauthUri(totpSecret, account) });
    })
  );

  r.post(
    "/mfa/confirm",
    requireScope("credentials:submit"),
    handler(async (req, res) => {
      const { code } = req.body ?? {};
      const ref = db().collection(C.providerVerifications).doc(req.auth!.sub);
      const existing = (await ref.get()).data() as ProviderVerificationDoc | undefined;

      if (!existing?.mfaSecret) {
        throw Problem.conflict("MFA_NOT_STARTED", "Start two-factor setup first.");
      }
      if (typeof code !== "string" || !verifyTotp(existing.mfaSecret, code)) {
        throw Problem.validation("That code is not right. Try the current one.", {
          code: "invalid",
        });
      }

      // Returned once and stored only as hashes — a database dump must not be a
      // set of live second factors.
      const recoveryCodes = generateRecoveryCodes();
      await ref.set(
        {
          mfaEnrolledAt: Timestamp.now(),
          recoveryCodeHashes: recoveryCodes.map((c) =>
            createHash("sha256").update(c).digest("hex")
          ),
          updatedAt: Timestamp.now(),
        },
        { merge: true }
      );

      res.json({ recoveryCodes });
    })
  );

  /**
   * Submits for supervisor review.
   *
   * Re-derives the gate from stored state rather than trusting a client that
   * believes it is complete, and a rejected document counts as not provided.
   */
  r.post(
    "/submit",
    requireScope("credentials:submit"),
    handler(async (req, res) => {
      const checklist = await checklistFor(req.auth!.sub);

      const missing = checklist.credentials
        .filter((c) => c.status !== "SUBMITTED" && c.status !== "ACCEPTED")
        .map((c) => c.kind);

      const problems: Record<string, string> = {};
      for (const kind of missing) problems[kind] = "missing";
      if (!checklist.registrationNumber) problems.registrationNumber = "missing";
      if (!checklist.mfaEnrolled) problems.mfa = "missing";

      if (Object.keys(problems).length > 0) {
        throw Problem.validation(
          "Some steps are not finished yet.",
          problems
        );
      }

      await db().collection(C.users).doc(req.auth!.sub).update({
        providerStatus: "SUBMITTED",
        // The provider's own token still says DRAFT; bumping this makes the
        // next request refresh into the new status.
        permissionVersion: FieldValue.increment(1),
        updatedAt: Timestamp.now(),
      });

      logger.info("Credentials submitted for review", { userId: req.auth!.sub });
      res.json(await checklistFor(req.auth!.sub));
    })
  );

  return r;
}

/** Shared with the admin review routes, which write the same states. */
export const REVIEW_STATES: CredentialReviewStatus[] = [
  "NOT_SUBMITTED",
  "PENDING_UPLOAD",
  "SUBMITTED",
  "UNDER_REVIEW",
  "ACCEPTED",
  "REJECTED",
];

export { checklistFor, KINDS as CREDENTIAL_KINDS, credentialId };
