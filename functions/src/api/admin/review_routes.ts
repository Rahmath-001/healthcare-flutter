import { Router } from "express";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import { requireAuth, requireScope } from "../auth/middleware";
import {
  C,
  db,
  type CredentialDoc,
  type ProviderVerificationDoc,
  type RatingDoc,
  type RejectionReasonCode,
  type SupportTicketDoc,
  type TicketStatus,
  type UserDoc,
} from "../db";
import { handler, Problem } from "../errors";
import { signedDownloadUrl } from "../storage";

/**
 * The reviewer's side of the product.
 *
 * These are the endpoints the web console calls, and none of them has a mobile
 * equivalent: supervisor and admin roles are routed to `/blocked` in the app
 * deliberately, because reviewing a degree certificate on a phone is not a
 * thing anyone should do.
 *
 * Everything here is scope-gated, and every decision is logged with who made
 * it. A verification decision with no attributable author is not a decision, it
 * is an event.
 */

const REJECTION_CODES: RejectionReasonCode[] = [
  "DOC_ILLEGIBLE",
  "DOC_EXPIRED",
  "NAME_MISMATCH",
  "NMC_NOT_FOUND",
  "NMC_SUSPENDED",
  "AFFILIATION_UNVERIFIABLE",
  "SUSPECTED_FORGERY",
  "DUPLICATE_ACCOUNT",
  "INCOMPLETE_SUBMISSION",
];

