# HIPAA Security Rule §164.312 — technical safeguards

**Date:** 2026-08-21 · **Scope:** the Flutter client (`lib/`) and its platform
configuration. The API (`functions/`) is referenced where the client depends on
it, but has not been audited line by line here.

**Status: every §164.312 technical safeguard that a mobile client can implement
is implemented.** What remains is server-side or organizational, and is listed
explicitly in [What is still required](#what-is-still-required) — not as a
hedge, but because those items are the difference between "the app does its
part" and "the organization is compliant", and someone has to own them.

### A note on jurisdiction, recorded once

HIPAA is US law binding US covered entities and their business associates. This
product is India-facing, where the **DPDP Act 2023** (§8(5) safeguards, §8(6)
breach notification), the **Telemedicine Practice Guidelines 2020** and the
**SPDI Rules 2011** are what bind it. The controls below satisfy both — §164.312
is a stricter, more specific checklist than DPDP's "reasonable security
safeguards", so building to it satisfies DPDP as a side effect. Nothing here is
wasted work under either regime.

If US patients or a US covered-entity relationship are actually in scope, two
things follow that code cannot deliver: **BAAs** (not DPAs) with Google/Firebase,
Twilio and 100ms, and a decision about Firebase Auth storing identity data
outside India.

---

## §164.312(a)(1) Access control

| Implementation specification | Status | Evidence |
| --- | --- | --- |
| **(a)(2)(i)** Unique user identification — *required* | **Met** | Server-issued session carrying `userId`/`sessionId`; authorization never reads Firebase — [session.dart](../lib/core/session/session.dart) |
| **(a)(2)(ii)** Emergency access — *required* | **Server-side** | Break-glass is an operator procedure. The console deliberately has no such mode; adding one client-side would be a bypass, not a safeguard. |
| **(a)(2)(iii)** Automatic logoff — *addressable* | **Met** | [inactivity_timeout.dart](../lib/core/security/inactivity_timeout.dart) — 15 min, resets on pointer input, measures backgrounded time against the wall clock because iOS suspends the process. Tested: `test/inactivity_timeout_test.dart` |
| **(a)(2)(iv)** Encryption and decryption — *addressable* | **Met** | Access token memory-only; refresh token in iOS Keychain / Android KeyStore (AES-GCM under an RSA-OAEP-wrapped key) — [secure_token_store.dart](../lib/core/storage/secure_token_store.dart). **On web, credentials are memory-only** and never touch `localStorage`. |

Authorization is role- and scope-based across 7 roles, with `permissionVersion`
forcing re-evaluation on every authorization change — [user_role.dart](../lib/core/session/user_role.dart).

## §164.312(b) Audit controls — *required*

**Met, server-side, and deliberately not client-side.** `logAccess` writes an
append-only record of every record read **including denials** —
`functions/src/api/consent/access.ts`. A client-side audit log is evidence the
audited party can edit, which is not evidence. The client's obligation is to not
weaken it, and it does not.

## §164.312(c)(1) Integrity

| Implementation specification | Status | Evidence |
| --- | --- | --- |
| **(c)(2)** Mechanism to authenticate ePHI — *addressable* | **Met in transit** | TLS with certificate pinning (below); uploads PUT to a signed URL, land in `quarantine/`, and are promoted only after magic-byte confirmation and EXIF stripping |
| Consent text integrity | **Met** | The exact string and version are transmitted and SHA-256'd server-side — [consent_text.dart](../lib/features/consultation/domain/consent_text.dart) |
| Prescription integrity | **Open — server-side** | The PDF is rendered client-side and says so. See [What is still required](#what-is-still-required). |

## §164.312(d) Person or entity authentication — *required*

**Met.** Firebase (Google / Apple / India phone OTP) proves identity; the
MiDoctor session proves authorization. Providers additionally require TOTP MFA
before `submitForReview()`. There is no email/password path to weaken.

The MFA enrolment screen's two credentials — the TOTP seed and the recovery
codes — are now screenshot-protected and expire off the clipboard after 60
seconds ([sensitive_clipboard.dart](../lib/shared/sensitive_clipboard.dart)).
A recovery code is a permanent second-factor bypass; leaving one in a shared
buffer indefinitely, or in the gallery, defeats the factor entirely.

## §164.312(e)(1) Transmission security

| Implementation specification | Status | Evidence |
| --- | --- | --- |
| **(e)(2)(i)** Integrity controls — *addressable* | **Met** | TLS; cleartext refused with no exception domain — [network_security_config.xml](../android/app/src/main/res/xml/network_security_config.xml), `usesCleartextTraffic="false"` |
| **(e)(2)(ii)** Encryption — *addressable* | **Met** | TLS everywhere; iOS ATS left at its secure default (no `NSAppTransportSecurity` key) |
| Certificate pinning | **Met on mobile** | [certificate_pinning_io.dart](../lib/core/network/certificate_pinning_io.dart) — leaf pin layered **on top of** normal chain validation, with backup pins and a kill switch. Tested: `test/certificate_pinning_test.dart` |

> **Pinning requires one action before external release.**
> `AppConfig._pinsFor` returns an empty set for staging and prod, which disables
> pinning. Populate it from the deployed certificate, and always keep two pins —
> the live certificate and its successor. The rotation runbook is in
> `certificate_pinning_io.dart`. A pin is the only control that can permanently
> brick an installed fleet; that is why the kill switch exists and why the value
> is deliberately separate from the mechanism.

---

## Beyond §164.312: mobile-specific exposure

The Security Rule predates smartphones. These are where health data on a phone
actually leaks.

| Control | Status |
| --- | --- |
| Cloud backup / device transfer | **Met** — `allowBackup="false"` plus [data_extraction_rules.xml](../android/app/src/main/res/xml/data_extraction_rules.xml) excluding every domain |
| Screenshot / screen recording | **Met on Android + iOS** — `FLAG_SECURE` / blur-on-resign, now **reference-counted and visibility-driven** so a shell tab actually releases it (see below). Covers records, prescriptions, sharing, consultation, appointment detail, prescribe, edit-profile and MFA enrolment. No-op on web. |
| PHI in crash reports | **Met** — only `FailureKind` + machine code is forwarded, never `Failure.message`; breadcrumbs are route names |
| PHI in device logs | **Met** — `avoid_print` is an error, and every `debugPrint` is behind `kDebugMode`. Note `debugPrint` is **not** stripped from release builds; the guard is the control. |
| Keyboard dictionary caching | **Met** — `autocorrect`/`enableSuggestions` off on every clinical free-text field. Without it, typing a drug or diagnosis trains the OS personal dictionary, which then suggests it **in other apps**. |
| Credentials on the clipboard | **Met** — 60-second expiry with a value check, so the user's own later copy is not wiped |
| Clinical data in plaintext local storage | **Met** — `SharedPreferences` holds one onboarding boolean; `purgeLegacyHealthData()` wipes the legacy age/blood-group keys on upgrade |
| App-level PIN / biometric re-entry | **Not implemented** — deliberate, see below |

### Two defects found and fixed during this audit

Both failed *safe*, which is why neither would have been noticed:

1. **`ProtectedScreen` never released.** Records and Prescriptions are
   `StatefulShellRoute.indexedStack` branches, which are never disposed once
   visited — so `FLAG_SECURE` latched on for the life of the process and the
   release path never ran at all. Now reference-counted and driven by
   `TickerMode` visibility, which is exactly the signal go_router uses for an
   inactive branch. Tested: `test/screen_protection_test.dart`.
2. **The inactivity timeout read the session cold.** The first implementation
   checked for a session only when the timer fired, caught it mid-restore in its
   loading state, treated that as "nobody is signed in", and never re-armed —
   leaving the window open for the rest of the process. It now arms off
   `currentSessionProvider`.

### Why there is no biometric lock

Automatic logoff is the required control and it is implemented. A biometric
re-entry gate is a usability improvement on top of it, not an additional
safeguard — §164.312(d) is satisfied by the sign-in. Adding `local_auth` forces
`MainActivity` to `FlutterFragmentActivity`, which interacts with the 100ms,
camera and file-picker plugins in ways that need testing on real devices. That
is a deliberate deferral with a stated reason, not an oversight; it is worth
doing when there is a device lab to prove it.

---

## What is still required

Code cannot close these. They are listed so they can be assigned.

### Server-side

1. **Prescription integrity** — a server-generated, WORM-stored PDF.
   §164.312(c)(2). A prescription the client composes is one the client can
   alter.
2. **`HttpOnly` refresh cookie for web.** The client-side mitigation above
   (memory-only credentials, so a tab reload signs you out) removes the XSS
   exfiltration path but costs session persistence. The real fix is a same-site
   `HttpOnly` cookie the API issues, which script cannot read at all.
3. **Populate the certificate pins** before external release, per the runbook.

### Organizational — the majority of the Rule

§164.312 is one of three safeguard sets. **§164.308 (administrative)** and
**§164.310 (physical)** are entirely organizational, and no repository can
satisfy them:

- Security risk analysis and risk management plan — §164.308(a)(1)
- Assigned security official — §164.308(a)(2)
- Workforce training and sanction policy — §164.308(a)(5)
- Contingency plan: backup, disaster recovery, emergency mode — §164.308(a)(7)
- **BAAs** with every processor that touches ePHI — §164.308(b)(1). Under DPDP
  these are DPAs and are already tracked in
  [LAUNCH_CHECKLIST.md](../LAUNCH_CHECKLIST.md); under HIPAA a DPA is not
  sufficient.
- Breach notification procedures — §164.404 *et seq.* (DPDP §8(6) in India)
- Facility access, workstation use and security, device and media disposal —
  §164.310

## What this audit did not cover

- `functions/` line by line, and the Firestore transaction paths that need the
  emulator to exercise at all.
- Penetration testing, and dependency CVEs beyond what `security.yml` already
  runs (gitleaks, osv-scanner, CodeQL).
