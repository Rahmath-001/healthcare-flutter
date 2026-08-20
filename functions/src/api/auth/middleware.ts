import type { NextFunction, Request, Response } from "express";

import { C, db, type UserDoc } from "../db";
import { Problem, TOKEN_STALE } from "../errors";
import { hasScope } from "./scopes";
import { verifyAccessToken, type AccessClaims } from "./tokens";

/**
 * Set by [requireAuth]. Augments the global `Express` namespace rather than
 * `express-serve-static-core` directly — pnpm's strict node_modules does not
 * expose transitive type packages for direct module augmentation.
 */
declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      auth?: AccessClaims;
      user?: UserDoc;
    }
  }
}

/**
 * Verifies the bearer token and re-reads the user.
 *
 * The re-read is the point. A JWT is a snapshot of authorization at mint time;
 * if a supervisor suspends an account, a token issued a minute earlier still
 * claims ACTIVE. Comparing the token's `ver` against the stored
 * `permissionVersion` turns that stale snapshot into a `TOKEN_STALE`, which the
 * Flutter `AuthInterceptor` answers by refreshing and replaying — so a
 * revocation takes effect on the next request, not in fifteen minutes.
 */
export function requireAuth(secret: () => string) {
  return async (req: Request, _res: Response, next: NextFunction) => {
    try {
      const header = req.header("authorization") ?? "";
      const [scheme, token] = header.split(" ");
      if (scheme?.toLowerCase() !== "bearer" || !token) {
        throw Problem.unauthorized("NO_TOKEN", "Please sign in again.");
      }

      const claims = verifyAccessToken(secret(), token);

      const snap = await db().collection(C.users).doc(claims.sub).get();
      if (!snap.exists) throw Problem.unauthorized("USER_NOT_FOUND", "Please sign in again.");
      const user = snap.data() as UserDoc;

      if (user.permissionVersion !== claims.ver) {
        throw Problem.unauthorized(TOKEN_STALE, "Your permissions changed. Reconnecting…");
      }

      if (user.status !== "ACTIVE") {
        throw Problem.forbidden("ACCOUNT_NOT_ACTIVE", "This account is not active.");
      }

      req.auth = claims;
      req.user = user;
      next();
    } catch (e) {
      next(e);
    }
  };
}

/** Rejects a request whose token does not carry [scope]. */
export function requireScope(scope: string) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.auth || !hasScope(req.auth.scopes, scope)) {
      return next(Problem.forbidden("SCOPE_REQUIRED", "You do not have access to this."));
    }
    next();
  };
}
