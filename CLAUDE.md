# MiDoctor — Flutter mobile client

Indian telemedicine app. Two audiences in one binary: **patient** and **provider (doctor)**.

Package name: `healthcare_mobile`. Product name: **MiDoctor**. Repo root is a Flutter app;
`functions/` is the **MiDoctor API** — a TypeScript Express app on Cloud Functions, plus the
Twilio carrier check. See [functions/README.md](functions/README.md).

**Backend status: every surface built.** `USE_FIXTURES=false` swaps all thirteen
repositories to API-backed implementations — auth/session, patient profile, doctors, booking,
appointments, consent, records (with real object storage), prescriptions, credentials,
availability, ratings, support and consultation. See
[lib/core/feature_providers.dart](lib/core/feature_providers.dart).

The fixtures are not scaffolding to delete, and they are no longer per-repository. Every one
of them reads and writes a single in-memory store,
[`FixtureBackend`](lib/core/fixtures/fixture_backend.dart) — see the Sample data section.

**Three clients, two binaries.** Patient and provider share `lib/main.dart`; supervisors,
admins and support staff use the **operator console** at `lib/main_admin.dart`. The console
is a separate entry point rather than a third shell — see the Operator console section below.
The first admin is created with `pnpm grant-role`; nothing in the API can mint one.

---

## Stack

| Concern | Choice |
| --- | --- |
| State | `flutter_riverpod` ^3.4 — no codegen (`riverpod_generator` is unusable on this Flutter version) |
| Routing | `go_router` ^17.5, hand-written paths, no `go_router_builder` |
| HTTP | `dio` ^5.11 behind an `ApiClient` wrapper |
| Identity | Firebase Auth (Google OAuth + India phone OTP). **No email/password.** |
| Authorization | MiDoctor server session (own JWT), *not* Firebase |
| Secure storage | `flutter_secure_storage` ^11 (Keychain / EncryptedSharedPreferences) |
| Telehealth | `hmssdk_flutter` (100ms) behind a `TelehealthProvider` seam |
| L10n | `flutter_localizations` + ARB — **wired into `MaterialApp` but no screen reads it** |
| Lints | `flutter_lints` + `strict-casts`/`strict-raw-types`/`strict-inference`, `avoid_print: true` |

Dart SDK `>=3.3.0 <4.0.0`.

---

## Commands

```bash
flutter pub get
flutter analyze --fatal-infos        # must be clean; CI enforces
dart format --set-exit-if-changed lib test
flutter test                         # 208 tests
flutter test --tags golden           # goldens; excluded from CI (host fonts)
flutter gen-l10n                     # auto-runs on build (generate: true)
flutter run --dart-define=USE_FIXTURES=true
flutter run --dart-define=ENV=staging --dart-define=API_BASE_URL=https://...
flutter build appbundle              # ship the AAB, never the universal APK
flutter build web --release
flutter run -d chrome -t lib/main_admin.dart        # operator console
flutter build web -t lib/main_admin.dart --output build/admin
```

`lib/firebase_options.dart` and `android/app/google-services.json` are **gitignored**.
Regenerate with `flutterfire configure`, or copy the stubs from `tool/ci/` for a
credential-free build.

### Build-time config (`--dart-define`)

| Key | Values | Default |
| --- | --- | --- |
| `ENV` | `dev` \| `staging` \| `prod` | `dev` |
| `API_BASE_URL` | any | per-env (`http://10.0.2.2:8080` on dev) |
| `USE_FIXTURES` | `true` \| `false` | `true` |

`USE_FIXTURES=false` swaps every binding except credentials, which is only ~15% built
server-side. All of it lives in
[lib/core/feature_providers.dart](lib/core/feature_providers.dart), so each new endpoint is a
one-line cutover in a single reviewable file.

---

## Platforms

Standard single-repo Flutter layout — one `lib/`, one `pubspec.yaml`, one native folder per
target. `android/`, `ios/` and `web/` are all present and tracked; `build/`,
`local.properties`, `*.iml` and the Firebase configs are correctly gitignored.

`linux/`, `macos/` and `windows/` also exist (from `flutter create .`) but are not product
targets. Harmless, though their generated plugin registrants churn on every `pub get`.
Delete them if desktop is never going to ship.

### Plugin support matrix

