import { Router } from "express";
import { Timestamp } from "firebase-admin/firestore";

import { requireAuth, requireScope } from "../auth/middleware";
import { C, db, type PrescriptionTemplateDoc } from "../db";
import { handler, Problem } from "../errors";
import type { DrugDoc } from "./drug_rules";

/**
 * A doctor's saved prescribing sets.
 *
 * ## What is stored, and what is not
 *
 * Drug **ids** and doses. Never drug names, and never a telemedicine
 * classification. Both are read back out of the catalogue on every request, so
 * when the regulator moves a medicine to List B, every saved template
 * containing it starts refusing on first consultations that same day - no
 * migration, nothing to remember, and no stale copy to disagree with the
 * catalogue.
 *
 * A template also grants nothing. Applying one fills the composer; issuing
 * still goes through `assertPrescribable`, which re-resolves every item. A
 * template that carried its own permission would be a way to launder a drug
 * past a rule the doctor satisfied once, months ago, for a different patient.
 *
 * Templates are private to the doctor who saved them. There is deliberately no
 * sharing and no practice library: one clinician's set becoming another's
 * default is how a prescribing habit spreads without anybody deciding it
 * should.
 */

const MAX_NAME = 60;
const MAX_ITEMS = 20;
const MAX_TEMPLATES = 50;

interface IncomingItem {
  drugId: string;
  strength: string;
  frequency: string;
  durationDays: number;
  instructions?: string | null;
}

function parseItems(raw: unknown): IncomingItem[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw Problem.validation("Add at least one medicine.", {
      items: "required",
    });
  }
  if (raw.length > MAX_ITEMS) {
    throw Problem.validation(`A set can hold at most ${MAX_ITEMS} medicines.`, {
      items: "too_many",
    });
  }

  return raw.map((entry) => {
    const e = entry as Record<string, unknown>;
    const drugId = typeof e.drugId === "string" ? e.drugId.trim() : "";
    const strength = typeof e.strength === "string" ? e.strength.trim() : "";
    const frequency = typeof e.frequency === "string" ? e.frequency.trim() : "";
    const durationDays = Number(e.durationDays);

    // A drug id is what makes an item re-checkable. One without it could never
    // be validated against the drug lists again, which is precisely the hole a
    // template must not open.
    if (!drugId || !strength || !frequency) {
      throw Problem.validation("Each medicine needs a drug, a strength and a frequency.", {
        items: "incomplete",
      });
    }
    if (!Number.isInteger(durationDays) || durationDays < 1 || durationDays > 365) {
      throw Problem.validation("Duration must be between 1 and 365 days.", {
        durationDays: "out_of_range",
      });
    }

    return {
      drugId,
      strength,
      frequency,
      durationDays,
      instructions:
        typeof e.instructions === "string" && e.instructions.trim()
          ? e.instructions.trim()
          : null,
    };
  });
}

/** Fills a stored template out of the catalogue as it stands right now. */
async function hydrate(id: string, doc: PrescriptionTemplateDoc) {
  const ids = [...new Set(doc.items.map((i) => i.drugId))];
  const snaps = await Promise.all(
    ids.map((drugId) => db().collection(C.drugs).doc(drugId).get())
  );
  const drugs = new Map<string, DrugDoc>();
  snaps.forEach((snap, i) => {
    if (snap.exists) drugs.set(ids[i], snap.data() as DrugDoc);
  });

  return {
    id,
    name: doc.name,
    diagnosis: doc.diagnosis ?? null,
    advice: doc.advice ?? null,
    createdAt: doc.createdAt.toDate().toISOString(),
    items: doc.items.flatMap((i) => {
      const drug = drugs.get(i.drugId);
      // A medicine withdrawn from the catalogue drops out of the template
      // rather than appearing with a stale name and no classification.
      if (!drug) return [];
      return [
        {
          drugId: i.drugId,
          drugName: drug.name,
          genericName: drug.genericName,
          form: drug.form,
          strength: i.strength,
          frequency: i.frequency,
          durationDays: i.durationDays,
          instructions: i.instructions,
          telemedicineList: drug.telemedicineList,
        },
      ];
    }),
  };
}

