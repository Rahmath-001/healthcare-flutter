# MiDoctor

An Indian telemedicine app: **patients** book and consult, **doctors** are verified and
practise. Both audiences ship in one Flutter binary, separated by role at the router.

This repository holds two things:

| Path | What |
| --- | --- |
| `lib/` | The patient + provider app (Android, iOS, web) |
| `lib/admin/` | The **operator console** — a separate web entry point for supervisors, admins and support |
| `functions/` | The **MiDoctor API** — TypeScript Express on Cloud Functions. See [functions/README.md](functions/README.md) |

Engineering conventions, architecture rules and the traps worth knowing before changing
anything live in [CLAUDE.md](CLAUDE.md). Launch readiness lives in
[LAUNCH_CHECKLIST.md](LAUNCH_CHECKLIST.md). **This app cannot launch yet** — read that file
before assuming any part of it is production-ready.

---

## Quick start

```bash
flutter pub get
flutter run                                     # fixtures; no backend needed
flutter run -d chrome -t lib/main_admin.dart    # operator console
```

`USE_FIXTURES` defaults to `true`, so a plain `flutter run` gives a fully working app backed
by sample data — tap **Explore with sample data** on the login screen. Every fixture reads and
writes one shared in-memory store, so the features actually connect: book an appointment and
it appears in your list, upload a record and it becomes readable once "scanned", grant consent
and the doctor's view changes. The console works the same way.

To run against the real API:

```bash
cd functions && pnpm install && pnpm build     # pnpm, not npm
firebase emulators:start --only functions,firestore,auth
FIRESTORE_EMULATOR_HOST=localhost:8080 pnpm seed

flutter run \
  --dart-define=USE_FIXTURES=false \
  --dart-define=API_BASE_URL=http://10.0.2.2:5001/<project>/asia-south1/api
```

`lib/firebase_options.dart` and `android/app/google-services.json` are gitignored. Generate
them with `flutterfire configure`, or copy the credential-free stubs from `tool/ci/`.

### Build-time configuration

| `--dart-define` | Values | Default |
| --- | --- | --- |
| `ENV` | `dev` \| `staging` \| `prod` | `dev` |
| `API_BASE_URL` | any | per-env (`http://10.0.2.2:8080` on dev) |
| `USE_FIXTURES` | `true` \| `false` | `true` |

---

## How it is put together

Three layers per feature, no exceptions:

```
lib/features/<feature>/
  domain/        immutable models, enums, business rules. No Flutter, no Dio.
  data/          abstract <X>Repository + Fixture<X>Repository (+ Api<X>Repository)
  presentation/  Riverpod providers + ConsumerWidget screens
```

- **State** is `flutter_riverpod`, written by hand — `riverpod_generator` does not work on
  this Flutter version.
- **Routing** is `go_router`. The redirect logic is a pure, exhaustively unit-tested
  function, `resolveRedirect()` in [lib/core/router/app_router.dart](lib/core/router/app_router.dart).
- **Two shells, not one.** `StatefulShellRoute.indexedStack` × 2, so it is structurally
  impossible to render a provider tab in the patient shell.
- **Errors** are always a [`Failure`](lib/core/error/failure.dart). Nothing above `ApiClient`
  knows about Dio or HTTP status codes; the server speaks RFC 9457 `application/problem+json`.
- **Identity is not authorization.** Firebase Auth proves *who*; a separate MiDoctor session
  (own JWT, own scopes) decides *what they may do*. The app never authorizes off Firebase.

`lib/screens/`, `lib/services/`, `lib/widgets/` and `lib/models/` are pre-refactor code that
has not been migrated into `lib/features/`. Some of it is still live and wired into the
router — see the legacy section of [CLAUDE.md](CLAUDE.md) for which files are which.

---

## Sign-in

Google OAuth, Sign in with Apple (Apple platforms only), and India phone OTP behind a
Twilio carrier/VoIP check. **No email/password.** Whatever succeeds, the Firebase ID token is
exchanged for a MiDoctor session via `POST /v1/auth/session`.

Two platform steps are not finished and both fail silently at runtime:

