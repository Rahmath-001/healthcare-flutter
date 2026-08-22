import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { requireAuth, requireScope } from "../auth/middleware";
import { C, db, type AccessEventDoc, type UserDoc } from "../db";
import { handler, Problem } from "../errors";

/**
 * The console's overview and its access log.
 *
 * Two screens that had no endpoints: an operator opening the console could not
 * tell which of four queues needed them, and the record access log - written
 * since consent shipped - could only be read with a Firestore console, which
 * is not a process anybody can put in a privacy notice.
 */

const SUPPORT_RESPONSE_TARGET_HOURS = 24;
const AUDIT_PAGE = 200;

function hoursSince(t: Timestamp | undefined): number | null {
  if (!t) return null;
  return Math.floor((Date.now() - t.toDate().getTime()) / 3_600_000);
}

function has(scopes: string[], scope: string): boolean {
  return scopes.includes("*:*") || scopes.includes(scope);
}

export function overviewRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));

  /**
   * `GET /v1/admin/summary` — what is waiting.
   *
   * Each section is **omitted entirely** when the caller lacks the scope for
   * the queue behind it, rather than returned as a zero. A support agent has
   * no business knowing how many doctors are awaiting verification, and a
   * count that reaches the client and is merely hidden by the UI has already
   * left the building. This is the same reason the console has no user search.
   */
  r.get(
    "/summary",
    handler(async (req, res) => {
      const scopes = req.auth!.scopes ?? [];
      const out: Record<string, unknown> = {};

      if (has(scopes, "provider:review")) {
        const apps = await db()
          .collection(C.users)
          .where("role", "==", "PROVIDER")
          .where("providerStatus", "in", ["SUBMITTED", "UNDER_REVIEW"])
          .get();

        let oldest: Timestamp | undefined;
        apps.docs.forEach((d) => {
          const at = (d.data() as UserDoc & { submittedAt?: Timestamp })
            .submittedAt;
          if (at && (!oldest || at.toMillis() < oldest.toMillis())) oldest = at;
        });

        out.verification = {
          pending: apps.size,
          // The figure that matters more than the count: ten applications
          // filed this morning is a normal Tuesday, and one filed three weeks
          // ago is somebody who cannot earn a living.
          oldestWaitingHours: hoursSince(oldest),
        };

        const ratings = await db()
          .collection(C.ratings)
          .where("status", "==", "PENDING_MODERATION")
          .get();

        let oldestRating: Timestamp | undefined;
        ratings.docs.forEach((d) => {
          const at = (d.data() as { createdAt?: Timestamp }).createdAt;
          if (at && (!oldestRating || at.toMillis() < oldestRating.toMillis())) {
            oldestRating = at;
          }
        });

        out.moderation = {
          pending: ratings.size,
          oldestWaitingHours: hoursSince(oldestRating),
        };
      }

      if (has(scopes, "support:ticket_read")) {
        const tickets = await db()
          .collection(C.supportTickets)
          .where("status", "in", ["OPEN", "AWAITING_USER", "ESCALATED"])
          .get();

        let oldestTicket: Timestamp | undefined;
        let breaching = 0;
        tickets.docs.forEach((d) => {
          const at = (d.data() as { createdAt?: Timestamp }).createdAt;
          if (!at) return;
          if (!oldestTicket || at.toMillis() < oldestTicket.toMillis()) {
            oldestTicket = at;
          }
          const age = hoursSince(at);
          if (age !== null && age >= SUPPORT_RESPONSE_TARGET_HOURS) breaching++;
        });

        out.support = {
          open: tickets.size,
          // A placeholder target with no contractual authority behind it,
          // exactly like the free-cancellation window.
          breachingSla: breaching,
          oldestWaitingHours: hoursSince(oldestTicket),
        };
      }

      res.json(out);
    })
  );

  /**
   * `GET /v1/admin/audit/:userId` — every recorded read of one account's
   * records, newest first.
   *
   * Behind `user:suspend` rather than a scope of its own: reading who saw
   * whose records is at least as sensitive as ending somebody's session, and
   * the operators who already act on accounts are the ones who need it.
   *
   * **Denials are included.** A doctor repeatedly trying records they hold no
   * grant for is the pattern an audit log exists to surface, and a log of
   * successes only would hide the one thing worth finding.
   *
   * **Reading it is itself recorded.** An audit log whose readers are not
   * audited protects everybody except from the people holding it.
   */
  r.get(
    "/audit/:userId",
    requireScope("user:suspend"),
    handler(async (req, res) => {
      const userId = req.params.userId;
      if (!userId) throw Problem.validation("An account id is required.", {
        userId: "required",
      });

      const snap = await db()
        .collection(C.accessLog)
        .where("patientId", "==", userId)
        .orderBy("at", "desc")
        .limit(AUDIT_PAGE)
        .get();

      const events = snap.docs.map((d) => {
        const e = d.data() as AccessEventDoc;
        return {
          id: d.id,
          actorName: e.actorName,
          actorRole: "Provider",
          recordTitle: e.recordTitle,
          action: e.action === "DENIED" ? "denied" : e.action.toLowerCase(),
          at: e.at.toDate().toISOString(),
        };
      });

      // Written after the read, and never allowed to fail it: an operator
      // must not be able to suppress their own entry by breaking the write.
      // The entry naming the operator is the point of the whole endpoint.
      const entry: AccessEventDoc = {
        patientId: userId,
        actorId: req.auth!.sub,
        actorName: req.user?.displayName ?? "Operations",
        recordTitle: "Access log",
        action: "VIEW_METADATA",
        at: Timestamp.now(),
      };
      await db().collection(C.accessLog).add(entry);

      res.json(events);
    })
  );

  return r;
}
