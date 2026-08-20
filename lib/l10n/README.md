# Localisation

> **Nothing here reaches a user yet.** `AppLocalizations` is wired into
> `MaterialApp` in `lib/app.dart` and **no screen reads a single key** — every
> user-facing string in `lib/features` and `lib/screens` is a hardcoded English
> literal (~272 of them). So the Hindi ARB currently ships nothing, and the CI
> drift check guards a file nothing consumes. Localising the app is real,
> unstarted work; this document describes the policy that will apply once it
> starts.

English (`app_en.arb`) is the template. Hindi (`app_hi.arb`) is partial **by
design** — any key it omits falls back to English at runtime. There are ~37 keys
in the template and ~21 in Hindi, so 16 are missing; three of those (`doctor`,
`duration`, `sharingEndsIn`) are ordinary UI strings rather than the legal copy
the policy below covers, and should simply be translated.

## Why the legal strings are not translated yet

Every entry marked `LEGAL COPY` in `app_en.arb` is deliberately absent from
`app_hi.arb`. These are:

- the telemedicine consent gate (MoHFW Telemedicine Practice Guidelines),
- the DPDP data-principal rights summary,
- the retention and erasure notices.

Machine-translated consent text is not consent. The intent is that the exact
string shown to a user is hashed and stored as proof of what they agreed to, so
a mistranslation is not a cosmetic bug — it invalidates the consent record and,
for the "not for emergencies" notice, is a safety issue.

**That hashing does not exist yet.** `ConsultationRepository.captureConsent(id)`
sends a consultation id and nothing else: no consent text, no version, no hash,
no record of which words were on screen. Until a consent record binds the exact
string, the argument above is a design intention rather than a property of the
system — and the reason to keep the legal copy untranslated is simply that
unreviewed legal text is worse than accurate English.

**These must be translated by a qualified legal translator and reviewed before
Hindi ships as a supported locale.** Until then, a Hindi-locale user sees the
English legal text, which is accurate, rather than an unreviewed translation.

## Adding a language

1. Copy `app_en.arb` to `app_<code>.arb` and set `@@locale`.
2. Translate. Leave `LEGAL COPY` entries out until reviewed.
3. Add the locale to `supportedLocales` in `lib/app.dart`.
4. `flutter gen-l10n` runs automatically on build (`generate: true`).

## Consent policy versioning

Changing any `LEGAL COPY` string is a **policy version bump**, not an edit:
existing consent artifacts reference the text they were granted against. Bump
the version server-side and re-obtain consent rather than silently changing what
people already agreed to.