| Package | Android | iOS | Web |
| --- | :-: | :-: | :-: |
| firebase_core / firebase_auth / cloud_functions | yes | yes | yes |
| google_sign_in | yes | yes | yes — needs a meta tag, see below |
| sign_in_with_apple | yes | yes | yes |
| connectivity_plus, shared_preferences, printing, pdf | yes | yes | yes |
| file_picker, image_picker | yes | yes | yes |
| flutter_secure_storage | yes | yes | **localStorage only** |
| **hmssdk_flutter (100ms)** | yes | yes | **NONE** |

`flutter build web --release` succeeds today (verified). Three things do **not** carry over:

`flutter build web --release` succeeds — verified, not assumed. Two `dart:io` imports used to
break it; `lib/core/network/socket_error.dart` is now a conditional-import seam, and the file
picker carries bytes rather than paths. Three things still do **not** carry over:

1. **Video consultations do not work on web.** 100ms ships Android/iOS only. Its Dart
   surface is method channels, so web compiles fine and then throws
   `MissingPluginException` on join. `telehealthProviderProvider` therefore binds
   `UnsupportedTelehealthProvider` when `kIsWeb`, failing as an ordinary `Failure`
   (`TELEHEALTH_UNSUPPORTED_PLATFORM`) that tells the user to join from their phone. Do not
   remove that guard without a web media vendor behind `TelehealthProvider`.
2. **`ScreenProtection` is a no-op on web.** Browsers have no `FLAG_SECURE` equivalent — the
   method-channel call is swallowed as `MissingPluginException`, by design. PHI screens
   (records, prescriptions, sharing, consultation) are screenshot-able on web. Unavoidable.
3. **`flutter_secure_storage` on web is `localStorage`, not a keychain.** The refresh token
   would sit where any XSS can read it, contradicting the mobile design (memory-only access
   token, Keychain/Keystore refresh token). **Unresolved decision** — the correct fix is a
   same-site `HttpOnly` refresh cookie for the web client, which is a server-side choice,
   not a client one. Do not ship web auth to real users before deciding this.

### Web setup gotchas

- **Google Sign-In on web reads neither `firebase_options.dart` nor `google-services.json`.**
  It needs the Web OAuth client id in a `<meta name="google-signin-client_id">` tag in
  [web/index.html](web/index.html), where it sits commented out with instructions. Without
  it, sign-in fails at runtime with no useful error.
- Firebase web needs its authorised-domains list updated per deploy host.

CI builds all three targets: `build-android`, `build-ios`, `build-web` in `flutter.yml`.

---

## Architecture

Strict three layers per feature, no exceptions:

```
lib/features/<feature>/
  domain/        immutable models + enums + business rules. No Flutter, no Dio.
  data/          abstract <X>Repository  +  Fixture<X>Repository  (+ Api<X>Repository later)
  presentation/  Riverpod providers/controllers  +  ConsumerWidget screens
```

**Rules the codebase already follows — keep them:**

- Nothing above `ApiClient` knows about Dio or HTTP status codes. Errors are always
  [`Failure`](lib/core/error/failure.dart) with a coarse `FailureKind` + a machine `code`.
- Domain models are `@immutable`, have `fromJson`, and hold the business predicates
  (`Appointment.canCancel`, `RecordAccessGrant.isActive`, `Drug.isPrescribableOn`). Tests in
  `test/domain_rules_test.dart` assert those predicates directly.
- Screens are views. Mutations go through a controller or a top-level function next to
  the provider (e.g. `cancelAppointment`, `revokeGrant`) which invalidates the affected
  providers afterwards.
- Every async list renders through [`AsyncView`](lib/shared/widgets/async_view.dart), so
  loading/error/empty look identical app-wide. Companions: `FailureView`, `EmptyState`,
  `StatusChip`, `StarRating`.
- Dates/money/countdowns go through `Fmt.*` in [lib/shared/formatters.dart](lib/shared/formatters.dart)
  (`Fmt.date`, `Fmt.time`, `Fmt.relative`, `Fmt.countdown`, `Fmt.rupees`).

### Composition root

[lib/core/providers.dart](lib/core/providers.dart) — config, Dio, ApiClient, secure store,
device id, session. [lib/core/service_providers.dart](lib/core/service_providers.dart) —
Firebase Auth + connectivity. [lib/core/feature_providers.dart](lib/core/feature_providers.dart) —
all eleven repository bindings. Tests override any of these via `ProviderScope(overrides:)`.

### Network

- [`ApiClient`](lib/core/network/api_client.dart) — thin Dio wrapper; throws only `Failure`.
- [`ProblemJson`](lib/core/network/problem_json.dart) — parses RFC 9457 `application/problem+json`
  (`type`/`title`/`status`/`detail`/`code`/`requestId`/`errors`) into `Failure`. Honours
  `Retry-After` and `x-request-id`.
