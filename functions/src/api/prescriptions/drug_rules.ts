import { Problem } from "../errors";

/**
 * Telemedicine drug lists, MoHFW Telemedicine Practice Guidelines 2020.
 *
 * **This is the enforcement point.** The Flutter client has the same table and
 * uses it to disable options with a reason, which is a good experience and no
 * protection at all: a repackaged APK simply sends the request anyway. A rule
 * that only exists in the client binds honest doctors and nobody else.
 *
 * The lists are a legal constraint, not a product preference, and the seeded
 * catalogue is not a complete formulary — a real deployment loads the current
 * schedule from a maintained source. What matters structurally is that the
 * decision is made here.
 */
export type DrugList = "LIST_O" | "LIST_A" | "LIST_B" | "PROHIBITED";

export interface DrugDoc {
  name: string;
  genericName: string;
  form: string;
  telemedicineList: DrugList;
  commonStrengths: string[];
  /** Lowercased tokens, so a prefix search can be indexed. */
  searchTerms: string[];
}

/**
 * Whether a drug may be prescribed on this consultation.
 *
 * List B is refill-only: permitted at an established follow-up, refused on a
 * first contact. Prohibited is never permitted, on any consultation, by anyone.
 */
export function isPrescribableOn(list: DrugList, isFollowUp: boolean): boolean {
  switch (list) {
    case "PROHIBITED":
      return false;
    case "LIST_B":
      return isFollowUp;
    case "LIST_O":
    case "LIST_A":
      return true;
  }
}

export function blockedReason(list: DrugList, isFollowUp: boolean): string | null {
  if (list === "PROHIBITED") {
    return "cannot be prescribed in a teleconsultation";
  }
  if (list === "LIST_B" && !isFollowUp) {
    return "can only be re-prescribed at a follow-up consultation";
  }
  return null;
}

/** Refuses the whole prescription unless every item is permitted. */
export function assertPrescribable(
  items: { drugName: string; list: DrugList }[],
  isFollowUp: boolean
): void {
  const blocked = items
    .map((item) => ({ item, reason: blockedReason(item.list, isFollowUp) }))
    .filter((x): x is { item: { drugName: string; list: DrugList }; reason: string } =>
      x.reason !== null
    );

  if (blocked.length === 0) return;

  throw new Problem(
    422,
    "DRUG_NOT_PRESCRIBABLE",
    "Medicine not permitted",
    blocked.map(({ item, reason }) => `${item.drugName} ${reason}.`).join(" "),
    Object.fromEntries(blocked.map(({ item, reason }) => [item.drugName, reason]))
  );
}
