import { Timestamp } from "firebase-admin/firestore";
import { Router } from "express";

import { C, db, type OrganisationRegistrationDoc } from "../db";
import { handler, Problem } from "../errors";
import { rateLimit } from "../rate_limit";

const TYPES = new Set(["HOSPITAL", "LAB_DIAGNOSTICS", "HOME_HEALTH_PROVIDER"]);
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const INDIA_MOBILE = /^\+91[6-9]\d{9}$/;

function text(value: unknown, field: string, maxLength: number): string {
  if (typeof value !== "string" || !value.trim()) {
    throw Problem.validation("Complete all required details.", { [field]: "required" });
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLength) {
    throw Problem.validation("One or more fields are too long.", { [field]: "too long" });
  }
  return trimmed;
}

/** Public prospect form from the hospital/lab/home-health wireframe. */
export function organisationRegistrationRoutes(): Router {
  const r = Router();

  r.post(
    "/",
    rateLimit({ name: "organisation_registration", max: 5, windowSeconds: 3600 }),
    handler(async (req, res) => {
      const body = req.body ?? {};
      const type = body.type;
      if (typeof type !== "string" || !TYPES.has(type)) {
        throw Problem.validation("Choose a valid organisation type.", { type: "invalid" });
      }

      const email = text(body.email, "email", 254).toLowerCase();
      if (!EMAIL.test(email)) {
        throw Problem.validation("Enter a valid email address.", { email: "invalid" });
      }
      const phone = text(body.phone, "phone", 13);
      if (!INDIA_MOBILE.test(phone)) {
        throw Problem.validation("Enter a valid Indian mobile number.", { phone: "invalid" });
      }
      if (body.country !== "India") {
        throw Problem.validation("Organisation registration is currently India-only.", {
          country: "invalid",
        });
      }

      const registration: OrganisationRegistrationDoc = {
        type: type as OrganisationRegistrationDoc["type"],
        name: text(body.name, "name", 160),
        registrationNumber: text(body.registrationNumber, "registrationNumber", 100),
        email,
        phone,
        address: text(body.address, "address", 500),
        city: text(body.city, "city", 120),
        postalCode: text(body.postalCode, "postalCode", 20),
        state: text(body.state, "state", 120),
        country: "India",
        status: "SUBMITTED",
        submittedAt: Timestamp.now(),
      };

      const ref = await db().collection(C.organisationRegistrations).add(registration);
      res.status(201).json({ id: ref.id, status: registration.status });
    })
  );

  return r;
}