export function reviewRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  // ---------------------------------------------------------------- providers

  /**
   * Everything a reviewer needs about one applicant, in one call.
   *
   * Deliberately assembled server-side rather than left to the console to
   * stitch together from four endpoints: a reviewer looking at a partially
   * loaded page is a reviewer approving on incomplete information.
   */
  r.get(
    "/providers/:userId",
    requireScope("provider:review"),
    handler(async (req, res) => {
      const userId = req.params.userId;

      const [userSnap, credsSnap, verificationSnap] = await Promise.all([
        db().collection(C.users).doc(userId).get(),
        db().collection(C.credentials).where("userId", "==", userId).get(),
        db().collection(C.providerVerifications).doc(userId).get(),
      ]);

      if (!userSnap.exists) throw Problem.notFound("USER_NOT_FOUND", "No such account.");
      const user = userSnap.data() as UserDoc;
      const verification = verificationSnap.data() as ProviderVerificationDoc | undefined;

      res.json({
        userId,
        displayName: user.displayName ?? null,
        email: user.email ?? null,
        phone: user.phone ?? null,
        providerStatus: user.providerStatus,
        accountStatus: user.status,
        registrationNumber: verification?.registrationNumber ?? null,
        mfaEnrolled: verification?.mfaEnrolledAt != null,
        identityVerifiedAt: verification?.identityVerifiedAt
          ? verification.identityVerifiedAt.toDate().toISOString()
          : null,
        documents: credsSnap.docs.map((d) => {
          const c = d.data() as CredentialDoc;
          return {
            id: d.id,
            kind: c.kind,
            status: c.status,
            fileName: c.fileName ?? null,
            contentType: c.contentType,
            sizeBytes: c.sizeBytes,
            uploadedAt: c.uploadedAt.toDate().toISOString(),
            reasonCode: c.reasonCode ?? null,
            reviewerNote: c.reviewerNote ?? null,
            reviewedBy: c.reviewedBy ?? null,
            // Whether a file exists to look at. The URL itself is minted by a
            // separate call, so opening the page does not mint one per document.
            hasFile: c.objectPath != null,
          };
        }),
      });
    })
  );

  /**
   * A short-lived URL for a reviewer to open one credential document.
   *
   * Separate from the detail call so a URL is minted only when someone actually
   * opens a document, and each one is logged. A page load is not a disclosure;
   * opening a doctor's degree certificate is.
   */
  r.get(
    "/credentials/:id/download",
    requireScope("provider:review"),
    handler(async (req, res) => {
      const snap = await db().collection(C.credentials).doc(req.params.id).get();
      if (!snap.exists) throw Problem.notFound("DOCUMENT_NOT_FOUND", "Not found.");

      const credential = snap.data() as CredentialDoc;
      if (!credential.objectPath) {
        throw Problem.conflict(
          "DOCUMENT_NOT_READY",
          "This document has not finished uploading, or failed its check."
        );
      }

      logger.info("Credential document opened", {
        credentialId: req.params.id,
        subject: credential.userId,
        actor: req.auth!.sub,
      });

      res.json({ url: await signedDownloadUrl(credential.objectPath), expiresInSeconds: 300 });
    })
  );

  /**
   * Accepts or rejects a single document.
   *
   * Per-document rather than per-application, because "your submission was
   * rejected" is useless to a provider and "your affiliation letter was not
   * readable" is actionable. A rejected document counts as not provided, so the
   * submit gate reopens on its own.
   */
  r.post(
    "/credentials/:id/decision",
    requireScope("provider:approve"),
    handler(async (req, res) => {
      const { decision, reasonCode, note } = req.body ?? {};
      if (decision !== "ACCEPT" && decision !== "REJECT") {
        throw Problem.validation("Decision must be ACCEPT or REJECT.", {
          decision: "invalid",
        });
      }
      if (decision === "REJECT" && !REJECTION_CODES.includes(reasonCode)) {
        // A structured code, not free text: it can be shown in the provider's
        // own language and counted for fraud analysis.
        throw Problem.validation("Choose a reason for rejection.", {
          reasonCode: "required",
        });
      }

      const ref = db().collection(C.credentials).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("DOCUMENT_NOT_FOUND", "Not found.");

      await ref.update({
        status: decision === "ACCEPT" ? "ACCEPTED" : "REJECTED",
        reasonCode: decision === "REJECT" ? reasonCode : null,
        reviewerNote: typeof note === "string" && note.trim() ? note.trim() : null,
        reviewedBy: req.auth!.sub,
        reviewedAt: Timestamp.now(),
      });

      logger.info("Credential decision", {
        credentialId: req.params.id,
        actor: req.auth!.sub,
        decision,
      });

      res.json({ id: req.params.id, decision });
    })
  );

  /** Moves an application into review, so two reviewers do not duplicate work. */
  r.post(
    "/providers/:userId/claim",
    requireScope("provider:review"),
    handler(async (req, res) => {
      const ref = db().collection(C.users).doc(req.params.userId);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("USER_NOT_FOUND", "No such account.");

      const user = snap.data() as UserDoc;
      if (user.providerStatus !== "SUBMITTED") {
        throw Problem.conflict(
          "NOT_AWAITING_REVIEW",
          "This application is not waiting to be picked up."
        );
      }

      await ref.update({
        providerStatus: "UNDER_REVIEW",
        reviewClaimedBy: req.auth!.sub,
        permissionVersion: FieldValue.increment(1),
        updatedAt: Timestamp.now(),
      });

      res.json({ userId: req.params.userId, providerStatus: "UNDER_REVIEW" });
    })
  );

  // ----------------------------------------------------------------- ratings

  /** Ratings awaiting moderation. Nothing counts towards a doctor until it passes. */
  r.get(
    "/ratings/pending",
    requireScope("provider:review"),
    handler(async (_req, res) => {
      const snap = await db()
        .collection(C.ratings)
        .where("status", "==", "PENDING_MODERATION")
        .limit(100)
        .get();

      const items = snap.docs
        .map((d) => ({ id: d.id, r: d.data() as RatingDoc }))
        .sort((a, b) => a.r.createdAt.toMillis() - b.r.createdAt.toMillis());

      res.json(
        items.map(({ id, r: rating }) => ({
          id,
          doctorId: rating.doctorId,
          doctorName: rating.doctorName,
          stars: rating.stars,
          comment: rating.comment ?? null,
          createdAt: rating.createdAt.toDate().toISOString(),
          editedAt: rating.editedAt ? rating.editedAt.toDate().toISOString() : null,
        }))
      );
    })
  );

  // ----------------------------------------------------------------- support

  /**
   * The support queue.
   *
   * Agents see subject, category and the thread. There is no endpoint here that
   * returns a user's medical records, appointments or prescriptions: support
   * staff hold no consent grant, and the fastest way to leak a patient's
   * history is to build a "context" panel for a helpdesk.
   */
  r.get(
    "/support/tickets",
    requireScope("support:ticket_read"),
    handler(async (req, res) => {
      const status = req.query.status as TicketStatus | undefined;

      let query = db().collection(C.supportTickets).limit(100) as FirebaseFirestore.Query;
      if (status) query = query.where("status", "==", status);

      const snap = await query.get();
      const items = snap.docs
        .map((d) => ({ id: d.id, t: d.data() as SupportTicketDoc }))
        .sort((a, b) => b.t.updatedAt.toMillis() - a.t.updatedAt.toMillis());

      res.json(
        items.map(({ id, t }) => ({
          id,
          reference: t.reference,
          subject: t.subject,
          category: t.category,
          status: t.status,
          createdAt: t.createdAt.toDate().toISOString(),
          updatedAt: t.updatedAt.toDate().toISOString(),
          messageCount: t.messages.length,
          assignedTo: t.assignedTo ?? null,
        }))
      );
    })
  );

  r.get(
    "/support/tickets/:id",
    requireScope("support:ticket_read"),
    handler(async (req, res) => {
      const snap = await db().collection(C.supportTickets).doc(req.params.id).get();
      if (!snap.exists) throw Problem.notFound("TICKET_NOT_FOUND", "Ticket not found.");

      const t = snap.data() as SupportTicketDoc;
      res.json({
        id: req.params.id,
        reference: t.reference,
        subject: t.subject,
        category: t.category,
        status: t.status,
        createdAt: t.createdAt.toDate().toISOString(),
        updatedAt: t.updatedAt.toDate().toISOString(),
        assignedTo: t.assignedTo ?? null,
        messages: t.messages.map((m) => ({
          id: m.id,
          body: m.body,
          authorName: m.authorName,
          fromSupport: m.fromSupport,
          at: m.at.toDate().toISOString(),
        })),
      });
    })
  );

  r.post(
    "/support/tickets/:id/replies",
    requireScope("support:ticket_read"),
    handler(async (req, res) => {
      const body = req.body?.body;
      if (typeof body !== "string" || body.trim().length < 2) {
        throw Problem.validation("Write a reply first.", { body: "required" });
      }

      const ref = db().collection(C.supportTickets).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("TICKET_NOT_FOUND", "Ticket not found.");

      const ticket = snap.data() as SupportTicketDoc;
      const now = Timestamp.now();

      await ref.set(
        {
          ...ticket,
          status: ticket.status === "OPEN" ? "ASSIGNED" : ticket.status,
          assignedTo: ticket.assignedTo ?? req.auth!.sub,
          updatedAt: now,
          messages: [
            ...ticket.messages,
            {
              id: `${now.toMillis()}-${req.auth!.sub}`,
              body: body.trim(),
              authorName: req.user!.displayName ?? "MiDoctor Support",
              fromSupport: true,
              at: now,
            },
          ],
        },
        { merge: true }
      );

      res.status(201).json({ ok: true });
    })
  );

  r.post(
    "/support/tickets/:id/status",
    requireScope("support:ticket_read"),
    handler(async (req, res) => {
      const { status } = req.body ?? {};
      if (!["OPEN", "ASSIGNED", "ESCALATED", "CLOSED"].includes(status)) {
        throw Problem.validation("Unknown status.", { status: "invalid" });
      }
      if (status === "ESCALATED") {
        // L1 can see a ticket; escalating is L2's call.
        if (!req.auth!.scopes.includes("*:*") &&
            !req.auth!.scopes.includes("support:ticket_escalate")) {
          throw Problem.forbidden(
            "SCOPE_REQUIRED",
            "You cannot escalate a ticket."
          );
        }
      }

      await db()
        .collection(C.supportTickets)
        .doc(req.params.id)
        .update({ status, updatedAt: Timestamp.now() });

      res.json({ id: req.params.id, status });
    })
  );

  return r;
}
