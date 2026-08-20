import { randomUUID } from "crypto";
import jwt from "jsonwebtoken";

/**
 * 100ms join tokens.
 *
 * The token is a JWT signed with the app secret, and that is the entire reason
 * this lives on the server: a secret shipped in the client would let anyone
 * mint a token for any room and sit in any consultation. The client asks for a
 * token and never learns how one is made.
 *
 * `role` maps to a 100ms template role and decides what a participant may do —
 * a patient cannot mute the doctor, and neither can start a recording, which is
 * how FR-TEL-003 is enforced at the vendor rather than merely in the UI.
 */
export type HmsRole = "host" | "guest";

/**
 * Short-lived on purpose.
 *
 * The token authorises joining a specific room as a specific person. Twenty
 * minutes covers a late join and a reconnect after a dropped call, without
 * leaving a reusable key to somebody's consultation lying in a log.
 */
const TOKEN_TTL_SECONDS = 20 * 60;

export interface HmsCredentials {
  accessKey: string;
  secret: string;
}

export function mintJoinToken(
  credentials: HmsCredentials,
  options: { roomId: string; userId: string; role: HmsRole }
): { token: string; expiresIn: number } {
  const now = Math.floor(Date.now() / 1000);

  const token = jwt.sign(
    {
      access_key: credentials.accessKey,
      room_id: options.roomId,
      user_id: options.userId,
      role: options.role,
      type: "app",
      version: 2,
      iat: now,
      // A little leeway for clock skew between us and the vendor; without it a
      // token minted "now" can be rejected as not-yet-valid.
      nbf: now - 30,
      exp: now + TOKEN_TTL_SECONDS,
      jti: randomUUID(),
    },
    credentials.secret,
    { algorithm: "HS256" }
  );

  return { token, expiresIn: TOKEN_TTL_SECONDS };
}

/**
 * Whether the vendor is configured at all.
 *
 * Kept explicit so a missing secret fails as a clear, actionable error at the
 * one endpoint that needs it, rather than as a signature error from a library
 * three frames down.
 */
export function hmsCredentialsFrom(
  accessKey: string | undefined,
  secret: string | undefined
): HmsCredentials | null {
  if (!accessKey || !secret) return null;
  return { accessKey, secret };
}