- [`AuthInterceptor`](lib/core/network/auth_interceptor.dart) — injects `Bearer`, and on
  401 **or** a body carrying `code: "TOKEN_STALE"` refreshes once and replays via a bare
  `retryDio` (no interceptor → cannot recurse). One retry max, flagged in `options.extra`.
  `skipAuth: true` opts a request out (session exchange / refresh).
- [`RefreshCoordinator`](lib/core/network/refresh_coordinator.dart) — single-flight. N
  concurrent 401s cause exactly one refresh. Critical: with rotating refresh tokens +
  reuse detection, a parallel second refresh looks like theft and nukes the session family.

---

## Session & RBAC — the part most likely to bite

Firebase proves **who**. The MiDoctor session proves **what they may do**. They are
separate objects and the app never authorizes off Firebase.

[`Session`](lib/core/session/session.dart) carries `userId`, `sessionId` (`sid`),
`accessToken`, `accessTokenExpiresAt`, `role`, `accountStatus`, `providerStatus`, `scopes`,
`permissionVersion`.

- **Access token: memory-only**, held in `SessionController._accessToken`. Never written to disk.
- **Refresh token: `SecureTokenStore` only.** Rotated on every refresh.
- `deviceId` is a random per-install hex string in secure storage — deliberately *not* a
  hardware id (DPDP Act).

### Roles ([lib/core/session/user_role.dart](lib/core/session/user_role.dart))

`patient`, `provider`, `supervisor`, `supportL1`, `supportL2`, `admin`, `unassigned`.
Only `patient` and `provider` have mobile UI; everything else routes to `/blocked`.

`ProviderStatus`: `draft`, `submitted`, `underReview`, `approved`, `rejected`,
`resubmitRequested`, `suspended`, `deactivated`, `notApplicable`. **Only `approved` gets the
provider shell**; every other value is pinned to `/provider/verification`.

`AccountStatus`: `active` | `pending` | `suspended` | `deactivated`. Non-active → `/blocked`
(a terminal screen with an explanation, never a silent sign-out).

### Scopes

Patient: `profile:read/write`, `doctor:search`, `appointment:create/cancel`,
`records:read_own/write_own`, `consent:grant/revoke/view_log`, `prescription:read_own`,
`consultation:join`, `rating:write`, `support:ticket_create`.
Provider: `profile:read`, `profile:write_limited`, `availability:write`,
`appointments:read_own`, `records:read_granted`, `records:request_access`,
`prescription:write`, `consultation:host/join`, `ratings:read_own`.
Admin holds `*:*`. Check with `session.hasScope('...')`.

The fixture mirrors this table exactly (`FixtureSessionRepository._scopesFor`), so
fixture-backed screens are gated the same way they will be against the API.

---

## Routing

Paths are constants in [lib/core/router/routes.dart](lib/core/router/routes.dart). The
tree is built in [lib/core/router/app_routes_builder.dart](lib/core/router/app_routes_builder.dart).

The redirect logic is **pure and unit-tested**: `resolveRedirect()` in
[lib/core/router/app_router.dart](lib/core/router/app_router.dart), covered by 21 cases in
`test/router_redirect_test.dart`. Riverpod → go_router refresh is bridged by
`_RouterRefresh`, which listens to `sessionControllerProvider` and `onboardingControllerProvider`.

Redirect precedence: session loading → `/splash`; no session → `/auth/*`; `!isUsable` →
`/blocked`; unsupported role → `/blocked`; patient without onboarding → `/onboarding/patient`;
provider not approved → `/provider/verification`; then cross-shell containment (a patient
can never land on `/provider/*` and vice versa).

**Two shells, not one.** `StatefulShellRoute.indexedStack` × 2 — it is structurally
impossible to render a provider tab in the patient shell.

| Shell | Branches |
| --- | --- |
| Patient | Home (+ doctor search → detail → book), Appointments (+ detail), Records (+ upload, prescriptions + detail), Profile |
| Provider | Today, Schedule (availability), Patients, Profile |

Pushed over the shell: booking-confirmed, sharing, settings/privacy/edit-profile, support,
consultation, rate, provider verification/credentials/mfa, prescribe.

Screens holding PHI are wrapped in `ProtectedScreen` (records, prescriptions, sharing,
consultation) — Android `FLAG_SECURE`, iOS blur-on-resign, no-op on web.

---

## Features (11 repositories = 11 backend surfaces)

