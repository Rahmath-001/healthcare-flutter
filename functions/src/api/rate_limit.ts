import type { NextFunction, Request, Response } from "express";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import { C, db } from "./db";
import { Problem } from "./errors";

/**
 * Fixed-window rate limiting, counted in Firestore.
 *
 * Firestore rather than process memory because Cloud Functions scales to
 * `maxInstances` independent containers: an in-process counter would give an
 * attacker one full budget per instance, and the budget would reset on every
 * cold start. A shared counter is the only kind that means anything here.
 *
 * The cost is one transaction per limited request, which is why this is applied
 * to the unauthenticated auth endpoints and not to the whole API. Those are the
 * routes worth protecting: they are reachable without a token, they perform the
 * most expensive work in the system (a Firebase ID-token verification, a
 * transaction, two writes), and they are the ones an attacker probes.
 *
 * The window is fixed rather than sliding, so a caller can spend up to two
 * budgets across a window boundary. That is a known and accepted property — the
 * alternative costs more reads than the attack it prevents.
 */
export interface RateLimitOptions {
  /** Distinct bucket name, so two limited routes do not share a budget. */
  readonly name: string;
  readonly max: number;
  readonly windowSeconds: number;
}

/**
 * Best-effort client identity for an unauthenticated request.
 *
 * `x-forwarded-for` is set by Google's front end and its *last* entry is the
 * one it observed; earlier entries are caller-supplied and trivially forged, so
 * taking the first — the usual reflex — limits an attacker-chosen string rather
 * than an attacker.
 */
function clientKey(req: Request): string {
  const forwarded = req.header("x-forwarded-for");
  if (forwarded) {
    const hops = forwarded.split(",").map((h) => h.trim()).filter(Boolean);
    if (hops.length > 0) return hops[hops.length - 1]!;
  }
  return req.ip ?? "unknown";
}

export function rateLimit(options: RateLimitOptions) {
  const { name, max, windowSeconds } = options;

  return async (req: Request, _res: Response, next: NextFunction) => {
    try {
      const windowMs = windowSeconds * 1000;
      const windowStart = Math.floor(Date.now() / windowMs) * windowMs;

      // The window index is part of the document id, so a new window is a new
      // document and expiry needs no cleanup pass to be correct.
      const key = clientKey(req).replace(/[^A-Za-z0-9_.:-]/g, "_").slice(0, 128);
      const ref = db().collection(C.rateLimits).doc(`${name}__${key}__${windowStart}`);

      const count = await db().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const current = snap.exists ? ((snap.data()?.count as number | undefined) ?? 0) : 0;
        if (current >= max) return current + 1;

        tx.set(
          ref,
          {
            count: FieldValue.increment(1),
            // Only used by the cleanup job; correctness does not depend on it.
            expiresAt: Timestamp.fromMillis(windowStart + windowMs),
          },
          { merge: true }
        );
        return current + 1;
      });

      if (count > max) {
        const retryAfter = Math.ceil((windowStart + windowMs - Date.now()) / 1000);
        logger.warn("Rate limit exceeded", { bucket: name, retryAfter });
        throw Problem.rateLimited(
          "Too many attempts. Please wait a moment and try again.",
          Math.max(retryAfter, 1)
        );
      }

      next();
    } catch (e) {
      // A limiter that fails closed would turn a Firestore blip into a total
      // sign-in outage. Availability of the auth path wins over the ceiling.
      if (e instanceof Problem) return next(e);
      logger.error("Rate limiter unavailable; allowing request", { bucket: name, err: e });
      next();
    }
  };
}
