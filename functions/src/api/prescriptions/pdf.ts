import { createHash } from "node:crypto";

import PDFDocument from "pdfkit";

import type { PrescriptionDoc } from "../db";

/**
 * The prescription PDF, rendered by the server.
 *
 * ## Why this is not the client's job
 *
 * It used to be. `prescription_pdf.dart` builds the same document on the
 * device, and that is fine as a convenience but it is not a record: a document
 * the client composes is a document the client can compose *differently*. The
 * pharmacist scanning the QR code, and anyone later asking what was actually
 * prescribed, need an artifact whose contents the prescribing party could not
 * have altered after the fact. That means generated here, from the stored
 * document, and written once — see `uploadImmutableObject`.
 *
 * The client keeps its renderer for offline viewing, but the server's copy is
 * the one the verification code refers to.
 *
 * ## Fonts
 *
 * Helvetica, which is WinAnsi and cannot render Devanagari. Every field that
 * reaches this document — drug names from the catalogue, registration numbers,
 * the verification code — is Latin by construction, but a patient's name may
 * not be. A name that will not encode is transliterated to `?` rather than
 * throwing, on the same reasoning the client applies: a Latin-only prescription
 * beats no prescription. Embedding a Devanagari TTF is the proper fix and is a
 * font-licensing decision, not a code one.
 */

const MARGIN = 48;
const RULE = "#D5DFDF";
const MUTED = "#4C5D5E";
const BRAND = "#0C7276";

/** Renders [doc] and returns the bytes plus their digest. */
export async function renderPrescriptionPdf(
  prescriptionId: string,
  doc: PrescriptionDoc
): Promise<{ bytes: Buffer; sha256: string }> {
  const bytes = await draw(prescriptionId, doc);
  return { bytes, sha256: createHash("sha256").update(bytes).digest("hex") };
}

function draw(prescriptionId: string, p: PrescriptionDoc): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const pdf = new PDFDocument({ size: "A4", margin: MARGIN });
    const chunks: Buffer[] = [];

    pdf.on("data", (c: Buffer) => chunks.push(c));
    pdf.on("end", () => resolve(Buffer.concat(chunks)));
    pdf.on("error", reject);

    const issued = p.issuedAt.toDate();

    // --- Header -----------------------------------------------------------
    pdf.fillColor(BRAND).fontSize(20).font("Helvetica-Bold").text("MiDoctor");
    pdf
      .fillColor(MUTED)
      .fontSize(9)
      .font("Helvetica")
      .text("Telemedicine prescription", { continued: false });

    pdf.moveDown(0.8);
    rule(pdf);
    pdf.moveDown(0.8);

    // --- Prescriber and patient ------------------------------------------
    const top = pdf.y;
    pdf.fillColor("#111C1D").fontSize(11).font("Helvetica-Bold").text(safe(p.providerName));
    pdf.fillColor(MUTED).fontSize(9).font("Helvetica");
    pdf.text(safe(p.providerQualification));
    // The council registration number is what makes this a prescription rather
    // than a note, and MoHFW requires it on the face of the document.
    pdf.text(`Reg. no. ${safe(p.providerRegistrationNumber)}`);

    const afterPrescriber = pdf.y;
    pdf.y = top;
    const rightX = pdf.page.width / 2;
    pdf.fillColor("#111C1D").fontSize(11).font("Helvetica-Bold");
    pdf.text(safe(p.patientName), rightX, top, { width: pdf.page.width - rightX - MARGIN });
    pdf.fillColor(MUTED).fontSize(9).font("Helvetica");
    pdf.text(`${safe(p.patientAge)} · ${safe(p.patientGender)}`, rightX, pdf.y, {
      width: pdf.page.width - rightX - MARGIN,
    });
    pdf.text(`Issued ${issued.toISOString().slice(0, 10)}`, rightX, pdf.y, {
      width: pdf.page.width - rightX - MARGIN,
    });

    pdf.x = MARGIN;
    pdf.y = Math.max(afterPrescriber, pdf.y) + 12;

    if (p.diagnosis) {
      labelled(pdf, "Diagnosis", p.diagnosis);
    }

    pdf.moveDown(0.4);
    rule(pdf);
    pdf.moveDown(0.6);

    // --- Items ------------------------------------------------------------
    pdf.fillColor("#111C1D").fontSize(12).font("Helvetica-Bold").text("Rx");
    pdf.moveDown(0.4);

    p.items.forEach((item, i) => {
      pdf
        .fillColor("#111C1D")
        .fontSize(10)
        .font("Helvetica-Bold")
        .text(`${i + 1}. ${safe(item.drugName)} ${safe(item.strength ?? "")}`.trim());

      const detail = [
        safe(item.form),
        safe(item.frequency),
        `${item.durationDays} day${item.durationDays === 1 ? "" : "s"}`,
      ]
        .filter((s) => s.length > 0)
        .join(" · ");

      pdf.fillColor(MUTED).fontSize(9).font("Helvetica").text(`    ${detail}`);
      if (item.instructions) {
        pdf.text(`    ${safe(item.instructions)}`);
      }
      pdf.moveDown(0.35);
    });

    if (p.advice) {
      pdf.moveDown(0.3);
      labelled(pdf, "Advice", p.advice);
    }

    if (p.followUpDate) {
      labelled(pdf, "Follow-up", p.followUpDate);
    }

    // --- Verification -----------------------------------------------------
    pdf.moveDown(0.8);
    rule(pdf);
    pdf.moveDown(0.6);

    labelled(pdf, "Verification code", p.verificationCode);
    pdf
      .fillColor(MUTED)
      .fontSize(8)
      .font("Helvetica")
      .text(
        "A pharmacist can confirm this prescription at midoctor.in/rx using the code above. " +
          "This document was generated by MiDoctor and is stored write-once; a copy that " +
          "differs from the verified record is not valid.",
        { width: pdf.page.width - MARGIN * 2 }
      );

    pdf.moveDown(0.4);
    pdf.fontSize(7).text(`Document id ${prescriptionId}`);
    if (p.appointmentReference) {
      pdf.text(`Consultation ${safe(p.appointmentReference)}`);
    }

    pdf.end();
  });
}

function rule(pdf: PDFKit.PDFDocument): void {
  pdf
    .strokeColor(RULE)
    .lineWidth(1)
    .moveTo(MARGIN, pdf.y)
    .lineTo(pdf.page.width - MARGIN, pdf.y)
    .stroke();
}

function labelled(pdf: PDFKit.PDFDocument, label: string, value: string): void {
  pdf.fillColor(MUTED).fontSize(8).font("Helvetica-Bold").text(label.toUpperCase());
  pdf.fillColor("#111C1D").fontSize(10).font("Helvetica").text(safe(value));
  pdf.moveDown(0.3);
}

/**
 * Replaces characters the built-in font cannot encode.
 *
 * pdfkit throws on an unencodable glyph, which would turn a patient with a
 * Devanagari name into a failed prescription. Substituting is the lesser harm,
 * and it is visible in the output rather than silent.
 */
export function safe(value: string): string {
  // eslint-disable-next-line no-control-regex
  return value.replace(/[^\x20-\x7E -ÿ]/g, "?");
}