| Feature | Repository contract | Key screens |
| --- | --- | --- |
| auth | `SessionRepository` — `exchange`, `refresh`, `logout` | login, signup, phone, otp, role selection (see Sign-in methods below) |
| providers_search | `DoctorRepository` — `search(filters)`, `byId`, `specialties`, `cities` | doctor search (+ debounced field, filter sheet), doctor detail |
| booking | `BookingRepository` — `slotsFor`, `hold`, `releaseHold`, `book` | booking (date strip + slot grid + hold countdown), booking confirmed |
| appointments | `AppointmentRepository` — `listForPatient`, `listForProvider`, `byId`, `cancel`, `checkIn` | appointments list, appointment detail (+ cancel sheet) |
| records | `RecordsRepository` — `listOwn`, `listGranted(patientId)`, `upload`, `delete` | records list (filtered), record upload (camera/gallery/doc) |
| consent | `ConsentRepository` — `grants`, `pendingRequests`, `accessLog`, `grant`, `revoke`, `approveRequest`, `denyRequest` | sharing screen (grants / requests / access log tabs) |
| prescriptions | `PrescriptionRepository` — `listForPatient`, `byId`, `searchDrugs`, `issue` | prescriptions list, prescription detail, prescribe (provider) |
| credentials | `CredentialsRepository` — `checklist`, `uploadDocument`, `verifyIdentityWithDigiLocker`, `setRegistrationNumber`, `beginMfaEnrolment`, `confirmMfaEnrolment`, `submitForReview` | credentials checklist, MFA (TOTP) enrolment |
| availability | `AvailabilityRepository` — `rules`, `exceptions`, `addRule`, `deleteRule`, `toggleRule`, `blockDay`, `deleteException` | availability editor (provider Schedule tab) |
| ratings | `RatingsRepository` — `listOwn`, `submit`, `edit` | rate appointment |
| support | `SupportRepository` — `listOwn`, `create`, `reply` | support tickets |
| consultation | `ConsultationRepository` — `byId`, `captureConsent`, `join`, `end`, `switchToAudio`, `sendMessage`, `networkQuality` + `TelehealthProvider` (media) | consultation screen: consent gate → waiting room → live call → chat, audio fallback |

### Domain rules already encoded (do not re-implement in UI)

- **Telemedicine drug lists** (MoHFW): `TelemedicineDrugList` — OTC + List A prescribable on
  first consult; **List B refill-only** (blocked unless follow-up); prohibited never. Blocked
  drugs are shown disabled *with a reason*, not hidden.
- **Consent**: every grant has a mandatory finite expiry, ceiling 180 days; there is no
  "until I revoke"; revoke is one tap; the access log records **denials** too.
- **Appointments**: cancellable only while upcoming; free-cancellation window 24h
  (placeholder, no business authority behind it).
- **Consultation join window**: opens 15 min before start, closes 30 min after scheduled
  end; in-person is never joinable.
- **Ratings**: one per completed appointment, editable 14 days, moderated before publish.
- **Provider verification gate**: all documents present **and** registration number **and**
  MFA enrolled before `submitForReview()`. A rejected document counts as not provided.
  There is deliberately **no Aadhaar credential kind** — identity is DigiLocker only.

---

## Sample data

`USE_FIXTURES=true` (the default) runs both apps against
[`FixtureBackend`](lib/core/fixtures/fixture_backend.dart) — **one** in-memory store shared by
every fixture repository, seeded from
[`fixture_seed.dart`](lib/core/fixtures/fixture_seed.dart).

That sharing is the whole point. The fixtures used to be independent, and the product did not
work even though every screen demoed correctly: booking returned an `Appointment` the
appointments list had never heard of, an uploaded record stayed "checking…" forever because
nothing finished the scan, and a prescription written by a doctor never reached the patient.
The cross-feature consequences now hold:

| Do this | And this happens |
| --- | --- |
| Book a slot | It appears in Appointments; the slot stops being offered |
| Cancel | The slot returns to the pool for someone else |
| Upload a record | Unreadable for ~3s, then clean — the quarantine state is real, not skipped |
| Grant consent | The doctor's view opens to exactly what the grant covers; revoking closes it |
| Issue a prescription | It reaches the patient's list and the appointment stops saying "none" |
| Rate a consultation | Queued for moderation, and it turns up in the console |
| Block a day | That day's slot grid genuinely empties |
| Submit credentials | An application appears in the operator console's review queue |

