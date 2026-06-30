import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

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
