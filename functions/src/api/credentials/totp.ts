import { createHmac, randomBytes, timingSafeEqual } from "crypto";

/**
 * TOTP (RFC 6238) for provider multi-factor enrolment.
 *
 * Hand-rolled rather than pulled from a package, because the algorithm is forty
 * lines and the dependency would be a supply-chain risk sitting directly on the
 * authentication path of accounts that can read patient records and issue
 * prescriptions.
 *
 * MFA is part of the verification gate rather than an afterthought for exactly
 * that reason: an approved provider holds real power, so the account has to be
 * hard to take over *before* it gains any.
 */

/** 30 seconds, the near-universal default every authenticator app assumes. */
const PERIOD_SECONDS = 30;

const DIGITS = 6;

/**
 * How many periods either side of now are accepted.
 *
 * One step — so a window of roughly 90 seconds. Enough for a phone whose clock
 * has drifted or a user who types slowly; small enough that a code shoulder-
 * surfed from a screen is stale before it can be used.
 */
const DRIFT_STEPS = 1;

const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/** RFC 4648 base32, which is what authenticator apps expect in an otpauth URI. */
export function toBase32(buffer: Buffer): string {
  let bits = 0;
  let value = 0;
  let out = "";

  for (const byte of buffer) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += BASE32_ALPHABET[(value << (5 - bits)) & 31];

  return out;
}

export function fromBase32(encoded: string): Buffer {
  const clean = encoded.toUpperCase().replace(/=+$/, "").replace(/\s/g, "");
  let bits = 0;
  let value = 0;
  const out: number[] = [];

  for (const char of clean) {
    const index = BASE32_ALPHABET.indexOf(char);
    if (index === -1) throw new Error("Invalid base32");
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }

  return Buffer.from(out);
}

/** 160 bits, the size RFC 4226 recommends for HMAC-SHA1. */
export function generateSecret(): string {
  return toBase32(randomBytes(20));
}

function codeAt(secret: Buffer, counter: number): string {
  const message = Buffer.alloc(8);
  // Big-endian 64-bit counter. Written as two 32-bit halves because
  // writeBigUInt64BE would need a BigInt for a value that never exceeds 2^53.
  message.writeUInt32BE(Math.floor(counter / 0x100000000), 0);
  message.writeUInt32BE(counter >>> 0, 4);

  const digest = createHmac("sha1", secret).update(message).digest();

  // Dynamic truncation, RFC 4226 §5.3.
  const offset = digest[digest.length - 1]! & 0x0f;
  const binary =
    ((digest[offset]! & 0x7f) << 24) |
    ((digest[offset + 1]! & 0xff) << 16) |
    ((digest[offset + 2]! & 0xff) << 8) |
    (digest[offset + 3]! & 0xff);

  return (binary % 10 ** DIGITS).toString().padStart(DIGITS, "0");
}

/**
 * Verifies a submitted code against the secret.
 *
 * Compares in constant time. A timing-variable comparison over a six-digit
 * space is a genuinely practical oracle, not a theoretical one.
 */
export function verifyTotp(
  base32Secret: string,
  submitted: string,
  atMs: number = Date.now()
): boolean {
  const cleaned = submitted.replace(/\s/g, "");
  if (!/^\d{6}$/.test(cleaned)) return false;

  const secret = fromBase32(base32Secret);
  const counter = Math.floor(atMs / 1000 / PERIOD_SECONDS);

  for (let drift = -DRIFT_STEPS; drift <= DRIFT_STEPS; drift++) {
    const step = counter + drift;
    // A counter before the Unix epoch is not a window anyone can be in, and
    // feeding a negative number to writeUInt32BE throws rather than failing the
    // comparison. Skipping keeps a nonsensical clock from taking the endpoint
    // down instead of just refusing the code.
    if (step < 0) continue;

    const expected = Buffer.from(codeAt(secret, step));
    const actual = Buffer.from(cleaned);
    if (expected.length === actual.length && timingSafeEqual(expected, actual)) {
      return true;
    }
  }

  return false;
}

/**
 * The URI an authenticator app scans.
 *
 * The issuer appears both as a path prefix and as a parameter — older apps read
 * one, newer ones the other, and a mismatch shows the account under the wrong
 * name in the user's list.
 */
export function otpauthUri(secret: string, accountName: string): string {
  const issuer = "MiDoctor";
  const label = encodeURIComponent(`${issuer}:${accountName}`);
  const params = new URLSearchParams({
    secret,
    issuer,
    algorithm: "SHA1",
    digits: String(DIGITS),
    period: String(PERIOD_SECONDS),
  });
  return `otpauth://totp/${label}?${params.toString()}`;
}

/**
 * Single-use recovery codes.
 *
 * Returned once, in plaintext, and stored only as hashes — the same reason
 * refresh tokens are stored hashed. A database dump must not be a set of live
 * second factors.
 */
export function generateRecoveryCodes(count = 8): string[] {
  const codes: string[] = [];
  for (let i = 0; i < count; i++) {
    const raw = randomBytes(5).toString("hex").toUpperCase();
    codes.push(`${raw.slice(0, 5)}-${raw.slice(5, 10)}`);
  }
  return codes;
}
