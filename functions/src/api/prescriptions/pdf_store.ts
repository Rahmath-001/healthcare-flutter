import { Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import { C, db, type PrescriptionDoc } from "../db";
import { prescriptionPdfPath, uploadImmutableObject } from "../storage";
import { renderPrescriptionPdf } from "./pdf";

/**
 * The stored-document half of issuing a prescription.
 *
 * Split from the route so the scheduled sweep can run exactly the same code
 * against a prescription whose first attempt failed. Two implementations of
 * "what the frozen document contains" is how the retry ends up producing a
 * different PDF from the original.
 */
export type StoredPdf = Pick<
  PrescriptionDoc,
  "pdfPath" | "pdfSha256" | "pdfStoredAt"
>;

/**
 * Renders, freezes and records the prescription PDF.
 *
 * **Never throws.** Issuing a prescription is a clinical act and it has already
 * been committed by the time this runs; failing the request afterwards would
 * tell a doctor their prescription did not happen when it did, and they would
 * write it again. A failure here leaves `pdfPath` null, which the sweep picks
 * up — the prescription is still valid and still verifiable, it simply has no
 * downloadable document yet.
 */
export async function storePrescriptionPdf(
  prescriptionId: string,
  doc: PrescriptionDoc
): Promise<StoredPdf> {
  const empty: StoredPdf = { pdfPath: null, pdfSha256: null, pdfStoredAt: null };

  if (doc.pdfPath) return { pdfPath: doc.pdfPath, pdfSha256: doc.pdfSha256 ?? null, pdfStoredAt: doc.pdfStoredAt ?? null };

  try {
    const { bytes, sha256 } = await renderPrescriptionPdf(prescriptionId, doc);
    const path = prescriptionPdfPath(prescriptionId);

    await uploadImmutableObject(path, bytes, "application/pdf");

    const stored: StoredPdf = {
      pdfPath: path,
      pdfSha256: sha256,
      pdfStoredAt: Timestamp.now(),
    };

    // The digest is recorded alongside the prescription so a downloaded copy
    // can be checked against the record without trusting the file itself.
    await db().collection(C.prescriptions).doc(prescriptionId).update(stored);
    return stored;
  } catch (e) {
    // Logged with the id and nothing else: a prescription's contents are the
    // last thing that should end up in a log line.
    logger.error("Prescription PDF not stored", {
      prescriptionId,
      error: e instanceof Error ? e.message : "unknown",
    });
    return empty;
  }
}

/**
 * Retries prescriptions issued without a stored document.
 *
 * Bounded per run: a sweep that tries to repair ten thousand at once is a sweep
 * that times out and repairs none.
 */
export async function sweepMissingPrescriptionPdfs(limit = 50): Promise<number> {
  const snap = await db()
    .collection(C.prescriptions)
    .where("pdfPath", "==", null)
    .limit(limit)
    .get();

  let repaired = 0;
  for (const d of snap.docs) {
    const result = await storePrescriptionPdf(d.id, d.data() as PrescriptionDoc);
    if (result.pdfPath) repaired++;
  }

  if (repaired > 0) logger.info("Prescription PDFs repaired", { repaired });
  return repaired;
}
