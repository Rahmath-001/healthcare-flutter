# MiDoctor — launch readiness

Status of the app against what a public launch in India actually requires.

**The app cannot launch today**, but the reason has changed. The backend is
now built: all twelve surfaces have real endpoints, files have real storage, and
nothing is a fixture except provider credential capture. What remains is
overwhelmingly **accounts, legal artefacts and operational readiness** — the
things no amount of engineering substitutes for. Everything below marked 🔴 is a
hard blocker.

---

## 🔴 Hard blockers

### 1. Backend — done

Every repository resolves to a real API under `USE_FIXTURES=false`, credentials
included: document upload, registration number and TOTP enrolment are built and
the verification gate is enforced server-side. A doctor can complete
verification, and a supervisor can work the queue in the operator console.

Still missing:

- [ ] **Server-generated prescription PDF.** The client renders one locally and
      says so in its own header. A prescription is a legal document and must be
      server-generated, server-attested and WORM-stored. The verification
      endpoint (`GET /v1/rx/:code`) and a content-derived, keyed code both exist,
      so the remaining work is the document itself.
- [ ] **A real antivirus.** `scanForMalware` is a seam that returns clean. File
      *format* validation and EXIF stripping are implemented and tested; malware
      detection needs a vendor.
- [ ] **Appointment reminders.** The scheduler infrastructure exists; the
      notification transport does not (see push, below).
- [ ] **DigiLocker identity verification.** Stubbed, and deliberately returns an
      explicit "not connected" error rather than passing everyone — an identity
      check that silently succeeds is worse than none. A real integration is an
      OAuth flow against MeitY's partner API, which needs a registered client
      and a signed agreement: an account, not code. Until then a reviewer
      verifies identity manually.

Six things are impossible without server-side authority, and no amount of client
work substitutes for them:

| Capability | Why the client cannot do it |
|---|---|
| Consent revocation | If the provider's app decides whether it may read a record, revocation is theatre — a patched build simply stops asking. |
| No double-booking | Two patients on two phones cannot coordinate. |
| Provider approval | Otherwise a doctor approves themselves. |
| Drug-list enforcement | Client validation is advisory; a repackaged APK bypasses it. |
| Audit log | A tamper-evident log cannot live on the device being audited. |
| Records across devices | Phone lost, records gone. |

**Still minimum for a closed beta:** a way for an operator to work the
provider-approval queue (see below), and credential capture so there is
something to approve.

### 2. Accounts and credentials nobody but you can create

- [ ] **Firebase production project.** `healthcare-demo-645ed` is a demo and
      should be treated as burned. Needs billing, least-privilege IAM, audit
      logs, and API-key restrictions (Android apps + SHA-256; Identity Toolkit
      only).
- [ ] **Android upload keystore** + Play App Signing. Release builds currently
      fail closed without `android/key.properties` — deliberately.
- [ ] **Apple Developer Program.** No iOS build is possible without it.
- [ ] **100ms account.** The SDK is wired; the join token must be minted
      server-side because it is signed with the app secret. A secret shipped in
      the client would let anyone join any consultation.
- [ ] **Twilio** production credentials for the carrier check.

### 3. Legal and regulatory

None of this is optional for an Indian telemedicine product.

- [ ] **NMC / State Medical Council verification** of every provider before
      approval. The app models it; someone must actually perform the check.
- [x] **An operator console.** Built — `flutter run -d chrome -t lib/main_admin.dart`.
      Verification queue with in-page document review, account suspension and
      role assignment, rating moderation, and the support queue. The first admin
      is still bootstrapped out of band with `cd functions && pnpm grant-role`,
      because nothing in the API can mint one.
- [ ] **Somebody to staff it.** The console is a tool; NMC register lookups,
      escalation and record custody are an operating procedure that has to exist
      before a doctor is approved through it.
- [x] **HIPAA §164.312 technical safeguards implemented** — see
      [docs/SECURITY_AUDIT.md](docs/SECURITY_AUDIT.md). Automatic logoff, certificate
      pinning, memory-only web credentials, screenshot coverage, keyboard-dictionary
      leakage and clipboard expiry are all done and tested.
