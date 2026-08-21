# Localisation

English (`app_en.arb`) is the template; Hindi (`app_hi.arb`) omits keys by design and falls
back to English at runtime. Screens read them through `context.l10n.someKey` — the extension
in [`l10n.dart`](l10n.dart), kept deliberately short because localisation that costs more than
typing the string does not happen.

Roughly 470 English keys and 455 Hindi ones. The gap is two things and no more: the `LEGAL
COPY` entries below, and a handful of developer-only strings (the sample-data sign-in) that no
end user sees.

## Coverage is about two thirds

Around 100 literals remain hardcoded in the patient/provider app — mostly interpolated
strings, a few one-off screens, and `prescription_pdf.dart`, which renders a document rather
than UI. Finishing that is ordinary work; nothing about it is blocked.

`tool/l10n_migrate.py` does the mechanical part. It refuses a mapping whose literal it cannot
find, so a typo fails loudly instead of leaving a string quietly in English, and it strips the
`const` that a runtime lookup invalidates.

**The operator console (`lib/admin/`) is intentionally English-only.** It is internal staff
tooling, not a consumer surface. Translating a review queue that nobody outside the company
will ever open is work that buys nothing.

## Why the legal strings are not translated

Every entry marked `LEGAL COPY` in `app_en.arb` is deliberately absent from `app_hi.arb`:

- the telemedicine consent gate (MoHFW Telemedicine Practice Guidelines),
- the DPDP data-principal rights summary,
- the retention and erasure notices,
- the doctor's council registration number, which the guidelines require to be visible.

Machine-translated consent text is not consent, and here that is a property of the system
rather than an argument. `POST /v1/consultations/:id/consent` sends the exact string shown and
its version, and the server stores a SHA-256 of it — so a consent record attests to *which
words* the patient agreed to. The client renders that copy from a single constant,
[`TelemedicineConsent`](../features/consultation/domain/consent_text.dart), so the text that is
displayed and the text that is hashed cannot drift apart.

Two consequences follow, and both matter:

- **A mistranslation is not a cosmetic bug.** It produces a consent record attesting to words
  no lawyer approved, and for the "not for emergencies" notice it is a safety issue.
- **Changing the wording means bumping `TelemedicineConsent.version`.** Editing the string
  without it makes every older record impossible to interpret.

**These must be translated by a qualified legal translator and reviewed before Hindi ships as
a supported locale.** Until then a Hindi-locale user sees Hindi chrome around English legal
text, which is accurate — the intended state, not a gap. `test/widget/screens_test.dart`
asserts that mix renders.

## Adding a language

1. Copy `app_en.arb` to `app_<code>.arb` and set `@@locale`.
2. Translate everything **except** the `LEGAL COPY` entries, which fall back to English until
   a legal translator has signed them off.
3. `flutter gen-l10n` — it runs automatically on build, and CI fails on drift between the ARB
   files and the generated output.
4. Check the layout survives: Devanagari sets taller line boxes than Latin at the same point
   size, so a row that just fits in English can clip. `test/golden/screens_golden_test.dart`
   has a Hindi golden for exactly this.