export function prescriptionTemplateRoutes(secret: () => string): Router {
  const r = Router();
  r.use(requireAuth(secret));
  // Saving a set of medicines is an act of prescribing preparation, so it sits
  // behind the same scope as writing one. A doctor who may not prescribe has
  // nothing to save a set for.
  r.use(requireScope("prescription:write"));

  /** `GET /v1/prescriptions/templates` */
  r.get(
    "/",
    handler(async (req, res) => {
      const doctorId = req.user!.doctorId;
      if (!doctorId) throw Problem.forbidden("NOT_A_PROVIDER", "Not a provider.");

      const snap = await db()
        .collection(C.prescriptionTemplates)
        .where("doctorId", "==", doctorId)
        .orderBy("createdAt", "desc")
        .get();

      const out = await Promise.all(
        snap.docs.map((d) => hydrate(d.id, d.data() as PrescriptionTemplateDoc))
      );
      res.json(out);
    })
  );

  /** `POST /v1/prescriptions/templates` */
  r.post(
    "/",
    handler(async (req, res) => {
      const doctorId = req.user!.doctorId;
      if (!doctorId) throw Problem.forbidden("NOT_A_PROVIDER", "Not a provider.");

      const name = typeof req.body?.name === "string" ? req.body.name.trim() : "";
      if (!name) throw Problem.validation("Give the set a name.", { name: "required" });
      if (name.length > MAX_NAME) {
        throw Problem.validation("That name is too long.", { name: "too_long" });
      }

      const items = parseItems(req.body?.items);

      // Every drug must exist. Checked before the write rather than tolerated
      // on read, so a typo is a refusal now instead of a set that silently
      // loses a medicine later.
      const unknown: string[] = [];
      await Promise.all(
        [...new Set(items.map((i) => i.drugId))].map(async (drugId) => {
          const snap = await db().collection(C.drugs).doc(drugId).get();
          if (!snap.exists) unknown.push(drugId);
        })
      );
      if (unknown.length) {
        throw Problem.validation("One of those medicines is not in the catalogue.", {
          items: "unknown_drug",
        });
      }

      const existing = await db()
        .collection(C.prescriptionTemplates)
        .where("doctorId", "==", doctorId)
        .get();

      if (existing.size >= MAX_TEMPLATES) {
        throw Problem.conflict(
          "TEMPLATE_LIMIT",
          `You can save at most ${MAX_TEMPLATES} sets.`
        );
      }
      if (
        existing.docs.some(
          (d) =>
            (d.data() as PrescriptionTemplateDoc).name.toLowerCase() ===
            name.toLowerCase()
        )
      ) {
        throw Problem.conflict("TEMPLATE_NAME_TAKEN", "You already have a set with that name.");
      }

      const doc: PrescriptionTemplateDoc = {
        doctorId,
        name,
        diagnosis:
          typeof req.body?.diagnosis === "string" && req.body.diagnosis.trim()
            ? req.body.diagnosis.trim()
            : null,
        advice:
          typeof req.body?.advice === "string" && req.body.advice.trim()
            ? req.body.advice.trim()
            : null,
        items,
        createdAt: Timestamp.now(),
      };

      const ref = await db().collection(C.prescriptionTemplates).add(doc);
      res.status(201).json(await hydrate(ref.id, doc));
    })
  );

  /** `DELETE /v1/prescriptions/templates/:id` */
  r.delete(
    "/:id",
    handler(async (req, res) => {
      const doctorId = req.user!.doctorId;
      if (!doctorId) throw Problem.forbidden("NOT_A_PROVIDER", "Not a provider.");

      const ref = db().collection(C.prescriptionTemplates).doc(req.params.id);
      const snap = await ref.get();
      // Same answer whether it never existed or belongs to another doctor:
      // distinguishing them would report whose ids are real.
      if (!snap.exists || (snap.data() as PrescriptionTemplateDoc).doctorId !== doctorId) {
        throw Problem.notFound("TEMPLATE_NOT_FOUND", "Not found.");
      }

      await ref.delete();
      res.json({ id: req.params.id, deleted: true });
    })
  );

  return r;
}
