import { describe, expect, it } from "vitest";

import {
  fromBase32,
  generateRecoveryCodes,
  generateSecret,
  otpauthUri,
  toBase32,
  verifyTotp,
} from "./totp";

/**
 * TOTP.
 *
 * Hand-rolled, so it needs the RFC's own vectors rather than a "does it round
 * trip" test — an implementation can be self-consistent and still disagree with
 * every authenticator app on earth, which is a bug nobody finds until a doctor
 * cannot sign in.
 */
describe("base32", () => {
  it("matches RFC 4648 test vectors", () => {
    expect(toBase32(Buffer.from("f"))).toBe("MY");
    expect(toBase32(Buffer.from("fo"))).toBe("MZXQ");
    expect(toBase32(Buffer.from("foo"))).toBe("MZXW6");
    expect(toBase32(Buffer.from("foobar"))).toBe("MZXW6YTBOI");
  });

  it("round-trips arbitrary bytes", () => {
    const original = Buffer.from([0x00, 0xff, 0x10, 0x7a, 0x5c, 0x03]);
    expect(fromBase32(toBase32(original))).toEqual(original);
  });

  it("ignores padding, whitespace and case, as authenticator apps do", () => {
    expect(fromBase32("mzxw6ytboi")).toEqual(Buffer.from("foobar"));
    expect(fromBase32("MZXW 6YTB OI")).toEqual(Buffer.from("foobar"));
    expect(fromBase32("MZXW6YTBOI======")).toEqual(Buffer.from("foobar"));
  });
});

describe("verifyTotp", () => {
  // RFC 6238 Appendix B, SHA-1: the secret is ASCII "12345678901234567890".
  const rfcSecret = toBase32(Buffer.from("12345678901234567890"));

  it("produces the RFC 6238 reference codes", () => {
    // The published vectors are 8-digit; the last six are what a 6-digit
    // implementation must emit at those instants.
    expect(verifyTotp(rfcSecret, "287082", 59_000)).toBe(true);
    expect(verifyTotp(rfcSecret, "081804", 1_111_111_109_000)).toBe(true);
    expect(verifyTotp(rfcSecret, "005924", 1_234_567_890_000)).toBe(true);
    expect(verifyTotp(rfcSecret, "279037", 2_000_000_000_000)).toBe(true);
  });

  it("rejects a code from a different secret", () => {
    expect(verifyTotp(generateSecret(), "287082", 59_000)).toBe(false);
  });

  it("accepts one step of clock drift in either direction", () => {
    // A phone whose clock is a little off, or a user who types slowly.
    expect(verifyTotp(rfcSecret, "287082", 59_000 + 30_000)).toBe(true);
    expect(verifyTotp(rfcSecret, "287082", 59_000 - 30_000)).toBe(true);
  });

  it("rejects a code that is two steps stale", () => {
    // Shoulder-surfed from a screen is worthless by the time it is typed.
    expect(verifyTotp(rfcSecret, "287082", 59_000 + 90_000)).toBe(false);
    expect(verifyTotp(rfcSecret, "287082", 59_000 - 90_000)).toBe(false);
  });

  it("refuses anything that is not six digits", () => {
    for (const bad of ["", "12345", "1234567", "abcdef", "12 34 56 ", "-12345"]) {
      expect(verifyTotp(rfcSecret, bad, 59_000), bad).toBe(false);
    }
  });

  it("tolerates spaces, which apps and users both add", () => {
    expect(verifyTotp(rfcSecret, "287 082", 59_000)).toBe(true);
  });
});

describe("generateSecret", () => {
  it("is 160 bits, as RFC 4226 recommends for HMAC-SHA1", () => {
    expect(fromBase32(generateSecret())).toHaveLength(20);
  });

  it("is not predictable", () => {
    const seen = new Set(Array.from({ length: 50 }, () => generateSecret()));
    expect(seen.size).toBe(50);
  });
});

describe("otpauthUri", () => {
  it("carries the issuer in both places apps look for it", () => {
    const uri = otpauthUri("JBSWY3DPEHPK3PXP", "priya@example.com");
    // Older apps read the label prefix, newer ones the parameter; a mismatch
    // files the account under the wrong name in the user's list.
    expect(uri).toContain("otpauth://totp/MiDoctor%3Apriya%40example.com");
    expect(uri).toContain("issuer=MiDoctor");
    expect(uri).toContain("secret=JBSWY3DPEHPK3PXP");
    expect(uri).toContain("digits=6");
    expect(uri).toContain("period=30");
  });
});

describe("generateRecoveryCodes", () => {
  it("returns eight distinct, readable codes", () => {
    const codes = generateRecoveryCodes();
    expect(codes).toHaveLength(8);
    expect(new Set(codes).size).toBe(8);
    for (const code of codes) {
      expect(code).toMatch(/^[0-9A-F]{5}-[0-9A-F]{5}$/);
    }
  });
});
