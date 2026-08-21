# MiDoctor API (Cloud Functions)

An Express app served by a single HTTPS function, `api`, in **asia-south1**
(Mumbai — India data residency, and a fraction of the RTT of a US/EU region).

Express rather than callable functions on purpose: the Flutter client is already
built against a REST contract — `/v1/...` paths, `Bearer` tokens, RFC 9457 error
bodies, a `TOKEN_STALE` refresh-and-replay interceptor. `onCall` would have meant
rewriting `ApiClient`, `AuthInterceptor` and every repository to speak Firebase's
envelope. This way the client is unchanged and the vendor stays swappable.

## Layout

```
src/
  index.ts                 exports `api` + the existing `verifyIndianCarrier`
  seed.ts                  specialties, doctors, availability
  api/
    app.ts                 route mounting
    errors.ts              Problem (RFC 9457), request id, terminal handler
    db.ts                  collection names + document types
    auth/
      scopes.ts            the RBAC matrix (server-side authority)
      tokens.ts            JWT mint/verify, refresh rotation, reuse detection
      middleware.ts        requireAuth, requireScope
      routes.ts            /v1/auth/*, /v1/me
    doctors/routes.ts      /v1/doctors, /specialties, /cities, /:id
    booking/routes.ts      slots, holds, POST /v1/appointments
    appointments/routes.ts list, detail, cancel, check-in
    consent/routes.ts      grants, requests, access log
    provider/routes.ts     verification queue, approve, reject
    admin/routes.ts        suspend, reactivate, assign role
    admin/review_routes.ts reviewer side: dossiers, decisions, queues
    credentials/           documents, registration number, TOTP enrolment
    records/routes.ts      metadata + signed upload/download URLs
    availability/routes.ts weekly rules, blocked days
    ratings/routes.ts      submit, edit, moderate
    support/routes.ts      tickets and replies
    prescriptions/         issue, drug search, MoHFW drug-list enforcement
    consultations/         consent capture, 100ms join tokens, chat
    storage.ts             signed URLs, quarantine/clean prefixes
    content_inspection.ts  magic bytes, EXIF stripping
    rate_limit.ts          Firestore-backed fixed-window limiter
  inspect_upload.ts        storage trigger: promote or reject an upload
  maintenance.ts           three scheduled sweeps
  grant-role.ts            out-of-band bootstrap for the first ADMIN
  seed.ts                  specialties, doctors, availability rules, drugs
```

**Five functions deploy, not one.** The Express app, the `verifyIndianCarrier` callable, the
`inspectUpload` storage trigger, and three schedulers (`sweepShortLived`, `sweepNightly`,
`completeErasures`).

Two functions are deployed, not one: the Express app above, and a separate
`verifyIndianCarrier` **callable** used by the phone sign-in flow (Twilio
Lookup; rejects VoIP, non-mobile, and carriers outside Airtel/Jio/Vi). It is
part of the attack surface and easy to miss when reading the table below.

## Endpoints

