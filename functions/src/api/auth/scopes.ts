import type { ProviderStatus, Role } from "../db";

/**
 * The RBAC matrix, server-side.
 *
 * This is the authority. The Flutter fixture in `FixtureSessionRepository`
 * mirrors it so that fixture-backed screens gate identically, but a client copy
 * of a permission table is a convenience for the UI, never a control — every
 * endpoint re-checks the scope it needs against the token it was given.
 */
const PATIENT_SCOPES = [
  "profile:read",
  "profile:write",
  "doctor:search",
  "appointment:create",
  "appointment:cancel",
  "records:read_own",
  "records:write_own",
  "consent:grant",
  "consent:revoke",
  "consent:view_log",
  "prescription:read_own",
  "consultation:join",
  "rating:write",
  "support:ticket_create",
] as const;

const APPROVED_PROVIDER_SCOPES = [
  "profile:read",
  "profile:write_limited",
  "availability:write",
  "appointments:read_own",
  "records:read_granted",
  "records:request_access",
  "prescription:write",
  "consultation:host",
  "consultation:join",
  "ratings:read_own",
] as const;

/**
 * A provider who is not APPROVED may do exactly two things: read their own
 * profile and submit credentials.
 *
 * This is the whole reason provider verification is a *status* rather than a
 * second role — the scope set collapses to almost nothing until a supervisor
 * approves, and there is no path by which an unapproved doctor can see a
 * patient record or issue a prescription.
 */
const UNVERIFIED_PROVIDER_SCOPES = [
  "profile:read",
  "credentials:submit",
] as const;

const SUPERVISOR_SCOPES = [
  "profile:read",
  "provider:review",
  "provider:approve",
  "provider:reject",
  // A supervisor who can approve a doctor must also be able to stop one. The
  // approval decision is worthless if the only way to undo it is a database
  // edit.
  "user:suspend",
] as const;

const SUPPORT_L1_SCOPES = ["profile:read", "support:ticket_read"] as const;

const SUPPORT_L2_SCOPES = [
  "profile:read",
  "support:ticket_read",
  "support:ticket_escalate",
] as const;

export function scopesFor(role: Role, providerStatus: ProviderStatus): string[] {
  switch (role) {
    case "PATIENT":
      return [...PATIENT_SCOPES];
    case "PROVIDER":
      return providerStatus === "APPROVED"
        ? [...APPROVED_PROVIDER_SCOPES]
        : [...UNVERIFIED_PROVIDER_SCOPES];
    case "SUPERVISOR":
      return [...SUPERVISOR_SCOPES];
    case "SUPPORT_L1":
      return [...SUPPORT_L1_SCOPES];
    case "SUPPORT_L2":
      return [...SUPPORT_L2_SCOPES];
    case "ADMIN":
      return ["*:*"];
    case "UNASSIGNED":
    default:
      return ["profile:read"];
  }
}

export function hasScope(scopes: string[], required: string): boolean {
  return scopes.includes("*:*") || scopes.includes(required);
}

/**
 * Roles a user may request for themselves at sign-up.
 *
 * FR-AUTH-002 allows exactly two. The other five are provisioned internally —
 * if a client could request SUPERVISOR, anyone could grant themselves approval
 * rights over doctors. `requestedRole` from the client is therefore treated as
 * a request and validated here, never trusted.
 */
export function resolveRequestedRole(requested: unknown): Role {
  return requested === "PROVIDER" ? "PROVIDER" : "PATIENT";
}
