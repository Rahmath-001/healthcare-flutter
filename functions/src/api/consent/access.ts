import { randomUUID } from "crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import {
  C,
  db,
  type AccessEventDoc,
  type ConsentGrantDoc,
  type MedicalRecordDoc,
} from "../db";

/**
 * Consent evaluation and the access log.
 *
 * Shared between the consent routes and the records routes so there is exactly
 * one implementation of "may this provider read this record". A second, subtly
 * different one is how consent expiry stops meaning anything.
 */

/** Appends to the access log. Never updates, never deletes. */
export async function logAccess(event: AccessEventDoc): Promise<void> {
  await db().collection(C.accessLog).doc(randomUUID()).set(event);
}

export interface ResolvedGrant {
  id: string;
  grant: ConsentGrantDoc;
}

/**
 * The live grant letting [providerId] read [patientId]'s records, if any.
 *
 * "Live" means granted, not revoked, and not expired — checked against the
 * clock on every call rather than trusted from a status field, because an
 * expiry that is only evaluated when something remembers to evaluate it is not
 * an expiry.
 *
 * Returns the grant with the **narrowest** scope that is still live, so a
 * patient who granted access to two specific records and later granted
 * ALL_RECORDS does not silently widen the first consultation's reach.
 */
export async function activeGrantFor(
  providerId: string,
  patientId: string
): Promise<ResolvedGrant | null> {
  const now = Timestamp.now();

  const snap = await db()
    .collection(C.consentGrants)
    .where("patientId", "==", patientId)
    .where("providerId", "==", providerId)
    .get();

  const live = snap.docs
    .map((d) => ({ id: d.id, grant: d.data() as ConsentGrantDoc }))
    .filter(
      ({ grant }) => !grant.revokedAt && grant.expiresAt.toMillis() > now.toMillis()
    );

  if (live.length === 0) return null;

  const rank = { SPECIFIC_RECORDS: 0, RECORD_TYPES: 1, ALL_RECORDS: 2 } as const;
  live.sort((a, b) => rank[a.grant.scopeKind] - rank[b.grant.scopeKind]);
  return live[0]!;
}

/** Whether a specific record falls inside a grant's scope. */
export function grantCovers(grant: ConsentGrantDoc, recordId: string, record: MedicalRecordDoc) {
  switch (grant.scopeKind) {
    case "ALL_RECORDS":
      return true;
    case "SPECIFIC_RECORDS":
      return grant.recordIds.includes(recordId);
    case "RECORD_TYPES":
      return grant.recordTypeLabels.includes(record.type);
  }
}

/**
 * Records a use of a grant.
 *
 * The counter is what lets a patient see that a grant they forgot about is
 * being exercised, which is usually the first sign something is wrong.
 */
export async function noteGrantUse(grantId: string): Promise<void> {
  await db()
    .collection(C.consentGrants)
    .doc(grantId)
    .update({ usesCount: FieldValue.increment(1) });
}