| Method | Path | Scope |
| --- | --- | --- |
| GET | `/v1/health` | — |
| POST | `/v1/auth/session` | — (Firebase ID token in body) |
| POST | `/v1/auth/refresh` | — (refresh token in body) |
| POST | `/v1/auth/logout` | authenticated |
| GET/PUT | `/v1/me` | authenticated |
| GET | `/v1/doctors` | `doctor:search` |
| GET | `/v1/doctors/specialties`, `/cities`, `/:id` | `doctor:search` |
| GET | `/v1/doctors/:id/slots?date=&mode=` | `doctor:search` |
| POST/DELETE | `/v1/slots/:slotId/hold` | `appointment:create` |
| POST | `/v1/appointments` | `appointment:create` |
| GET | `/v1/appointments`, `/:id` | authenticated |
| POST | `/v1/appointments/:id/cancel` | `appointment:cancel` |
| POST | `/v1/appointments/:id/check-in` | `appointments:read_own` |
| GET | `/v1/consent/grants`, `/requests`, `/access-log` | `consent:*` |
| POST | `/v1/consent/grants`, `/grants/:id/revoke` | `consent:grant` / `consent:revoke` |
| POST | `/v1/consent/requests/:id/approve`, `/deny` | `consent:grant` |
| POST | `/v1/consent/requests` | `records:request_access` |
| GET | `/v1/provider/verification`, `/queue` | provider / `provider:review` |
| POST | `/v1/provider/verification/submit` | `credentials:submit` |
| POST | `/v1/provider/:userId/approve`, `/reject` | `provider:approve` / `provider:reject` |
| GET | `/v1/me/export` | authenticated (DPDP s.11) |
| DELETE | `/v1/me` | authenticated (DPDP s.12) |
| GET | `/v1/admin/users/:userId` | `user:suspend` |
| POST | `/v1/admin/users/:userId/suspend`, `/reactivate` | `user:suspend` |
| POST | `/v1/admin/users/:userId/role` | `user:set_role` (ADMIN only) |
| GET/POST | `/v1/records` | `records:read_own` / `records:write_own` |
| GET | `/v1/records/:id/download` | owner, or a live consent grant |
| GET | `/v1/records/granted/:patientId` | `records:read_granted` |
| DELETE | `/v1/records/:id` | `records:write_own` |
| GET/POST | `/v1/availability/rules`, `/exceptions` | `availability:write` |
| POST | `/v1/availability/rules/:id/toggle` | `availability:write` |
| DELETE | `/v1/availability/rules/:id`, `/exceptions/:id` | `availability:write` |
| GET/POST | `/v1/ratings` | authenticated / `rating:write` |
| PUT | `/v1/ratings/:id` | `rating:write` |
| POST | `/v1/ratings/:id/moderate` | `provider:review` |
| GET/POST | `/v1/support/tickets`, `/:id/replies` | `support:ticket_create` |
| GET | `/v1/prescriptions`, `/:id`, `/drugs` | authenticated / `prescription:write` |
| POST | `/v1/prescriptions` | `prescription:write` |
| **GET** | **`/v1/rx/:code`** | **none — a pharmacist holds no token** |
| GET | `/v1/consultations/:id` | participant |
| POST | `/v1/consultations/:id/{consent,join-token,audio,messages,end}` | participant |
| GET | `/v1/credentials` | `credentials:submit` |
| POST | `/v1/credentials/documents` | `credentials:submit` |
| PUT | `/v1/credentials/registration-number` | `credentials:submit` |
| POST | `/v1/credentials/mfa/{begin,confirm}` | `credentials:submit` |
| POST | `/v1/credentials/submit` | `credentials:submit` |
| GET | `/v1/review/providers/:userId` | `provider:review` |
| POST | `/v1/review/providers/:userId/claim` | `provider:review` |
| GET | `/v1/review/credentials/:id/download` | `provider:review` |
| POST | `/v1/review/credentials/:id/decision` | `provider:approve` |
| GET | `/v1/review/ratings/pending` | `provider:review` |
| GET | `/v1/review/support/tickets`, `/:id` | `support:ticket_read` |
| POST | `/v1/review/support/tickets/:id/{replies,status}` | `support:ticket_read` |

`GET /v1/provider/verification` enforces no scope — only an inline check that
the caller is a PROVIDER. Only `/queue` requires `provider:review`.

`POST /v1/auth/session` and `/refresh` are rate limited (20 and 60 requests per
5 minutes per client). They are the only unauthenticated routes and the most
expensive work in the API.

## Design notes worth knowing before changing anything

**Authorization lives here, not in Firestore rules.** `firestore.rules` denies
everything. The app holds no Firestore credential — only a MiDoctor access
token — and the API reaches Firestore with the Admin SDK, which bypasses rules.
One implementation of consent expiry and scope checks, in one reviewable place.

**Double-booking is prevented by document id, not by a query.** `slotLocks`
documents are keyed `<doctorId>__<startMillis>`, so two phones booking the same
slot address the *same* document; a Firestore transaction that reads it missing
and then writes it will abort and retry if anyone else got there first. This is
the Firestore equivalent of a Postgres exclusion constraint. Never make slot ids
random.

**Refresh tokens are single-use and stored hashed.** Presenting an already-used
token revokes the whole family, because the server cannot tell replay from a
client racing itself and the safe reading is theft. This is exactly why the
Flutter client has `RefreshCoordinator` — without single-flight refresh, two
concurrent 401s would log the user out for doing nothing wrong.

**`permissionVersion` is what makes revocation fast.** A JWT is a snapshot of
authorization. Every authorization change — approve, reject, suspend,
reactivate, role change, logout, erasure, and refresh-token reuse detection —
increments the user's `permissionVersion`; `requireAuth` compares it to the
token's `ver` and answers `TOKEN_STALE`, which the client handles by refreshing
and replaying. Effect lands on the next request rather than up to fifteen
minutes later.