It enforces the real rules rather than accepting anything: slot exclusivity by the same
deterministic `<doctorId>__<startMillis>` id the server uses, the 180-day consent ceiling, the
14-day rating window, one rating per appointment, and the MoHFW drug lists. A fixture that
accepted what the server rejects would teach the UI a rule that does not hold.

**Signing in.** Sample data has no identity provider, so both apps offer an explicit sample
sign-in — "Explore with sample data" on the app's login screen, "Open with sample data" on the
console. Without it the mock data was unreachable: the app opened on a sign-in screen it could
not get past.

**The console is honest about its limits.** Reviewing, moderating and support all work against
the shared store. Opening a credential document, suspending an account and assigning a role
refuse with a clear message, because there is no file store behind the fixture and a console
that reports "account suspended" when nothing was suspended is the most dangerous kind of mock.

`FixtureBackend.resetShared()` restores the seed; `test/repository_behaviour_test.dart` and
`test/fixture_backend_test.dart` call it in `setUp` so one test's writes are invisible to the
next.

---

## Operator console (`lib/admin/`)

Supervisors, admins and support staff work in a **web console**, not the app. Run it with
`flutter run -d chrome -t lib/main_admin.dart`.

It is a separate entry point rather than a third `StatefulShellRoute`, for three reasons that
are worth keeping:

1. **Nothing under `lib/admin/` is reachable from `lib/main.dart`**, so approval logic and
   reviewer copy are never compiled into the APK that ships to the doctors being reviewed.
   The CI job `build-admin-console` also fails if that ever stops being true.
2. **Reviewing a degree certificate on a phone is not a thing anyone should do.** Modelling
   it as "another tab" invites exactly that.
3. It can sit behind a VPN or an IdP without any of that touching the app.

Everything below `lib/admin/` reuses `lib/core` — the same `ApiClient`, `AuthInterceptor`,
single-flight refresh and `Failure` mapping. Only the shell, routing and screens differ,
because the authorization story is identical and having two of those is how they drift.

| Screen | Scope | Does |
| --- | --- | --- |
| Verification queue → applicant | `provider:review` / `provider:approve` | Read each credential document in-page, accept or reject it with a structured reason, then approve (which composes the public directory listing) or reject the application |
| Accounts | `user:suspend`, `user:set_role` | Look up by id, suspend/deactivate with a recorded reason, reactivate, assign a role |
| Ratings | `provider:review` | Publish, hide or remove — this queue is a direct lever on which doctors search surfaces |
| Support | `support:ticket_read` | Queue, thread, reply, escalate, close |

`resolveAdminRedirect` is pure and unit-tested, exactly like the mobile one, and deliberately
**not** shared with it: one function serving both would mean a single edit could let a patient
into the review queue.

Two absences are deliberate. There is **no user search** — an operator acting on an account
already has its id, and a search box hands a helpdesk the ability to enumerate patients by
name. And there is **no patient-context panel** on a ticket: support staff hold no consent
grant, and a "recent appointments" sidebar is the fastest way to turn a helpdesk into an
unlogged route into someone's medical history.

The console has no fixture mode (`useFixturesProvider` is overridden to `false` in
`main_admin.dart`). A reviewer looking at invented applicants is worse than a reviewer looking
at an error: one of those ends with approving a doctor who does not exist.

Deployed as its own Firebase Hosting target (`admin`), separate from the app's (`app`), with
`X-Frame-Options: DENY` and a no-referrer policy.

---

## Sign-in methods

All three go through [`AuthService`](lib/services/auth_service.dart), which proves identity
only. Whatever succeeds, the resulting Firebase ID token is exchanged for a MiDoctor session
via `POST /v1/auth/session`.

| Method | Where | Notes |
| --- | --- | --- |
| Phone OTP (India) | all | Carrier/VoIP gate first (`carrier_service.dart` → Cloud Function) |
| Google | all | iOS also needs a URL scheme, see below |
| Apple | iOS/macOS only | Gated by `appleSignInAvailableProvider` |

**Apple specifics** — easy to break, each one is a review blocker:

- **Nonce**: sent to Apple SHA-256-hashed, to Firebase raw. Firebase re-hashes and compares.
  That comparison is what stops a stolen credential being replayed. Never pass the same form
  of the nonce to both.
- **Display name arrives exactly once**, on the very first authorization. `signInWithApple`
  captures it into `updateDisplayName` immediately; miss it and it is gone permanently.
- **Cancel is not an error.** `AuthorizationErrorCode.canceled` returns silently, matching
  Google's null-on-cancel, so dismissing the sheet shows no error.
