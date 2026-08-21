import type { Request, Response } from "express";
import { describe, expect, it, vi } from "vitest";

import {
  REFRESH_COOKIE_NAME,
  REFRESH_COOKIE_PATH,
  clearRefreshCookie,
  cookieModeEnabled,
  isBrowserClient,
  readRefreshCookie,
  setRefreshCookie,
  webOrigins,
} from "./refresh_cookie";

const req = (headers: Record<string, string>) =>
  ({ headers }) as unknown as Request;

const res = () => {
  const calls: { name: string; args: unknown[] }[] = [];
  const r = {
    cookie: vi.fn((...args: unknown[]) => calls.push({ name: "cookie", args })),
    clearCookie: vi.fn((...args: unknown[]) =>
      calls.push({ name: "clearCookie", args })
    ),
  };
  return { res: r as unknown as Response, calls };
};

describe("cookie mode is opt-in", () => {
  it("is off when WEB_ORIGINS is unset", () => {
    // The default has to be today's behaviour, or a deployment that has not
    // thought about this silently acquires a credentialed cross-origin surface.
    expect(cookieModeEnabled({})).toBe(false);
    expect(webOrigins({})).toEqual([]);
  });

  it("is off when WEB_ORIGINS is empty or whitespace", () => {
    expect(cookieModeEnabled({ WEB_ORIGINS: "" })).toBe(false);
    expect(cookieModeEnabled({ WEB_ORIGINS: "  , ,, " })).toBe(false);
  });

  it("parses a comma-separated list, trimming", () => {
    expect(
      webOrigins({ WEB_ORIGINS: "https://app.midoctor.in, https://admin.midoctor.in" })
    ).toEqual(["https://app.midoctor.in", "https://admin.midoctor.in"]);
  });
});

describe("browser detection", () => {
  const env = { WEB_ORIGINS: "https://app.midoctor.in" };

  it("treats an allow-listed Origin as a browser", () => {
    expect(
      isBrowserClient(req({ origin: "https://app.midoctor.in" }), env)
    ).toBe(true);
  });

  it("ignores an Origin that is not allow-listed", () => {
    // Otherwise any site could opt itself into cookie mode by sending an
    // Origin header, and the response would stop carrying the token the real
    // client needs.
    expect(isBrowserClient(req({ origin: "https://evil.example" }), env)).toBe(
      false
    );
  });

  it("treats a request with no Origin as native", () => {
    // This is what keeps every shipped mobile build on the existing body-based
    // contract: Dio sends no Origin, so nothing about its flow changes.
    expect(isBrowserClient(req({}), env)).toBe(false);
    expect(isBrowserClient(req({ origin: "" }), env)).toBe(false);
  });
});

describe("reading the cookie", () => {
  it("finds the token among other cookies", () => {
    expect(
      readRefreshCookie(
        req({ cookie: `_ga=GA1.2.3; ${REFRESH_COOKIE_NAME}=abc123; theme=dark` })
      )
    ).toBe("abc123");
  });

  it("url-decodes the value", () => {
    expect(
      readRefreshCookie(req({ cookie: `${REFRESH_COOKIE_NAME}=a%2Bb%3Dc` }))
    ).toBe("a+b=c");
  });

  it("returns undefined when absent, empty, or there is no header", () => {
    expect(readRefreshCookie(req({}))).toBeUndefined();
    expect(readRefreshCookie(req({ cookie: "theme=dark" }))).toBeUndefined();
    expect(
      readRefreshCookie(req({ cookie: `${REFRESH_COOKIE_NAME}=` }))
    ).toBeUndefined();
  });

  it("does not match a cookie whose name merely ends with ours", () => {
    expect(
      readRefreshCookie(req({ cookie: `not_${REFRESH_COOKIE_NAME}=nope` }))
    ).toBeUndefined();
  });
});

describe("writing the cookie", () => {
  it("is HttpOnly, Secure, SameSite=Strict and scoped to the auth path", () => {
    // Every one of these is load-bearing: HttpOnly is the whole feature,
    // Secure keeps it off cleartext, Strict is the CSRF control, and the path
    // stops it riding along on every unrelated API call.
    const { res: r } = res();
    setRefreshCookie(r, "token-value", 3600);

    expect(r.cookie).toHaveBeenCalledWith(REFRESH_COOKIE_NAME, "token-value", {
      httpOnly: true,
      secure: true,
      sameSite: "strict",
      path: REFRESH_COOKIE_PATH,
      maxAge: 3_600_000,
    });
  });

  it("clears with attributes matching the ones it was set with", () => {
    // A mismatch means the browser treats it as a different cookie and leaves
    // the original in place — a "signed out" browser still holding a token.
    const { res: r } = res();
    clearRefreshCookie(r);

    expect(r.clearCookie).toHaveBeenCalledWith(REFRESH_COOKIE_NAME, {
      httpOnly: true,
      secure: true,
      sameSite: "strict",
      path: REFRESH_COOKIE_PATH,
    });
  });
});
