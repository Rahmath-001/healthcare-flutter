import { describe, expect, it } from "vitest";

import type { ProviderStatus, Role } from "../db";
import { hasScope, resolveRequestedRole, scopesFor } from "./scopes";

/**
 * The RBAC matrix.
 *
 * This table is the authority — the Flutter fixture mirrors it, and every
 * endpoint checks against it. A wrong entry here does not fail loudly; it
 * quietly grants somebody access to a stranger's medical records.
 */
describe("scopesFor", () => {
  it("gives a patient the rights over their own data and nothing else", () => {
    const scopes = scopesFor("PATIENT", "NOT_APPLICABLE");
    expect(scopes).toContain("records:read_own");
    expect(scopes).toContain("consent:revoke");
    expect(scopes).not.toContain("records:read_granted");
    expect(scopes).not.toContain("prescription:write");
    expect(scopes).not.toContain("provider:approve");
  });

  it("collapses an unapproved provider to almost nothing", () => {
    const statuses: ProviderStatus[] = [
      "DRAFT",
      "SUBMITTED",
      "UNDER_REVIEW",
      "REJECTED",
      "RESUBMIT_REQUESTED",
      "SUSPENDED",
      "DEACTIVATED",
      "NOT_APPLICABLE",
    ];

    for (const status of statuses) {
      const scopes = scopesFor("PROVIDER", status);
      expect(scopes, status).toEqual(["profile:read", "credentials:submit"]);
      // The whole point of verification: no unapproved doctor can reach a
      // patient record or issue a prescription, whatever the UI shows.
      expect(scopes, status).not.toContain("records:read_granted");
      expect(scopes, status).not.toContain("prescription:write");
      expect(scopes, status).not.toContain("consultation:host");
    }
  });

  it("only APPROVED unlocks the provider's real scope set", () => {
    const scopes = scopesFor("PROVIDER", "APPROVED");
    expect(scopes).toContain("prescription:write");
    expect(scopes).toContain("records:read_granted");
    expect(scopes).toContain("consultation:host");
    expect(scopes).toContain("availability:write");
  });

  it("never gives a provider the power to approve themselves", () => {
    for (const status of ["DRAFT", "APPROVED"] as ProviderStatus[]) {
      const scopes = scopesFor("PROVIDER", status);
      expect(scopes, status).not.toContain("provider:approve");
      expect(scopes, status).not.toContain("provider:review");
      expect(scopes, status).not.toContain("user:set_role");
    }
  });

  it("limits a hospital account to its own organisation record", () => {
    const scopes = scopesFor("HOSPITAL", "NOT_APPLICABLE");
    expect(scopes).toEqual(["profile:read", "hospital:read_own"]);
    expect(scopes).not.toContain("provider:approve");
    expect(scopes).not.toContain("records:read_granted");
  });

  it("lets a supervisor act on providers but not on patient data", () => {
    const scopes = scopesFor("SUPERVISOR", "NOT_APPLICABLE");
    expect(scopes).toContain("provider:approve");
    // A supervisor who can approve a doctor must be able to stop one.
    expect(scopes).toContain("user:suspend");
    expect(scopes).not.toContain("records:read_own");
    expect(scopes).not.toContain("records:read_granted");
    // Role assignment is the most dangerous call in the API: admin only.
    expect(scopes).not.toContain("user:set_role");
  });

  it("gives support no access to clinical data", () => {
    for (const role of ["SUPPORT_L1", "SUPPORT_L2"] as Role[]) {
      const scopes = scopesFor(role, "NOT_APPLICABLE");
      expect(scopes, role).not.toContain("records:read_own");
      expect(scopes, role).not.toContain("records:read_granted");
      expect(scopes, role).not.toContain("prescription:read_own");
    }
  });

  it("leaves an unassigned account able to do nothing but read itself", () => {
    expect(scopesFor("UNASSIGNED", "NOT_APPLICABLE")).toEqual(["profile:read"]);
  });
});

describe("hasScope", () => {
  it("matches exactly, not by prefix", () => {
    expect(hasScope(["records:read_own"], "records:read_own")).toBe(true);
    expect(hasScope(["records:read_own"], "records:read_granted")).toBe(false);
    expect(hasScope(["records:read"], "records:read_own")).toBe(false);
  });

  it("treats the admin wildcard as everything", () => {
    expect(hasScope(["*:*"], "provider:approve")).toBe(true);
    expect(hasScope(["*:*"], "anything:at_all")).toBe(true);
  });

  it("is false for an empty scope set", () => {
    expect(hasScope([], "profile:read")).toBe(false);
  });
});

describe("resolveRequestedRole", () => {
  it("honours the only two roles a client may ask for", () => {
    expect(resolveRequestedRole("PROVIDER")).toBe("PROVIDER");
    expect(resolveRequestedRole("PATIENT")).toBe("PATIENT");
  });

  it("refuses every privileged role, however it is asked for", () => {
    // If a client could request SUPERVISOR, anyone could grant themselves
    // approval rights over doctors. The first admin is created out of band by
    // scripts/grant-role, never through sign-up.
    for (const attempt of [
      "ADMIN",
      "SUPERVISOR",
      "SUPPORT_L1",
      "SUPPORT_L2",
      "admin",
      "*:*",
      null,
      undefined,
      42,
      { role: "ADMIN" },
      ["ADMIN"],
    ]) {
      expect(resolveRequestedRole(attempt), String(attempt)).toBe("PATIENT");
    }
  });
});