- **Token revocation on account deletion is mandatory** (App Store Review 5.1.1(v)). The
  authorization code is also single-use, so it is captured at sign-in and held in memory;
  `revokeAppleToken()` is called from the privacy screen's delete flow. It only works if the
  user signed in with Apple *in that same app run* — a cold-start deletion needs the server
  to revoke using a refresh token stored at sign-up. **Server side not built.**
- **`appleSignInAvailableProvider`** gates the button on Apple platforms only. The package
  can run an Android/web flow via a Service ID, but that needs Apple server credentials this
  project has not set up — offering it there would render a button that always fails.
- **Entitlement**: [ios/Runner/Runner.entitlements](ios/Runner/Runner.entitlements) declares
  `com.apple.developer.applesignin`, wired into all three Runner build configs. The matching
  capability must *also* be enabled on the App ID in the Developer portal, or the entitlement
  is stripped at signing and the request fails at runtime with error 1000.

**Google on iOS is not finished**: it needs `CFBundleURLTypes` with the `REVERSED_CLIENT_ID`
from `GoogleService-Info.plist`. That file is gitignored, so `ios/Runner/Info.plist` carries
the block commented out with instructions. Without it the consent sheet opens and never
returns. Apple sign-in does not need a URL scheme — it uses the entitlement.

---

## The API (`functions/`)

Full route table and design notes in [functions/README.md](functions/README.md). It uses
**pnpm**, not npm — `npm install` fails on pnpm's node_modules layout.

Full route table in [functions/README.md](functions/README.md). Beyond the Express app there
are now four other deployed functions: `verifyIndianCarrier` (Twilio callable), `inspectUpload`
(a storage trigger), and three scheduled sweeps.

Still not built: a server-generated, WORM-stored prescription PDF. The client renders one
locally and says so — see `prescription_pdf.dart`. Credentials is ~15% built: submission and
the checklist only, so document upload, DigiLocker and MFA enrolment remain fixtures.

Wire values are UPPER_SNAKE throughout (`PATIENT`, `UNDER_REVIEW`, `IN_PERSON`,
`CANCELLED_BY_PATIENT`). Domain models carry `fromWire`/`wire` and `fromJson`.

Four server-side invariants that the client depends on and must not be "simplified":

- **`slotLocks` document ids are deterministic** (`<doctorId>__<startMillis>`). That is the
  entire no-double-booking guarantee — two phones addressing the same document id lets a
  Firestore transaction serialise them, the way a Postgres exclusion constraint would.
  Random slot ids would silently remove it.
- **Refresh tokens are single-use, stored hashed; reuse revokes the whole family.** This is
  why `RefreshCoordinator` exists on the client — without single-flight refresh, two
  concurrent 401s present the same token twice and look like theft.
- **`permissionVersion` mismatch → `TOKEN_STALE`**, which `AuthInterceptor` answers by
  refreshing and replaying. Every authorization change increments it — approve, reject,
  suspend, reactivate, role change, logout, erasure, and refresh-reuse detection — so a
  suspension lands on the next request instead of up to 15 minutes later. Logout relies on
  this: `requireAuth` reads `users`, never `sessions`, so stamping `sessions.revokedAt` alone
  left a stolen access token working for the rest of its 15-minute life.
- **Uploaded bytes never pass through the API.** The client PUTs to a signed URL, the object
  lands in a `quarantine/` prefix nothing can read, and `inspectUpload` promotes it only after
  the type is confirmed from magic bytes and EXIF is stripped. A Cloud Function relaying a
  25 MB file is billed twice for it and caps out at 32 MB.
- **Drug-list enforcement is server-side.** `assertPrescribable` re-resolves every item from
  the catalogue by id and derives follow-up status from appointment history. The client's copy
  of the table only decides what to grey out.
- **Availability is anchored to IST (+05:30), never to server or caller local time.** Cloud
  Functions runs in UTC, so building slots from `new Date(y,m,d)` shifts every doctor's hours
  by 5.5 hours in production while looking correct on an Indian dev machine. `booking/routes.ts`
  uses `IST_OFFSET_MS` and reads the calendar day out of the date string without ever parsing
  it into an instant. India has one timezone and no DST, so a fixed offset is exact.
- **`firestore.rules` denies everything, deliberately.** The app never holds a Firestore
  credential; the API uses the Admin SDK, which bypasses rules. Authorization has exactly one
  implementation. Do not "add rules for safety" — a second, weaker implementation of consent
  expiry is worse than none.

