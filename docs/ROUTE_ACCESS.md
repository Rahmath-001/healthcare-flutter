# Route access and capabilities

This is the source-of-truth map for MiDoctor's Flutter routes. Firebase
Authentication proves identity; MiDoctor's server session and scopes decide
access. A client route is never authorization by itself.

## Public and authentication

| Route | Access | Capability |
| --- | --- | --- |
| `/` | Guest | Browse approved doctors, filter by speciality/location and start sign-in before booking. |
| `/doctors/:id` | Guest | Read one approved provider's public profile. |
| `/doctors/:id/book` | Guest, then patient sign-in | Begin booking; creating a hold or appointment requires a patient session. |
| `/hospitals` | Guest | Browse operator-approved hospitals. |
| `/hospitals/:id` | Guest | Read a hospital's published location and approved affiliated providers. |
| `/auth/login` | Guest | Google, Apple, phone and hospital-administrator sign-in choices. |
| `/auth/phone`, `/auth/otp` | Guest | Firebase phone OTP journey. |
| `/auth/signup`, `/auth/role`, `/auth/consent` | Guest | Patient/provider registration and legal acceptance. |
| `/auth/organisation` | Guest | Submit a hospital, lab or home-health registration for review; it creates no privileged account. |
| `/auth/organisation-sign-in` | Provisioned `HOSPITAL` account | Firebase email/password sign-in for an already approved, provisioned hospital administrator. |

## Hospital administrator

| Route | Role and server scope | Capability |
| --- | --- | --- |
| `/hospital/home` | `HOSPITAL`, `hospital:read_own` | View only the assigned verified organisation and its published provider network. |
| `/hospital/manage` — Organisation tab | `HOSPITAL`, `hospital:request_change` | Submit name, address, city, state and postal-code changes for operations review. It never directly changes the public listing. |
| `/hospital/manage` — Provider network tab | `HOSPITAL`, `hospital:request_affiliation` | Submit an affiliation request for an already approved provider by MiDoctor provider ID; view its review status. |

Hospital users cannot select another hospital ID, publish a change, approve a
provider, view patient records, or create staff accounts. The API derives the
hospital from the signed-in user's session.

## Patient

| Route family | Role | Capability |
| --- | --- | --- |
| `/patient/home`, `/patient/doctors`, `/patient/hospitals` | `PATIENT` | Discover doctors/hospitals and begin booking. |
| `/patient/appointments/*`, `/patient/booking-confirmed` | `PATIENT` | View, cancel and track the caller's appointments. |
| `/patient/records/*`, `/patient/prescriptions`, `/patient/medications` | `PATIENT` | Manage the caller's records, prescriptions and self-reported medication doses. |
| `/patient/sharing`, `/patient/support`, `/patient/settings/*` | `PATIENT` | Manage consent, support tickets, account/profile/privacy/device settings and notification preferences. |

## Provider

| Route family | Role and state | Capability |
| --- | --- | --- |
| `/provider/verification/*` | `PROVIDER` not yet approved | Submit credentials and complete the verification journey only. |
| `/provider/today`, `/provider/schedule`, `/provider/patients/*` | Approved `PROVIDER` | View own work, availability and patients for whom a valid access relationship exists. |
| `/provider/prescribe/:id`, `/provider/consultation/:id`, `/provider/ratings`, `/provider/refills` | Approved `PROVIDER` | Conduct authorised consultations, issue prescriptions, manage ratings and refill requests. |

## Operations console

Supervisor, support and admin roles are deliberately blocked from the patient
mobile shell. They use the separate operations application (`main_admin.dart`).
Operations users review provider credentials, organisation applications,
moderation queues and support work according to their server scopes. `ADMIN`
has the wildcard scope, but the UI still limits every action to its assigned
operations surface.

## Hospital lifecycle

1. A guest submits `/auth/organisation`.
2. Operations verifies and approves the organisation; only then does it enter
   the public hospital directory and receive a provisioned hospital account.
3. The hospital administrator signs in at `/auth/organisation-sign-in` and
   uses `/hospital/manage` to request amendments or provider affiliations.
4. Operations verifies the request. Until that decision, public directory data
   and provider affiliation remain unchanged.

## Enforcement

- Flutter router redirects roles to their allowed area, but the API enforces
  scopes on every request.
- `GET /v1/hospitals/mine` derives the organisation from the bearer token.
- `POST /v1/hospitals/mine/change-requests` and
  `POST /v1/hospitals/mine/affiliation-requests` create review records only.
- Direct client Firestore access is denied; the app does not hold a Firestore
  credential.