This is also how logout invalidates an access token. Stamping `sessions.revokedAt`
alone did nothing observable, because `requireAuth` reads `users`, not
`sessions` — a token stolen before a logout kept working for the rest of its
15-minute life, including after reuse detection. Bumping the version closes that
window without adding a second Firestore read to every authenticated request.
The cost is that logging out on one device makes the user's other devices
refresh once; they hold valid tokens in a different family and recover
silently.

**Availability is anchored to IST, not to server time.** Cloud Functions runs in
UTC. Building slots from server-local midnight would shift every doctor's hours
by 5.5 hours in production while looking perfectly correct on an Indian dev
machine — a bug that only appears once deployed. `IST_OFFSET_MS` is a fixed
+05:30 (India has one timezone and has never observed DST), and the requested
day is read out of the date string as calendar Y-M-D without ever being parsed
into an instant. Covered by `src/api/booking/ist.test.ts`, which asserts this
without setting `TZ` — every function under test must be independent of it.

That date string is validated strictly: anchored at both ends, with the
component ranges checked. An earlier version matched only a prefix, so a caller
could pass a full ISO instant and have its *text* day used — and
`2026-03-15T20:00:00Z` is already the 16th in IST, so the request quietly
returned the wrong day's slots.

**A slot id is a claim, not a fact.** It is just a doctor id and a millisecond
value the caller assembled, so both the hold and the confirm path run it through
`bookableRule`: the doctor exists and is APPROVED, the time is in the future, and
it lands on a real stride of a live availability rule. They share one function so
they cannot drift — a slot that can be held is by definition one that can be
booked. Without the check on the hold path, any authenticated patient could mint
`slotLocks` documents for doctors who do not exist, at times nobody offers.

**A consent grant never trusts the provider identity in the request body.** The
name on a grant is resolved from the directory, because a grant is the one
object in this system that hands a third party access to someone's medical
records — a body-supplied name lets a patient be walked through a consent screen
reading "Dr Anjali Rao" while the id underneath belongs to somebody else.

**There is no endpoint that can create a privileged account.** `resolveRequestedRole`
returns only PATIENT or PROVIDER, and role assignment needs `user:set_role`,
which only an ADMIN holds. The first ADMIN is therefore created out of band with
`pnpm grant-role`, which authenticates with Application Default Credentials —
running it already requires privileged access to the project. Without that step
no supervisor exists, so the provider-approval queue can never be worked and no
doctor can ever be approved.

**Uploaded bytes never pass through this API.** The client PUTs to a v4 signed URL and the
object lands in a `quarantine/` prefix that no download path will read. `inspectUpload` then
confirms the type from magic bytes, refuses anything that lied about what it was, strips EXIF
(GPS, device, capture time), and only then moves it to `clean/` and marks the record CLEAN.
A Cloud Function relaying a 25 MB file is billed twice for the bandwidth and caps out at
32 MB per request; more importantly, "unreadable until inspected" is a property of *where the
object is*, not of a flag someone could forget to check.

`scanForMalware` is a seam, not an implementation — it returns clean and says so. Detecting
malware needs a maintained signature database, which is a vendor relationship. Reporting a
file as virus-scanned when nothing scanned it would be worse than reporting nothing.

**The drug lists are enforced here, not in the app.** The Flutter client has the same table
and uses it to grey out options with a reason, which is good UX and no protection: a
repackaged APK sends the request anyway. `POST /v1/prescriptions` re-resolves every item from
the catalogue **by id** — the request carries the doctor's choices, never the classification
those choices are judged against — and derives follow-up status from appointment history,
because a client that could assert "this is a follow-up" could unlock List B.

**A 100ms join token is minted here for the same reason.** The app secret signs a token that
authorises being in a room; shipped in a client, it would let anyone join any consultation.
The token is short-lived, the doctor gets `host` and the patient `guest`, and neither role can
start a recording — which is how FR-TEL-003 holds at the vendor rather than in the UI.

**Consent records store a hash of the exact text.** `POST /v1/consultations/:id/consent`
takes the consent copy and its version and stores a SHA-256 of it. Recording only that consent
*happened* proves nothing later; the evidentiary value is being able to show which words were
on screen. The client renders that copy from a single constant so the two cannot drift.

**Nothing expires by itself, so three schedulers do it.** Expiry is evaluated lazily at read
time — which is the correct behaviour for authorization, because an expiry that is only true
when someone remembers to check is not an expiry — but that leaves the data growing without
bound and states like `EXPIRED` and `NO_SHOW` declared and unwritable. `sweepShortLived` runs
every 15 minutes, `sweepNightly` and `completeErasures` at 03:00 and 04:00 IST.

