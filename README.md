# Healthcare Mobile (Flutter)

User-side healthcare app. Auth = **Google OAuth** + **India phone OTP** only (no email/password).
Phone rule: India (+91), carriers **Airtel / Jio / Vi** only, **VoIP rejected**.

Carrier/VoIP check is server-side (Twilio Lookup via a Firebase Cloud Function),
because India Mobile Number Portability makes prefix→carrier matching unreliable.
If the function isn't deployed, the check degrades gracefully to "unverified"
rather than blocking sign-in (see `lib/services/carrier_service.dart`).

## Features

**Auth & onboarding**
- Google OAuth and India phone OTP sign-in (`LoginScreen`, `SignupScreen`)
- Phone number → server-side carrier gate → OTP (`PhoneInputScreen` → `OtpScreen`)
- 3-step onboarding after first sign-in: intro, health profile (age/blood group), notifications (`OnboardingScreen`)
- `AuthGate` (`lib/app.dart`) routes between Login → Onboarding → Dashboard based on auth + onboarding state
- Animated transitions, debounced real-time form validation, shimmer loading states, offline banner

**Dashboard** (`DashboardScreen`, 4-tab bottom nav)
- **Home** — greeting card + quick actions (Book Appointment, View Records, Medications, Contact Support)
- **Appointments** — booked appointments list (status, date/time, mode, location) with a persistent "Book Appointment" CTA at top; tap-through to doctor search
- **Records** — health documents, segmented "From Doctor" / "My Uploads" toggle, search
- **Profile** — user info, saved health profile, sign out

**Booking & tracking**
- `DoctorsScreen` — doctor search + specialty filter chips, book action
- `MedicationsScreen` — medications grouped by health condition, dosage schedule, consumption progress

All appointment/record/medication data is currently mock/sample — UI is built to the real shape, ready to wire to a backend.

## One-time setup

```bash
# 1. Generate native platform folders (already done in this repo, re-run if needed)
flutter create .

# 2. Wire Firebase (creates lib/firebase_options.dart and android/app/google-services.json — both gitignored)
dart pub global activate flutterfire_cli
firebase login
flutterfire configure --project=<your-firebase-project-id>

# 3. Enable Phone + Google providers in Firebase console (Authentication → Sign-in method)
#    Add a SHA-1 fingerprint for Android Google Sign-In:
cd android && ./gradlew signingReport   # copy the debug SHA1
#    Paste it into Firebase console → Project settings → your Android app → Add fingerprint
#    Then re-pull config: firebase apps:sdkconfig android <appId> --out android/app/google-services.json

# 4. (Optional) Deploy the Twilio carrier-check Cloud Function — requires Blaze (pay-as-you-go) plan
cd functions
npm install
firebase functions:secrets:set TWILIO_SID
firebase functions:secrets:set TWILIO_TOKEN
firebase deploy --only functions
cd ..

# 5. Run
flutter pub get
flutter run
```

### Testing OTP without real SMS / without Blaze
Firebase console → Authentication → Sign-in method → Phone → "Phone numbers for testing".
Add a fake number (e.g. `+91 9999999999`) with a fixed code (e.g. `123456`) and **click Save**.
Using that number in the app skips real SMS and the Twilio gate entirely — free, works on emulators.

## Project structure
```
lib/
  app.dart                  # AuthGate: Login -> Onboarding -> Dashboard
  main.dart                 # Firebase init, MultiProvider
  models/app_user.dart
  services/
    auth_service.dart       # Google + phone OTP via Firebase Auth
    carrier_service.dart    # Twilio carrier/VoIP gate (graceful fallback)
    connectivity_service.dart
    onboarding_service.dart # SharedPreferences: onboarding flag + health profile
  screens/
    login_screen.dart, signup_screen.dart
    phone_input_screen.dart, otp_screen.dart
    onboarding_screen.dart
    dashboard_screen.dart   # bottom-nav shell
    doctors_screen.dart     # search + book
    medications_screen.dart
    tabs/                   # home_tab, appointments_tab, records_tab, profile_tab
  utils/
    phone_validator.dart, debouncer.dart, page_transitions.dart
  widgets/
    primary_button.dart, google_button.dart, offline_banner.dart, shimmer_placeholder.dart
functions/                  # Firebase Cloud Functions (TypeScript)
  src/index.ts               # verifyIndianCarrier callable (Twilio Lookup)
test/
  phone_validator_test.dart
```

## Notes
- `lib/firebase_options.dart` and `android/app/google-services.json` are gitignored —
  regenerate via `flutterfire configure` after cloning.
- Function region: `asia-south1`. Adjust in `functions/src/index.ts` if needed.
- Twilio Lookup `line_type_intelligence` returns current carrier + line type
  (`mobile`/`voip`/`landline`). Allow-list in `functions/src/index.ts`.
- Real phone-auth SMS on Android emulators is unreliable (Play Integrity/reCAPTCHA
  fallback breaks on emulator WebViews). Use Firebase test phone numbers for emulator
  testing, or a real device with Google Play Services for real SMS.