Local run: `firebase emulators:start --only functions,firestore` (Firestore emulator needs
**JDK 21+**; the functions emulator alone does not), secrets in a gitignored
`functions/.secret.local`, then
`flutter run --dart-define=USE_FIXTURES=false --dart-define=API_BASE_URL=http://10.0.2.2:5001/<project>/asia-south1/api`.

---

## Legacy code — `lib/screens`, `lib/services`, `lib/widgets`, `lib/models`

Pre-refactor Provider-era code that has **not** been migrated into `lib/features`. Still
wired into the router:

- `login_screen`, `signup_screen`, `phone_input_screen`, `otp_screen`, `onboarding_screen`
- `tabs/home_tab.dart`, `tabs/profile_tab.dart`
- `services/auth_service.dart` (Firebase Google + phone OTP), `services/carrier_service.dart`
  (Twilio Lookup via callable Cloud Function, region `asia-south1`, degrades to "unverified"
  rather than blocking), `utils/phone_validator.dart`, `utils/debouncer.dart`

**Dead — nothing imports these** (safe to delete, verify first):
`lib/screens/tabs/appointments_tab.dart`, `lib/screens/tabs/records_tab.dart`,
`lib/screens/doctors_screen.dart` (only referenced by the dead appointments_tab),
`lib/services/connectivity_service.dart`, `lib/utils/page_transitions.dart`,
`lib/features/booking/domain/payment.dart` (137 lines, zero importers anywhere), and
`ProviderTodayTab` / `ProviderScheduleTab` / `ProviderPatientsTab` in
`lib/features/provider_home/presentation/provider_tabs.dart` (the router uses
`ProviderTodayScreen` / `AvailabilityScreen` / `ProviderPatientsScreen` instead;
`ProviderProfileTab` from that file **is** live). `cupertino_icons` is a dependency with no
references.

`lib/screens/onboarding_screen.dart` and `lib/screens/tabs/profile_tab.dart` now read and
write the real patient profile through `accountRepositoryProvider`; they are legacy in style,
not in behaviour.

---

## Tests (`test/`, 139)

| File | Covers |
| --- | --- |
| `router_redirect_test.dart` | `resolveRedirect` across 7 roles × 9 provider statuses, incl. verification sub-routes |
| `account_test.dart` | patient profile parsing, partial-update semantics, erasure outcome |
| `api_repository_test.dart` | the `USE_FIXTURES=false` wire contract for every API repository |
| `admin_router_test.dart` | `resolveAdminRedirect`, and that the console's roles are the exact complement of the app's |
| `fixture_backend_test.dart` | the cross-feature consequences: book → appointments, upload → readable, grant → visible, prescribe → patient, submit → review queue |
| `widget/screens_test.dart` | screens mounted for real against the fixtures, in both locales |
| `golden/screens_golden_test.dart` | layout regressions, tagged `golden` and excluded from CI |
| `integration_test/` | end-to-end journeys on a device: `flutter test integration_test` |
| `domain_rules_test.dart` | drug lists, consent expiry, cancellation, join window, holds, verification gate, ratings |
| `fr_coverage_test.dart` | traceability against the FR spec (`docs/*.docx`) |
| `repository_behaviour_test.dart` | fixture repository semantics |
| `problem_json_test.dart` | transport + RFC 9457 → `Failure` mapping |
| `refresh_coordinator_test.dart` | single-flight refresh |
| `session_test.dart` | session parsing, expiry skew, scopes |
| `debouncer_test.dart`, `phone_validator_test.dart`, `widget_test.dart` | utils |

`fake_async` is pinned explicitly for deterministic timer tests.

`http_mock_adapter` backs `api_repository_test.dart`, which covers the wire contract of the
API-backed repositories — paths, request shapes, enum mapping both ways, and that a server
refusal arrives as a `Failure` rather than a `DioException`.

**Still untested:** the operator console's screens have no widget tests, and the Firestore
transactions need the emulator.

The API has its own suite: `cd functions && pnpm test` (vitest, 47 tests, no emulator
needed), covering the RBAC scope matrix, the IST/slot-id arithmetic, content inspection
(magic bytes, EXIF stripping) and TOTP against the RFC 6238 vectors. The Firestore transactions — double-booking and refresh
rotation — remain uncovered; they need the emulator.

---

## Localisation

**The app reads its strings from the ARB.** ~470 keys in `app_en.arb`, ~430 translated in
`app_hi.arb`. Screens use `context.l10n.someKey` via the extension in
[lib/l10n/l10n.dart](lib/l10n/l10n.dart) — short on purpose, because localisation that costs
more than typing the string does not happen.