- [ ] **Populate the certificate pins** in `AppConfig._pinsFor` before any external
      release. Empty = pinning disabled. Always ship two — the live certificate and its
      successor — and follow the rotation runbook in `certificate_pinning_io.dart`.
- [ ] **Server-side: WORM prescription PDF and an `HttpOnly` refresh cookie for web.**
      The only two §164.312 items the client cannot close.
- [ ] **§164.308 / §164.310** — risk analysis, security official, training, sanctions,
      contingency plan, facility and device controls. Entirely organizational; no
      repository can satisfy them.
- [ ] **BAAs, not just DPAs**, with Google/Firebase, Twilio and 100ms — *if* HIPAA is
      actually in scope. Decide whether US patients are, because it also decides the
      Firebase Auth residency question below.
- [ ] **DPDP Act 2023** — published privacy notice, appointed grievance officer
      (`grievance@midoctor.in` is currently a placeholder), breach-notification
      runbook, processing register.
- [ ] **Data Processing Agreements** with 100ms, Twilio, Google/Firebase.
- [ ] **Firebase Auth stores identity data outside India.** Domain data is
      India-resident by design; the identity provider is not. This is a
      residency decision that needs a documented answer.
- [ ] **Hindi legal copy** — the consent and privacy strings are deliberately
      untranslated. See `lib/l10n/README.md`. Machine-translated consent is not
      consent.
- [ ] **Telemedicine Practice Guidelines** — the app enforces the drug lists and
      displays registration numbers, but the operating protocol (who is on call,
      escalation, record custody) is an operational document, not code.

### 4. Payments

Deferred by decision. `BookingPolicy.requiresPayment()` returns `false` and
bookings confirm unpaid. Before enabling:

- [ ] Choose a gateway. **Stripe (FR-PAY-002) is likely wrong for INR domestic
      collection**; Razorpay/Cashfree/PhonePe are the practical options, and UPI
      is non-negotiable for Indian consumers.
- [ ] RBI payment-aggregator position — money flowing patient → platform →
      doctor needs a licence or a licensed partner with a nodal account.
- [ ] GST, invoicing, TDS 194J on professional payouts.
- [ ] Cancellation/refund policy. The 24-hour free window in
      `Appointment.freeCancellationWindow` is a placeholder with no business
      authority behind it.

---

## 🟡 Built, but needs real-world validation

- **Telemedicine.** 100ms is wired behind `TelehealthProvider`; never tested
  against a live room. Needs two-device testing on real Indian mobile networks,
  including the audio fallback.
- **File upload.** End to end now: pick, PUT to a signed URL, quarantine,
  magic-byte verification, EXIF stripping, promotion, signed download, and an
  in-app viewer that keeps the file inside `ProtectedScreen`. Never exercised
  against a real bucket.
- **Prescription PDF.** Renders and shares correctly, including Devanagari. It
  is explicitly a stand-in — a prescription is a legal document and must be
  server-generated, server-attested and WORM-stored. The verification code it
  prints is generated on the device and no endpoint can check it.
- **iOS.** `Info.plist` and usage strings are complete, but the project has
  never been compiled on macOS. Budget a day for the SwiftPM/CocoaPods question
  (WebRTC plugins may force a Podfile).
- **Push notifications.** Still not built, and now the last piece blocking
  appointment reminders — the scheduler that would send them exists. The
  manifests already claim the capability: `POST_NOTIFICATIONS` on Android and
  `UIBackgroundModes: remote-notification` on iOS, the latter still missing the
  `aps-environment` entitlement that would make it work.
- **Localisation.** About two thirds done: ~470 English keys, ~455 Hindi, and the
  screens read them. Roughly 100 literals remain in the app, and the operator
  console is deliberately English-only. LEGAL COPY stays untranslated by policy.
- **Payments.** Deferred by decision; see below. `payment.dart` is 137 lines of
  dead code with no importers and should be deleted or wired.
- **Deep links.** Now configured — Android App Links on `midoctor.in/app` and
  `/rx`, iOS `associated-domains`. Both need their verification files hosted
  (`assetlinks.json`, `apple-app-site-association`) before they stop showing a
  chooser, and no route parses an incoming link yet.

---

## 🟢 Done and verified