**MFA is part of the verification gate, not an afterthought.** An approved provider can read
patient records and issue prescriptions, so the account has to be hard to take over *before*
it gains those powers. TOTP is implemented in `credentials/totp.ts` rather than pulled from a
package: the algorithm is forty lines, and a dependency sitting directly on the authentication
path of those accounts is a supply-chain risk that is not worth forty lines. It is tested
against the RFC 6238 vectors, because an implementation can be perfectly self-consistent and
still disagree with every authenticator app on earth.

**Credential documents go through the same quarantine as medical records.** A reviewer
opening an attacker-supplied file is precisely the attack, and a reviewer is a higher-value
target than a patient. `inspectUpload` handles both prefixes; only the vocabulary differs
(a record becomes CLEAN, a credential becomes SUBMITTED).

**There is no user-search endpoint, deliberately.** The console looks an account up by id.
Adding search would hand a helpdesk the ability to enumerate patients by name, which is a very
different capability from "show me this specific account".

**Doctor search filters in two stages.** Firestore narrows on what it can index
(approval status, specialty, city); free text, fee ceiling and rating floor are
applied in memory over that set. Correct at closed-beta scale. A directory large
enough to outgrow it needs a search index (Algolia/Typesense), not a cleverer
Firestore query.

## Local development

```bash
pnpm install          # this package uses pnpm, not npm
pnpm build

# Secrets, for the emulator. NEVER commit this file — it is gitignored.
cat > .secret.local <<'ENV'
JWT_SECRET=<at least 32 random bytes>
TWILIO_SID=<optional locally>
TWILIO_TOKEN=<optional locally>
ENV

# The Firestore emulator needs JDK 21+. The functions emulator alone does not.
firebase emulators:start --only functions,firestore

# Seed, in a second shell
FIRESTORE_EMULATOR_HOST=localhost:8080 pnpm seed

# Sign in through the app once, then make that account an admin. Nothing in the
# API can do this — see the design note above.
FIRESTORE_EMULATOR_HOST=localhost:8080 FIREBASE_AUTH_EMULATOR_HOST=localhost:9099   pnpm grant-role -- --email you@example.com --role ADMIN
```

The emulator config also starts **auth** on 9099, and `POST /v1/auth/session`
calls `verifyIdToken`, so `--only functions,firestore` is not enough for a local
sign-in — add `auth`.

```bash
pnpm test             # vitest, no emulator required
pnpm exec tsc --noEmit
```

Point the app at it:

```bash
flutter run \
  --dart-define=USE_FIXTURES=false \
  --dart-define=API_BASE_URL=http://10.0.2.2:5001/<project>/asia-south1/api
```

`10.0.2.2` is the host loopback as seen from the Android emulator.

## Deploy

```bash
firebase functions:secrets:set JWT_SECRET      # >= 32 random bytes
firebase functions:secrets:set TWILIO_SID
firebase functions:secrets:set TWILIO_TOKEN
firebase deploy --only functions,firestore:rules,firestore:indexes
```

Then run the app against
`https://asia-south1-<project>.cloudfunctions.net/api`.

Rotating `JWT_SECRET` invalidates every access token immediately — that is the
emergency lever. Refresh tokens live in Firestore and are revoked separately.

## Not built yet

Every client repository now has a route behind it, including the 100ms
join-token endpoint. What is still missing:

- **A server-generated prescription PDF**, stored WORM. The client renders one
  locally and its own header says so. `GET /v1/rx/:code` and a content-derived,
  keyed verification code both exist, so the remaining work is the document.
- **A real antivirus.** `scanForMalware` returns clean and says so in its own
  docstring. Format validation and EXIF stripping are implemented and tested;
  malware detection needs a maintained signature database, which is a vendor
  relationship rather than a function.
- **DigiLocker identity verification.** Stubbed, and it returns an explicit
  "not connected" error rather than passing everyone — an identity check that
  silently succeeds is worse than none. A real integration is an OAuth flow
  against MeitY's partner API, which needs a registered client and a signed
  agreement.
- **Push notifications.** The schedulers that would send appointment reminders
  exist; the transport does not.
- **Payments.** The state model is complete and inert: `feeInr` is computed and
  stored, `PENDING_PAYMENT` and the refund states are declared, and every
  booking is written `NOT_REQUIRED`.

Also untested: the Firestore transactions — double-booking and refresh rotation
— which need the emulator. `pnpm test` covers everything that does not.
