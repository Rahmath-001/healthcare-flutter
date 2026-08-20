import { randomUUID } from "crypto";
import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { requireAuth, requireScope } from "../auth/middleware";
import { C, db, type SupportTicketDoc, type TicketCategory } from "../db";
import { handler, Problem } from "../errors";

/**
 * Support tickets.
 *
 * Mobile holds `support:ticket_create` and nothing else, so this exposes the
 * caller's own tickets and no queue, no assignment and no other user's data.
 * The agent-facing side is a separate surface for a client that does not exist
 * yet; building half of it here would mean an endpoint whose only protection is
 * that no UI calls it.
 *
 * Nothing here should ever carry clinical detail. The category list is
 * deliberately about the *app* — a booking that failed, a payment, an account
 * problem — and the placeholder copy on the client steers away from symptoms.
 * A support ticket is read by staff who hold no consent grant.
 */

const CATEGORIES: TicketCategory[] = [
  "LOGIN_PROBLEM",
  "BOOKING_PROBLEM",
  "PAYMENT_PROBLEM",
  "RECORDS_PROBLEM",
  "DOCTOR_CONCERN",
  "OTHER",
];

const MAX_BODY = 2000;

/** Human-quotable, unambiguous when read aloud over a phone call. */
function reference(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let out = "";
  for (let i = 0; i < 6; i++) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return `SUP-${out}`;
}

function ticketJson(id: string, t: SupportTicketDoc) {
  return {
    id,
    reference: t.reference,
    subject: t.subject,
    category: t.category,
    status: t.status,
    createdAt: t.createdAt.toDate().toISOString(),
    updatedAt: t.updatedAt.toDate().toISOString(),
    messages: t.messages.map((m) => ({
      id: m.id,
      body: m.body,
      authorName: m.authorName,
      fromSupport: m.fromSupport,
      at: m.at.toDate().toISOString(),
    })),
  };
}

function assertBody(value: unknown): string {
  if (typeof value !== "string" || value.trim().length < 5) {
    throw Problem.validation("Tell us a little more.", { body: "too short" });
  }
  if (value.length > MAX_BODY) {
    throw Problem.validation("That is too long to send.", { body: "too long" });
  }
  return value.trim();
}

export function supportRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  r.get(
    "/",
    handler(async (req, res) => {
      const snap = await db()
        .collection(C.supportTickets)
        .where("userId", "==", req.auth!.sub)
        .get();

      const items = snap.docs
        .map((d) => ({ id: d.id, t: d.data() as SupportTicketDoc }))
        .sort((a, b) => b.t.updatedAt.toMillis() - a.t.updatedAt.toMillis());

      res.json(items.map(({ id, t }) => ticketJson(id, t)));
    })
  );

  r.post(
    "/",
    requireScope("support:ticket_create"),
    handler(async (req, res) => {
      const { subject, category } = req.body ?? {};
      const body = assertBody(req.body?.body);

      if (typeof subject !== "string" || subject.trim().length < 3) {
        throw Problem.validation("Give it a short subject.", { subject: "too short" });
      }
      if (!CATEGORIES.includes(category)) {
        throw Problem.validation("Pick a category.", { category: "invalid" });
      }

      const now = Timestamp.now();
      const id = randomUUID();
      const doc: SupportTicketDoc = {
        userId: req.auth!.sub,
        reference: reference(),
        subject: subject.trim(),
        category,
        status: "OPEN",
        createdAt: now,
        updatedAt: now,
        messages: [
          {
            id: randomUUID(),
            body,
            authorName: req.user!.displayName ?? "You",
            fromSupport: false,
            at: now,
          },
        ],
      };

      await db().collection(C.supportTickets).doc(id).set(doc);
      res.status(201).json(ticketJson(id, doc));
    })
  );

  r.post(
    "/:id/replies",
    requireScope("support:ticket_create"),
    handler(async (req, res) => {
      const body = assertBody(req.body?.body);

      const ref = db().collection(C.supportTickets).doc(req.params.id);
      const snap = await ref.get();
      if (!snap.exists) throw Problem.notFound("TICKET_NOT_FOUND", "Ticket not found.");

      const ticket = snap.data() as SupportTicketDoc;
      if (ticket.userId !== req.auth!.sub) {
        throw Problem.forbidden("NOT_YOUR_TICKET", "That is not your ticket.");
      }
      if (ticket.status === "CLOSED") {
        throw Problem.conflict(
          "TICKET_CLOSED",
          "This ticket is closed. Please open a new one."
        );
      }

      const now = Timestamp.now();
      const message = {
        id: randomUUID(),
        body,
        authorName: req.user!.displayName ?? "You",
        fromSupport: false,
        at: now,
      };

      const updated: SupportTicketDoc = {
        ...ticket,
        // A reply from the user reopens a closed-off ticket: they are telling
        // us it was not resolved. Only ESCALATED is left alone, because that is
        // already someone's active queue.
        status: ticket.status === "ASSIGNED" ? "ASSIGNED" : ticket.status,
        updatedAt: now,
        messages: [...ticket.messages, message],
      };

      await ref.set(updated);
      res.status(201).json(ticketJson(req.params.id, updated));
    })
  );

  return r;
}