- 208 Flutter tests and 47 API tests; `flutter analyze --fatal-infos` clean
  under `strict-casts`, `strict-raw-types`, `strict-inference`; debug, R8 release
  and **web release** builds all green and verified locally. The workflows were
  committed for the first time with this work, so CI has only just begun
  running — its results have not been reviewed here.
- The `USE_FIXTURES=false` network path is covered: `api_repository_test.dart`
  asserts the wire contract of every API-backed repository.
- Crash reporting, with PHI deliberately stripped — only failure kind and
  machine code are forwarded, and breadcrumbs are route names.
- Release signing fails closed without a keystore; R8 minification enabled.
- Access tokens memory-only; refresh tokens in Keychain/Keystore with rotation
  and reuse detection. Logout and reuse detection now also invalidate the
  outstanding access token by bumping `permissionVersion`.
- Rate limiting on the two unauthenticated auth endpoints.
- Account suspension and role assignment exist and are scope-gated; a slot hold
  is validated against a real availability rule; a consent grant resolves the
  provider from the directory rather than from the request body.
- Role-aware routing covering all 7 roles and all 9 provider statuses (21 tests).
- Consent: mandatory expiry, 180-day ceiling, one-tap revoke, access log
  including denials.
- Telemedicine drug lists enforced; prohibited drugs blocked on every path.
- Screenshot/recording blocked on records, prescriptions, sharing and
  consultation screens; the record viewer renders in-app rather than handing the
  file to a browser, so a document never leaves that boundary.
- Uploads land in quarantine, are identified by magic bytes, have EXIF stripped,
  and are unreadable until promoted. Covered by tests.
- Telemedicine drug lists enforced **server-side**, re-resolved by drug id, with
  follow-up status derived from appointment history rather than asserted.
- Telemedicine consent records store a SHA-256 of the exact text shown, with a
  version — so the record attests to what was agreed, not merely that something
  was.
- Provider MFA (TOTP) implemented and tested against the RFC 6238 vectors, and
  enforced as part of the verification gate rather than offered afterwards.
- The operator console refuses patients and providers, and its roles are
  asserted to be the exact complement of the app's.
- In-app account deletion and data export are real: erasure revokes every
  consent grant, cancels upcoming appointments, destroys all sessions and
  deactivates the account, while recording the statutory retention date for the
  clinical tail it deliberately keeps.
- Legacy plaintext health data purged from SharedPreferences on upgrade.
- No Aadhaar image or number is stored anywhere — identity is DigiLocker.
- CI: analyze, test, l10n drift, debug APK, iOS compile, gitleaks, osv-scanner,
  CodeQL.

---

## App size — matters more here than usual

Adding the 100ms SDK took the release build from 62 MB to 97 MB. Almost all of
it is WebRTC native code:

| ABI | Native libs |
|---|---|
| arm64-v8a | 31.0 MB |
| armeabi-v7a | 25.7 MB |
| x86_64 | 35.3 MB |

**Ship the App Bundle, not the universal APK.** The AAB is 79.9 MB but Play
delivers only the matching ABI, so a real arm64 download is roughly 40 MB rather
than 97 MB. `.github/workflows/release-android.yml` builds `appbundle` on a `v*`
tag, restores the keystore from secrets, refuses a debug-signed artifact, and
keeps the R8 mapping file as an artifact.

This is worth watching rather than ignoring: in India, install size and mobile
data both convert directly into drop-off. If it needs to come down further,
excluding `x86_64` from release (emulators and some Chromebooks only) is the
cheapest single cut.

## Store submission (after the blockers)

- [ ] Rename `applicationId` to `in.midoctor.app` — **immutable after first
      publish**, and must land with the fresh Firebase project.
- [ ] Play Data Safety form + Health apps declaration.
- [ ] App Store privacy labels; Apple mandates in-app account deletion (built).
- [ ] App icons and store screenshots (currently the Flutter default icon).
- [ ] Third-party penetration test.
- [x] Custom launcher icon — generated from one source by `tool/make_icon.py`,
      applied to Android (incl. adaptive), iOS and web.
- [ ] iOS `CFBundleDisplayName` still reads "Healthcare Mobile".
- [ ] Host `assetlinks.json` and `apple-app-site-association` on `midoctor.in`,
      and add routes that parse an incoming deep link.
- [ ] Load-test booking concurrency against the exclusion constraint.