- **iOS Google Sign-In** needs `CFBundleURLTypes` with the `REVERSED_CLIENT_ID` from
  `GoogleService-Info.plist`. The block sits commented out in `ios/Runner/Info.plist`.
- **Web Google Sign-In** needs the web OAuth client id in a `<meta name="google-signin-client_id">`
  tag in `web/index.html`, also commented out.

Apple sign-in has several requirements that are each a review blocker if broken — the nonce
must be hashed for Apple and raw for Firebase, the display name arrives exactly once, and
token revocation on account deletion is mandatory. See the Sign-in section of
[CLAUDE.md](CLAUDE.md) before touching `lib/services/auth_service.dart`.

### Phone OTP notes

- Twilio Lookup `line_type_intelligence` returns the current carrier and line type
  (`mobile`/`voip`/`landline`). The allow-list is in `functions/src/index.ts`, and it
  degrades to "unverified" rather than blocking sign-in.
- Real phone-auth SMS on Android emulators is unreliable (Play Integrity/reCAPTCHA fallback
  breaks on emulator WebViews). Use Firebase test phone numbers on an emulator, or a real
  device with Play Services.

---

## Checks

```bash
flutter analyze --fatal-infos                 # must be clean
dart format --set-exit-if-changed lib test
flutter test                                  # 208 tests

cd functions
pnpm exec tsc --noEmit
pnpm test                                     # 47 tests, no emulator needed
```

Goldens are tagged and excluded from CI (they render with the host's fonts):
`flutter test --tags golden`, and `flutter test --update-goldens --tags golden` to
regenerate. End-to-end journeys live in `integration_test/`.

Known gaps: the operator console's screens have no widget tests, and the Firestore
transactions (double-booking, refresh rotation) need the emulator to cover.

---

## Release builds & signing

Release builds are **never** signed with the debug keystore.
`android/app/build.gradle.kts` reads signing material from `android/key.properties`, which is
gitignored, and fails closed without it.

```bash
# 1. Generate an upload keystore (once — back it up somewhere durable)
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload

# 2. Create android/key.properties from the template and fill it in
cp android/key.properties.example android/key.properties
```

Then enable **Play App Signing**, so Google holds the app-signing key and this keystore is
only the *upload* key — which can be reset if it is ever lost.

```bash
flutter build appbundle                             # ship this
./gradlew assembleRelease -PallowDebugSigning=true  # local escape hatch, never distribute
```

**Ship the App Bundle, never the universal APK.** The 100ms WebRTC natives make the universal
APK ~97 MB; Play delivers only the matching ABI, so a real arm64 download is roughly 40 MB.
In India, install size converts directly into drop-off.

Release builds are minified and resource-shrunk (R8). A release-only crash that debug does
not reproduce is usually a missing keep rule in `android/app/proguard-rules.pro`.

---

## CI

| Workflow | Does |
| --- | --- |
| `flutter.yml` | l10n drift check, `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, `flutter test --coverage`, debug APK, iOS compile (non-blocking), web release build |
| `functions.yml` | Typecheck, test and build the Cloud Functions package |
| `security.yml` | gitleaks secret scan, osv-scanner dependency CVEs, CodeQL (JS/TS only — Dart is not scanned) |
| `release-android.yml` | On a `v*` tag: signed App Bundle, refuses a debug-signed artifact, keeps the R8 mapping file |

`flutter.yml` also builds the operator console from its own entry point, which doubles as a
check that nothing under `lib/admin/` has crept into a mobile import path.

Because `lib/firebase_options.dart` and `android/app/google-services.json` are gitignored, CI
copies the placeholder configs in `tool/ci/` into place. Those stubs contain **no real
credentials** and any artifact built with them cannot reach Firebase.

The analyzer runs with `strict-casts`, `strict-raw-types` and `strict-inference`, and
`avoid_print` is an **error** — a stray `print()` in a healthcare app leaks clinical data into
logcat.

> **CI has not actually run yet.** `.github/` is untracked in a two-commit repository, so
> every claim above is currently aspirational. Commit it and let it run before relying on it.