**Coverage is about two thirds, not all of it.** Roughly 100 literals remain in the
patient/provider app: mostly interpolated strings, a few one-off screens, and
`prescription_pdf.dart` (a rendered document, not UI). `tool/l10n_migrate.py` is the migration
helper — it refuses a mapping that does not match, so a typo is a loud failure rather than a
string that quietly stayed English.

**The operator console (`lib/admin/`) is deliberately English-only.** It is internal staff
tooling, not a consumer surface, and translating a review queue nobody outside the company
sees is work that buys nothing.

The `LEGAL COPY` policy stands, and its rationale is now real rather than aspirational:
`captureConsent` sends the exact text and version from
[lib/features/consultation/domain/consent_text.dart](lib/features/consultation/domain/consent_text.dart),
and the server stores a SHA-256 of it. A machine translation would therefore produce a consent
record attesting to words no lawyer approved. The consent gate, DPDP rights summary and
retention notices must not be machine-translated. See [lib/l10n/README.md](lib/l10n/README.md).

---

## Non-negotiables / traps

1. **Never add a package before the code that imports it.** This has broken the build twice.
2. **Never `print()`.** `avoid_print` is an error — a stray print leaks PHI into logcat.
3. **Never persist clinical data locally.** Age/blood group were once in SharedPreferences;
   `purgeLegacyHealthData()` in `main()` wipes them on upgrade. They live in `patient_profiles`
   server-side now.
4. **Never throw from a release `buildType` block** in `android/app/build.gradle.kts`.
   R8 needs a Play Core `dontwarn` rule (see `android/app/proguard-rules.pro`).
5. Release builds **fail closed** without `android/key.properties` — that is deliberate.
   `-PallowDebugSigning=true` is a local-only escape hatch; never distribute the result.
6. `riverpod_generator` does not work on this Flutter version. Write providers by hand.
7. Use `flutter pub add`, not hand-pinned versions in `pubspec.yaml`.
8. Formatting is CI-enforced: run `dart format lib test` before committing.
9. On Windows, do not rewrite files with `python -c "open(p,'w')..."` — the default cp1252
   codec fails on em-dashes and truncates the file to zero after opening it. Use the Write
   tool, or pass `encoding='utf-8'`.
10. **`functions/` sources are CRLF; `lib/` is LF.** A `perl -0pi -e` substitution with `
`
    in the pattern silently matches nothing on the TypeScript side. Python's `io.open` with
    `encoding='utf-8'` normalises on read and restores on write, so it works on both.
11. **Never add a scope without an endpoint behind it.** A scope that guards nothing makes
    the RBAC matrix read as more complete than it is. Every scope now has a route behind it
    except the credentials ones.
12. **Crash reports must never carry PHI.** `CrashReporting` deliberately strips
    `Failure.message` — which can quote the server's `detail` verbatim — and forwards only the
    kind and machine code. Breadcrumbs are route names, never arguments.
13. **The consent gate renders from `TelemedicineConsent`.** The same string is hashed into
    the consent record, so inlining the copy in the widget again would let the two drift, and
    a hash of text nobody saw is not evidence of anything. Changing the wording means bumping
    `TelemedicineConsent.version`.

---

## Launch status

See [LAUNCH_CHECKLIST.md](LAUNCH_CHECKLIST.md). Short version — the app cannot launch:
every repository is a fixture, and six capabilities are *impossible* client-side (consent
revocation, double-booking prevention, provider approval, drug-list enforcement, audit log,
cross-device records). Also blocked on: a production Firebase project, Play/Apple accounts,
100ms + Twilio production credentials, NMC provider verification, DPDP compliance artefacts,
and a payment gateway decision (`BookingPolicy.requiresPayment()` returns `false`; Stripe is
likely wrong for INR domestic — Razorpay/Cashfree/PhonePe + UPI are the practical options).

Release AAB is ~80 MB (WebRTC natives); ship the App Bundle, never the universal APK.

## CI (`.github/workflows/`)

`flutter.yml` — l10n drift check, `dart format --set-exit-if-changed`,
`flutter analyze --fatal-infos`, `flutter test --coverage`, debug APK, iOS no-codesign build,
web release build.
`functions.yml` — typecheck/build the Cloud Functions package.
`security.yml` — gitleaks, osv-scanner, CodeQL.
CI copies `tool/ci/firebase_options.stub.dart` and `tool/ci/google-services.stub.json` into
place because the real ones are gitignored; the stubs contain no credentials.
