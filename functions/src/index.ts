import { initializeApp } from "firebase-admin/app";
import { defineSecret } from "firebase-functions/params";
import { onRequest } from "firebase-functions/v2/https";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { buildApp } from "./api/app";

export { inspectUpload } from "./inspect_upload";
export { completeErasures, sweepNightly, sweepShortLived } from "./maintenance";

initializeApp();

/**
 * Signing key for MiDoctor access tokens. Set with:
 *   firebase functions:secrets:set JWT_SECRET
 *
 * Rotating it invalidates every access token immediately — which is the
 * emergency lever, since refresh tokens live in Firestore and can be revoked
 * separately. Generate at least 32 random bytes; a guessable value here lets
 * anyone mint an admin token.
 */
const JWT_SECRET = defineSecret("JWT_SECRET");

/**
 * 100ms credentials for minting consultation join tokens.
 *
 * Server-only, and that is the whole point: the app secret signs a token that
 * authorises joining a room, so shipping it in the client would let anyone sit
 * in on any consultation. Set with:
 *   firebase functions:secrets:set HMS_APP_ACCESS_KEY
 *   firebase functions:secrets:set HMS_APP_SECRET
 *
 * Absent, video consultations fail with a clear message rather than a
 * signature error nobody can act on.
 */
const HMS_APP_ACCESS_KEY = defineSecret("HMS_APP_ACCESS_KEY");
const HMS_APP_SECRET = defineSecret("HMS_APP_SECRET");

/**
 * The MiDoctor API.
 *
 * asia-south1 (Mumbai): domain data stays India-resident, and RTT from Indian
 * mobile networks is a fraction of a US or EU region's.
 *
 * Point the client at it with:
 *   --dart-define=API_BASE_URL=https://asia-south1-<project>.cloudfunctions.net/api
 *   --dart-define=USE_FIXTURES=false
 */
function optionalSecret(param: { value: () => string }): string | undefined {
  try {
    return param.value() || undefined;
  } catch {
    return undefined;
  }
}

export const api = onRequest(
  {
    region: "asia-south1",
    secrets: [JWT_SECRET, HMS_APP_ACCESS_KEY, HMS_APP_SECRET],
    // India's mobile networks are slow rather than absent; a request that has
    // reached us deserves room to finish.
    timeoutSeconds: 60,
    memory: "512MiB",
    // Cold starts on an auth endpoint are felt directly at the sign-in button.
    minInstances: 0,
    maxInstances: 20,
  },
  buildApp({
    secret: () => JWT_SECRET.value(),
    // `value()` throws if the secret was never set, so an unconfigured
    // deployment must degrade to undefined rather than take the API down.
    hmsAccessKey: () => optionalSecret(HMS_APP_ACCESS_KEY),
    hmsSecret: () => optionalSecret(HMS_APP_SECRET),
  })
);

// Twilio creds live only on the server. Set with:
//   firebase functions:secrets:set TWILIO_SID
//   firebase functions:secrets:set TWILIO_TOKEN
const TWILIO_SID = defineSecret("TWILIO_SID");
const TWILIO_TOKEN = defineSecret("TWILIO_TOKEN");

// Allowed Indian carriers. Twilio returns the *current* (post-portability)
// carrier, so this is reliable where prefix matching is not.
const ALLOWED = [
  { match: ["bharti", "airtel"], name: "Airtel" },
  { match: ["jio"], name: "Jio" },
  { match: ["vodafone", "idea", "vi "], name: "Vi" },
];

function classify(carrierName: string): string | null {
  const lc = carrierName.toLowerCase();
  for (const c of ALLOWED) {
    if (c.match.some((m) => lc.includes(m))) return c.name;
  }
  return null;
}

/**
 * verifyIndianCarrier({ phone: "+91XXXXXXXXXX" })
 * -> { ok, carrier, type, reason? }
 * Rejects: non-+91, VoIP/landline, carriers outside Airtel/Jio/Vi.
 */
export const verifyIndianCarrier = onCall(
  { secrets: [TWILIO_SID, TWILIO_TOKEN], region: "asia-south1" },
  async (request) => {
    const phone = String(request.data?.phone ?? "").trim();

    if (!/^\+91\d{10}$/.test(phone)) {
      return { ok: false, reason: "Must be a +91 Indian mobile number." };
    }

    const url =
      `https://lookups.twilio.com/v2/PhoneNumbers/${encodeURIComponent(phone)}` +
      `?Fields=line_type_intelligence`;
    const auth = Buffer.from(
      `${TWILIO_SID.value()}:${TWILIO_TOKEN.value()}`
    ).toString("base64");

    let body: any;
    try {
      const res = await fetch(url, {
        headers: { Authorization: `Basic ${auth}` },
      });
      if (!res.ok) {
        throw new HttpsError("internal", `Lookup HTTP ${res.status}`);
      }
      body = await res.json();
    } catch (e) {
      throw new HttpsError("unavailable", "Carrier lookup failed.");
    }

    const lti = body?.line_type_intelligence ?? {};
    const type: string = (lti.type ?? "").toLowerCase();
    const carrierName: string = lti.carrier_name ?? "";

    if (type === "voip") {
      return { ok: false, type, carrier: carrierName, reason: "VoIP numbers are not allowed." };
    }
    if (type && type !== "mobile") {
      return { ok: false, type, carrier: carrierName, reason: "Only mobile numbers are allowed." };
    }

    const carrier = classify(carrierName);
    if (!carrier) {
      return {
        ok: false,
        type,
        carrier: carrierName,
        reason: "Only Airtel, Jio or Vi numbers are allowed.",
      };
    }

    return { ok: true, type: type || "mobile", carrier };
  }
);
