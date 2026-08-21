import type { Request, Response } from "express";

/**
 * The refresh token as an `HttpOnly` cookie, for browser clients only.
 *
 * ## Why this exists
 *
 * On mobile the refresh token goes in the response body and the client puts it
 * in the iOS Keychain or the Android KeyStore, which script cannot reach. The
 * web build has no equivalent: `flutter_secure_storage` on web is
 * `localStorage`, so the same token would sit where a single injected script —
 * a compromised dependency, an analytics tag, a stored-XSS — can read it. That
 * matters more than a stolen session usually would, because the server's
 * rotation and reuse-detection design assumes the token is *not* readable by
 * script: an attacker who can silently read it can refresh in lockstep and
 * never trip reuse detection.
 *
 * The client currently mitigates this by holding web credentials in memory only
 * (see `SecureTokenStore`), which costs the user their session on every tab
 * reload. This is the actual fix: the browser stores and returns the token, and
 * no script — ours or anyone else's — can read it at all.
 *
 * ## Why it is opt-in
 *
 * Cookie mode activates only when `WEB_ORIGINS` names the origins the web app
 * is served from. Unset means no cookies and no credentialed CORS, which is
 * exactly today's behaviour — so a deployment that has not thought about this
 * does not silently acquire a credentialed cross-origin surface.
 *
 * ## Deployment constraint
 *
 * `SameSite=Strict` means the cookie is only sent when the web app and the API
 * are on the same registrable domain — `app.midoctor.in` calling
 * `api.midoctor.in` is fine; a `*.web.app` Firebase Hosting default domain
 * calling `api.midoctor.in` is not, and refresh will fail there. Serve the web
 * app from a subdomain of the API's domain. `Strict` rather than `Lax` because
 * this cookie only ever accompanies a deliberate POST from our own page, and
 * `Lax` would permit top-level cross-site navigations to carry it.
 */

/** Scoped to the auth routes: no other endpoint has any use for it. */
export const REFRESH_COOKIE_PATH = "/v1/auth";

export const REFRESH_COOKIE_NAME = "midoctor_rt";

/**
 * Origins permitted to use credentialed CORS and receive the cookie.
 *
 * Read from `WEB_ORIGINS` as a comma-separated list. Empty disables cookie
 * mode entirely.
 */
export function webOrigins(env: NodeJS.ProcessEnv = process.env): string[] {
  return (env.WEB_ORIGINS ?? "")
    .split(",")
    .map((o) => o.trim())
    .filter((o) => o.length > 0);
}

export function cookieModeEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return webOrigins(env).length > 0;
}

/**
 * True when this request should use the cookie rather than the JSON body.
 *
 * Keyed on `Origin`, because that header is set by the browser and cannot be
 * forged by page script — the one signal here that a hostile page cannot lie
 * about. A native Dio client sends no `Origin` at all and therefore keeps the
 * existing body-based contract, which is what makes this change invisible to
 * every shipped mobile build.
 */
export function isBrowserClient(
  req: Request,
  env: NodeJS.ProcessEnv = process.env
): boolean {
  const origin = req.headers.origin;
  if (typeof origin !== "string" || origin.length === 0) return false;
  return webOrigins(env).includes(origin);
}

/**
 * Reads the refresh token out of the `Cookie` header.
 *
 * Parsed by hand rather than with `cookie-parser`: one cookie, one call site,
 * and a dependency that runs on every request of an API carrying health data is
 * a dependency worth not having.
 */
export function readRefreshCookie(req: Request): string | undefined {
  const header = req.headers.cookie;
  if (typeof header !== "string") return undefined;

  for (const part of header.split(";")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    if (part.slice(0, eq).trim() !== REFRESH_COOKIE_NAME) continue;
    const value = part.slice(eq + 1).trim();
    return value.length > 0 ? decodeURIComponent(value) : undefined;
  }
  return undefined;
}

export function setRefreshCookie(
  res: Response,
  token: string,
  maxAgeSeconds: number
): void {
  res.cookie(REFRESH_COOKIE_NAME, token, {
    httpOnly: true,
    // Non-negotiable: a refresh token on a cleartext connection is a refresh
    // token in a stranger's hands. The platform config already forbids
    // cleartext, and this says so again at the point it matters.
    secure: true,
    sameSite: "strict",
    path: REFRESH_COOKIE_PATH,
    maxAge: maxAgeSeconds * 1000,
  });
}

/**
 * Clears the cookie on logout.
 *
 * The attributes must match those it was set with or the browser treats it as
 * a different cookie and leaves the original in place — which would mean a
 * "signed out" browser still holding a refresh token.
 */
export function clearRefreshCookie(res: Response): void {
  res.clearCookie(REFRESH_COOKIE_NAME, {
    httpOnly: true,
    secure: true,
    sameSite: "strict",
    path: REFRESH_COOKIE_PATH,
  });
}
