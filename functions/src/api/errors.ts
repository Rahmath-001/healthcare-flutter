import type { NextFunction, Request, Response } from "express";
import { logger } from "firebase-functions";

/**
 * RFC 9457 (`application/problem+json`) error.
 *
 * The Flutter client parses exactly these fields in `ProblemJson.fromResponse`
 * and turns them into a `Failure`, so the shape here is a contract, not a
 * convention. In particular the client shows `detail` to the user verbatim —
 * so `detail` must never carry clinical information or server internals.
 */
export class Problem extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly title: string,
    readonly detail: string,
    readonly errors?: Record<string, string>,
    readonly retryAfterSeconds?: number
  ) {
    super(`${code}: ${detail}`);
  }

  static badRequest(code: string, detail: string, errors?: Record<string, string>) {
    return new Problem(400, code, "Bad request", detail, errors);
  }

  static unauthorized(code: string, detail: string) {
    return new Problem(401, code, "Unauthorized", detail);
  }

  static forbidden(code: string, detail: string) {
    return new Problem(403, code, "Forbidden", detail);
  }

  static notFound(code: string, detail: string) {
    return new Problem(404, code, "Not found", detail);
  }

  static conflict(code: string, detail: string) {
    return new Problem(409, code, "Conflict", detail);
  }

  static validation(detail: string, errors?: Record<string, string>) {
    return new Problem(422, "VALIDATION_FAILED", "Validation failed", detail, errors);
  }

  static rateLimited(detail: string, retryAfterSeconds: number) {
    return new Problem(429, "RATE_LIMITED", "Too many requests", detail, undefined, retryAfterSeconds);
  }

  static internal(detail = "Something went wrong. Please try again.") {
    return new Problem(500, "INTERNAL", "Internal server error", detail);
  }
}

/**
 * Sentinel the Flutter `AuthInterceptor` treats exactly like a 401: refresh the
 * access token once, then replay the request.
 *
 * Returned when a token is cryptographically valid but its `ver` claim is
 * behind the user's current `permissionVersion` — the user's role, status or
 * scopes changed after the token was minted. The canonical case is a provider
 * being approved: their old token still says DRAFT.
 */
export const TOKEN_STALE = "TOKEN_STALE";

/**
 * Attaches a request id used for log correlation and support tickets.
 *
 * A caller-supplied id is honoured so a client can tie its own logs to ours,
 * but only after it is checked against a deliberately narrow shape. The value
 * is written into structured logs and echoed in a response header, and an
 * unvalidated string reaching both is how log injection and header splitting
 * happen. Anything that is not a short, boring token is replaced rather than
 * rejected — the request itself is not at fault.
 */
const REQUEST_ID_SHAPE = /^[A-Za-z0-9_.:-]{1,64}$/;

export function requestId(req: Request, res: Response, next: NextFunction) {
  const supplied = req.header("x-request-id");
  const id =
    supplied && REQUEST_ID_SHAPE.test(supplied)
      ? supplied
      : `req_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
  res.locals.requestId = id;
  res.setHeader("x-request-id", id);
  next();
}

/** Terminal error handler. Every route funnels here, so nothing leaks a stack. */
export function problemHandler(err: unknown, req: Request, res: Response, _next: NextFunction) {
  const id = res.locals.requestId as string | undefined;

  const problem =
    err instanceof Problem
      ? err
      : (logger.error("Unhandled error", { err, requestId: id, path: req.path }), Problem.internal());

  if (problem.retryAfterSeconds !== undefined) {
    res.setHeader("retry-after", String(problem.retryAfterSeconds));
  }

  res.status(problem.status).type("application/problem+json").json({
    type: `https://midoctor.in/errors/${problem.code.toLowerCase().replace(/_/g, "-")}`,
    title: problem.title,
    status: problem.status,
    detail: problem.detail,
    code: problem.code,
    requestId: id,
    ...(problem.errors ? { errors: problem.errors } : {}),
  });
}

/** Wraps an async handler so a rejected promise reaches [problemHandler]. */
export function handler<T>(fn: (req: Request, res: Response) => Promise<T>) {
  return (req: Request, res: Response, next: NextFunction) => {
    fn(req, res).catch(next);
  };
}
