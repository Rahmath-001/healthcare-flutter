import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";

import type { PrescriptionDoc } from "../db";
import { renderPrescriptionPdf, safe } from "./pdf";

const base: PrescriptionDoc = {
  patientId: "p1",
  doctorId: "d1",
  appointmentId: "a1",
  verificationCode: "MD-7F3K-2QX9",
  providerName: "Dr Anjali Rao",
  providerQualification: "MBBS, MD (General Medicine)",
  providerRegistrationNumber: "KMC/12345",
  patientName: "Priya Sharma",
  patientAge: "34 years",
  patientGender: "FEMALE",
  issuedAt: Timestamp.fromDate(new Date("2026-08-21T09:30:00Z")),
  status: "ISSUED",
  items: [
    {
      drugName: "Paracetamol",
      genericName: "Paracetamol",
      strength: "500 mg",
      form: "Tablet",
      frequency: "1-0-1",
      durationDays: 5,
      instructions: "After food",
    },
    {
      drugName: "Cetirizine",
      genericName: "Cetirizine",
      strength: "10 mg",
      form: "Tablet",
      frequency: "0-0-1",
      durationDays: 1,
      instructions: null,
    },
  ],
  diagnosis: "Viral fever",
  advice: "Rest and fluids. Return if the fever persists beyond three days.",
  followUpDate: "2026-08-28",
  appointmentReference: "MD8842",
  isFollowUp: false,
};

describe("prescription PDF", () => {
  it("produces a real PDF", async () => {
    const { bytes } = await renderPrescriptionPdf("rx-1", base);

    expect(bytes.subarray(0, 5).toString("latin1")).toBe("%PDF-");
    // A header-only file would also start with %PDF-; this is the crude but
    // effective check that something was actually drawn.
    expect(bytes.length).toBeGreaterThan(1000);
  });

  it("digests the exact bytes it stored", async () => {
    const { bytes, sha256 } = await renderPrescriptionPdf("rx-1", base);

    const { createHash } = await import("node:crypto");
    expect(sha256).toBe(createHash("sha256").update(bytes).digest("hex"));

    // Note deliberately not asserted: that two renders of the same
    // prescription produce the same digest. They do not — a PDF embeds a
    // creation timestamp and a file id. The digest verifies the stored
    // artifact against what was recorded, which is what integrity means here;
    // it is not a content fingerprint and must not be used as one.
  });

  it("renders a name the built-in font cannot encode, rather than throwing", async () => {
    // The real regression this guards. pdfkit throws on an unencodable glyph,
    // so a patient with a Devanagari name would have turned into a failed
    // prescription document — silently, since storage failures are swallowed.
    const { bytes } = await renderPrescriptionPdf("rx-2", {
      ...base,
      patientName: "प्रिया शर्मा",
      diagnosis: "बुखार",
    });

    expect(bytes.subarray(0, 5).toString("latin1")).toBe("%PDF-");
  });

  it("renders with every optional field absent", async () => {
    const { bytes } = await renderPrescriptionPdf("rx-3", {
      ...base,
      diagnosis: null,
      advice: null,
      followUpDate: null,
      appointmentReference: null,
      items: [{ ...base.items[0], instructions: null }],
    });

    expect(bytes.subarray(0, 5).toString("latin1")).toBe("%PDF-");
  });
});

describe("safe()", () => {
  it("passes ASCII and Latin-1 through untouched", () => {
    expect(safe("Dr Anjali Rao, MBBS (Hons.) - 500mg")).toBe(
      "Dr Anjali Rao, MBBS (Hons.) - 500mg"
    );
    expect(safe("Café")).toBe("Café");
  });

  it("substitutes what the font cannot draw", () => {
    expect(safe("प्रिया")).toBe("??????");
  });
});
