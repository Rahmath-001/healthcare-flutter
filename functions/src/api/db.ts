import { getFirestore, Timestamp } from "firebase-admin/firestore";

export const db = () => getFirestore();

/**
 * Collection names, in one place so a typo is a compile error rather than a
 * silently empty query.
 *
 * Everything the client can reach goes through this API. Firestore security
 * rules deny all direct client access (see `firestore.rules`) — the app never
 * holds a Firestore credential, only a MiDoctor access token, so authorization
 * is enforced in exactly one place instead of being duplicated in rules.
 */
export const C = {
  users: "users",
  sessions: "sessions",
  refreshTokens: "refreshTokens",
  doctors: "doctors",
  specialties: "specialties",
  availabilityRules: "availabilityRules",
  appointments: "appointments",
  slotLocks: "slotLocks",
  consentGrants: "consentGrants",
  consentRequests: "consentRequests",
  accessLog: "accessLog",
  rateLimits: "rateLimits",
  erasureRequests: "erasureRequests",
  patientProfiles: "patientProfiles",
  records: "records",
  availabilityExceptions: "availabilityExceptions",
  ratings: "ratings",
  supportTickets: "supportTickets",
  prescriptions: "prescriptions",
  drugs: "drugs",
  consultations: "consultations",
  credentials: "credentials",
  providerVerifications: "providerVerifications",
} as const;

export type Role =
  | "PATIENT"
  | "PROVIDER"
  | "SUPERVISOR"
  | "SUPPORT_L1"
  | "SUPPORT_L2"
  | "ADMIN"
  | "UNASSIGNED";

export type AccountStatus = "ACTIVE" | "PENDING" | "SUSPENDED" | "DEACTIVATED";

export type ProviderStatus =
  | "DRAFT"
  | "SUBMITTED"
  | "UNDER_REVIEW"
  | "APPROVED"
  | "REJECTED"
  | "RESUBMIT_REQUESTED"
  | "SUSPENDED"
  | "DEACTIVATED"
  | "NOT_APPLICABLE";

export interface UserDoc {
  role: Role;
  status: AccountStatus;
  providerStatus: ProviderStatus;
  /**
   * Bumped on every authorization change. An access token carrying an older
   * `ver` is stale and must be refreshed before the request is served — this is
   * what makes a revocation take effect in seconds rather than in 15 minutes.
   */
  permissionVersion: number;
  displayName?: string | null;
  phone?: string | null;
  email?: string | null;
  photoUrl?: string | null;
  /** Set once the user is a provider; links to their `doctors` document. */
  doctorId?: string | null;
  /** Why the account was suspended. Shown to the user on the blocked screen. */
  suspensionReason?: string | null;
  /** Reviewer who moved this application into UNDER_REVIEW. */
  reviewClaimedBy?: string | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/**
 * Clinical profile, kept out of `users` on purpose.
 *
 * `users` is read on every authenticated request by `requireAuth`; blood group
 * and allergies are not needed to authorize anything, and putting them there
 * would mean the most sensitive fields in the system are fetched constantly and
 * land in every debug dump of an auth path. Splitting them costs one extra read
 * on the two screens that actually want them.
 *
 * `dateOfBirth` is stored as a plain `YYYY-MM-DD` string rather than a
 * Timestamp: a birth date is a calendar day, and an instant shifts by a day
 * either side of midnight depending on the reader's timezone.
 */
export interface PatientProfileDoc {
  dateOfBirth?: string | null;
  gender?: string | null;
  bloodGroup?: string | null;
  allergies?: string[];
  chronicConditions?: string[];
  emergencyContactName?: string | null;
  emergencyContactPhone?: string | null;
  updatedAt: Timestamp;
}

export interface SessionDoc {
  userId: string;
  deviceId: string;
  platform: string;
  appVersion: string;
  familyId: string;
  createdAt: Timestamp;
  lastSeenAt: Timestamp;
  revokedAt?: Timestamp | null;
}

/**
 * One issued refresh token, keyed by the SHA-256 of the token itself.
 *
 * The raw token is never stored: a database dump must not be usable as a set of
 * live credentials. Rotation marks the old document `usedAt`, and presenting an
 * already-used token is treated as theft — see `rotateRefreshToken`.
 */
export interface RefreshTokenDoc {
  userId: string;
  sessionId: string;
  familyId: string;
  expiresAt: Timestamp;
  usedAt?: Timestamp | null;
  revokedAt?: Timestamp | null;
}

export type ConsultationMode = "VIDEO" | "AUDIO" | "IN_PERSON";

export interface SpecialtyRef {
  code: string;
  name: string;
}

export interface HospitalRef {
  id: string;
  name: string;
  city: string;
  address?: string | null;
}

/** Shape mirrors the client's `Doctor`; see `doctorJson` in doctors/routes.ts. */
export interface DoctorDoc {
  name: string;
  specialties: SpecialtyRef[];
  qualification: string;
  /**
   * NMC / State Medical Council number. Surfaced to patients because the MoHFW
   * Telemedicine Practice Guidelines require it to be visible before and during
   * a consultation.
   */
  registrationNumber: string;
  yearsExperience: number;
  consultationFeeInr: number;
  videoFeeInr: number;
  rating: number;
  ratingCount: number;
  hospital: HospitalRef;
  languages: string[];
  modes: ConsultationMode[];
  photoUrl?: string | null;
  bio?: string | null;
  /** Only APPROVED providers are ever returned by search. */
  providerStatus: ProviderStatus;
  userId: string;
  /** Denormalised from `hospital.city` so Firestore can filter on it. */
  city: string;
  /**
   * Denormalised `specialties[].code`. Firestore cannot filter on a field
   * inside an array of objects, so the codes are duplicated into a flat array
   * that `array-contains` can index.
   */
  specialtyCodes: string[];
}

/** Provider working hours; slots are materialised from these on demand. */
export interface AvailabilityRuleDoc {
  doctorId: string;
  /** 1 = Monday … 7 = Sunday, matching Dart's `DateTime.weekday`. */
  weekday: number;
  startMinutes: number;
  endMinutes: number;
  mode: ConsultationMode;
  slotMinutes: number;
  active: boolean;
}

/**
 * A one-off change to the weekly pattern.
 *
 * `date` is a plain `YYYY-MM-DD` in IST, not a Timestamp, for the same reason a
 * birth date is: a blocked day is a calendar day, and storing it as an instant
 * makes it shift either side of midnight depending on who reads it.
 */
export interface AvailabilityExceptionDoc {
  doctorId: string;
  date: string;
  /** True blocks the day. False adds an extra window (not yet offered by the UI). */
  isBlocked: boolean;
  startMinutes?: number | null;
  endMinutes?: number | null;
  reason?: string | null;
  createdAt: Timestamp;
}

/** Wire values for the client's `AppointmentStatus`, one for one. */
export type AppointmentStatus =
  | "HELD"
  | "PENDING_PAYMENT"
  | "CONFIRMED"
  | "CHECKED_IN"
  | "IN_PROGRESS"
  | "COMPLETED"
  | "CANCELLED_BY_PATIENT"
  | "CANCELLED_BY_PROVIDER"
  | "RESCHEDULED"
  | "NO_SHOW_PATIENT"
  | "NO_SHOW_PROVIDER"
  | "EXPIRED";

export type PaymentStatus =
  | "NOT_REQUIRED"
  | "PENDING"
  | "AUTHORIZED"
  | "PAID"
  | "REFUND_PENDING"
  | "REFUNDED"
  | "FAILED";

export interface AppointmentDoc {
  /** Human-readable code the patient can quote to support, e.g. MD-8K2P4Q. */
  referenceCode: string;
  doctorId: string;
  patientId: string;
  patientName: string;
  start: Timestamp;
  end: Timestamp;
  mode: ConsultationMode;
  status: AppointmentStatus;
  paymentStatus: PaymentStatus;
  feeInr: number;
  reasonForVisit?: string | null;
  cancellationReason?: string | null;
  consultationId?: string | null;
  hasPrescription: boolean;
  hasRating: boolean;
  createdAt: Timestamp;
}

/**
 * The document that makes double-booking impossible.
 *
 * Its id is derived from the doctor and the exact start instant, so two
 * concurrent bookings for one slot address the *same* document. A Firestore
 * transaction that reads a missing document and then creates it will abort and
 * retry if anyone else created it first, which is the guarantee a Postgres
 * exclusion constraint would otherwise provide.
 */
export interface SlotLockDoc {
  doctorId: string;
  start: Timestamp;
  end: Timestamp;
  state: "HELD" | "BOOKED";
  heldBy?: string | null;
  /** A hold past this instant is treated as free and may be taken over. */
  holdExpiresAt?: Timestamp | null;
  appointmentId?: string | null;
}

export function slotLockId(doctorId: string, start: Date): string {
  return `${doctorId}__${start.getTime()}`;
}

export type RecordType =
  | "LAB_REPORT"
  | "SCAN"
  | "XRAY"
  | "PRESCRIPTION"
  | "DISCHARGE_SUMMARY"
  | "VACCINATION"
  | "OTHER";

export type RecordSource = "PATIENT" | "PROVIDER";

/**
 * Content-inspection state. A record is unreadable until it is CLEAN.
 *
 * PENDING is the state a record is created in — the metadata document exists
 * before the bytes do, because the client needs the record id to know where to
 * upload. A record whose upload never completes stays PENDING forever and is
 * collected by the maintenance job.
 */
export type ScanStatus = "PENDING" | "CLEAN" | "INFECTED" | "FAILED";

export interface MedicalRecordDoc {
  patientId: string;
  title: string;
  type: RecordType;
  source: RecordSource;
  /** When the study happened, not when it was uploaded. */
  recordedAt: Timestamp;
  uploadedAt: Timestamp;
  scanStatus: ScanStatus;
  /** Declared at creation, replaced with the detected type once inspected. */
  contentType: string;
  sizeBytes: number;
  /** Set once the object is promoted out of quarantine. */
  objectPath?: string | null;
  /** False when the format could not be rewritten safely — PDF and HEIC. */
  metadataStripped?: boolean;
  scanner?: string | null;
  rejectionReason?: string | null;
  issuedByName?: string | null;
  notes?: string | null;
  pageCount?: number | null;
  deletedAt?: Timestamp | null;
}

export type ConsentScopeKind = "SPECIFIC_RECORDS" | "RECORD_TYPES" | "ALL_RECORDS";

export type ConsentPurpose =
  | "CONSULTATION"
  | "SECOND_OPINION"
  | "CONTINUITY_OF_CARE"
  | "EMERGENCY";

export interface ConsentGrantDoc {
  patientId: string;
  providerId: string;
  providerName: string;
  providerSpecialty: string;
  scopeKind: ConsentScopeKind;
  purpose: ConsentPurpose;
  recordIds: string[];
  recordTypeLabels: string[];
  appointmentReference?: string | null;
  grantedAt: Timestamp;
  /** Never null. Every grant expires; the 180-day ceiling is enforced on write. */
  expiresAt: Timestamp;
  revokedAt?: Timestamp | null;
  usesCount: number;
}

export type AccessRequestStatus =
  | "PENDING"
  | "APPROVED"
  | "DENIED"
  | "EXPIRED"
  | "WITHDRAWN";

export interface ConsentRequestDoc {
  patientId: string;
  providerId: string;
  providerName: string;
  providerSpecialty: string;
  purpose: ConsentPurpose;
  message?: string | null;
  appointmentReference?: string | null;
  requestedAt: Timestamp;
  /** A request auto-expires after 72 hours so the channel cannot be a fishing tool. */
  expiresAt: Timestamp;
  status: AccessRequestStatus;
  resolvedAt?: Timestamp | null;
}

export type AccessAction = "VIEW_METADATA" | "VIEW" | "DOWNLOAD" | "DENIED";

/**
 * Append-only. Denials are recorded as deliberately as reads: a burst of denied
 * attempts is the clearest fraud signal the system produces, and a patient
 * asking "who looked at my records" is entitled to know who *tried*.
 */
export interface AccessEventDoc {
  patientId: string;
  actorId: string;
  actorName: string;
  recordTitle: string;
  action: AccessAction;
  purpose?: ConsentPurpose | null;
  at: Timestamp;
}

/**
 * A data-principal's request to erase their account (DPDP Act, s.12).
 *
 * Recorded rather than executed inline because erasure is not a delete. Consent
 * grants and sessions die immediately — that part is the point, and it is what
 * the patient can feel. Consultation notes and prescriptions cannot: they carry
 * a statutory retention period as medical records, so they are retained,
 * quarantined from every read path, and destroyed when it lapses.
 *
 * Keeping the request as a document is also what makes the obligation auditable:
 * a regulator's question is "when was it asked for and when was it completed",
 * and neither is answerable from an absence of rows.
 */
export interface ErasureRequestDoc {
  userId: string;
  requestedAt: Timestamp;
  /** When the retained clinical tail may be destroyed. */
  clinicalRetentionUntil: Timestamp;
  status: "REQUESTED" | "ANONYMISED" | "COMPLETED";
  completedAt?: Timestamp | null;
}

/**
 * Documents a provider must supply (FR-PROV-001).
 *
 * There is deliberately no Aadhaar kind. Identity is proven through DigiLocker,
 * from which only name, date of birth and the last four digits are retained;
 * storing Aadhaar images or numbers is a serious liability under the Aadhaar Act
 * and UIDAI regulations.
 */
export type CredentialKind =
  | "DEGREE_CERTIFICATE"
  | "MEDICAL_REGISTRATION"
  | "IDENTITY_PROOF"
  | "HOSPITAL_AFFILIATION";

/**
 * `PENDING_UPLOAD` exists because the metadata is written before the bytes
 * arrive — the client needs the id to know where to PUT. It becomes SUBMITTED
 * only once the file has passed inspection, so a reviewer never sees a document
 * that nothing has checked.
 */
export type CredentialReviewStatus =
  | "NOT_SUBMITTED"
  | "PENDING_UPLOAD"
  | "SUBMITTED"
  | "UNDER_REVIEW"
  | "ACCEPTED"
  | "REJECTED";

/** Structured rejection reasons (FR-PROV-003), mirroring the client's enum. */
export type RejectionReasonCode =
  | "DOC_ILLEGIBLE"
  | "DOC_EXPIRED"
  | "NAME_MISMATCH"
  | "NMC_NOT_FOUND"
  | "NMC_SUSPENDED"
  | "AFFILIATION_UNVERIFIABLE"
  | "SUSPECTED_FORGERY"
  | "DUPLICATE_ACCOUNT"
  | "INCOMPLETE_SUBMISSION";

export interface CredentialDoc {
  userId: string;
  kind: CredentialKind;
  status: CredentialReviewStatus;
  fileName?: string | null;
  contentType: string;
  sizeBytes: number;
  /** Set once the object is promoted out of quarantine. */
  objectPath?: string | null;
  uploadedAt: Timestamp;
  reasonCode?: RejectionReasonCode | null;
  reviewerNote?: string | null;
  reviewedBy?: string | null;
  reviewedAt?: Timestamp | null;
}

/**
 * The non-document half of provider verification.
 *
 * Separate from `users` because it holds the TOTP secret and recovery hashes,
 * and `users` is read by `requireAuth` on every single request — second-factor
 * material has no business being fetched that often or landing in a debug dump
 * of an auth path.
 */
export interface ProviderVerificationDoc {
  registrationNumber?: string | null;
  /** Base32. Present but unconfirmed until `mfaEnrolledAt` is set. */
  mfaSecret?: string | null;
  mfaEnrolledAt?: Timestamp | null;
  /** SHA-256 of each single-use recovery code. Never the codes themselves. */
  recoveryCodeHashes?: string[];
  identityVerifiedAt?: Timestamp | null;
  identityName?: string | null;
  identityDobYear?: number | null;
  identityLast4?: string | null;
  updatedAt?: Timestamp;
}

export type ConsultationStatus =
  | "SCHEDULED"
  | "WAITING"
  | "ACTIVE"
  | "ENDED"
  | "ABANDONED"
  | "TECH_FAILED";

export interface ChatMessageDoc {
  id: string;
  body: string;
  senderId: string;
  senderName: string;
  at: Timestamp;
}

/**
 * The live phase of an appointment.
 *
 * The document id **is** the appointment id, so "the consultation for this
 * appointment" cannot become a lookup that disagrees with itself.
 *
 * There is deliberately no `isRecorded` field. FR-TEL-003 forbids recording and
 * nothing at any layer implements it, so a stored flag could only ever be a
 * thing to get wrong; the API reports `isRecorded: false` as a constant.
 */
export interface ConsultationDoc {
  appointmentId: string;
  patientId: string;
  doctorId: string;
  mode: ConsultationMode;
  status: ConsultationStatus;
  /** 100ms room. Allocated on first join, not at booking time. */
  roomId?: string | null;
  startedAt?: Timestamp | null;
  endedAt?: Timestamp | null;
  /**
   * Consent evidence. The hash is of the exact text shown, so the record proves
   * *what* was agreed to rather than merely that something was.
   */
  consentCapturedAt?: Timestamp | null;
  consentVersion?: string | null;
  consentTextHash?: string | null;
  consentLocale?: string | null;
  messages?: ChatMessageDoc[];
}

export interface PrescriptionItemDoc {
  drugName: string;
  genericName: string;
  strength: string;
  form: string;
  /** Free-text dosing, e.g. "1-0-1" or "Twice daily". */
  frequency: string;
  durationDays: number;
  instructions?: string | null;
}

export type PrescriptionStatus = "DRAFT" | "ISSUED" | "CANCELLED" | "SUPERSEDED";

/**
 * An issued prescription.
 *
 * Provider and patient details are **snapshots** taken at issue time, not
 * references: this is a legal document and must render exactly as issued even
 * after the doctor edits their profile. There is deliberately no update path —
 * a mistake is corrected by cancelling and issuing a replacement, so what was
 * actually handed to a patient survives.
 */
export interface PrescriptionDoc {
  patientId: string;
  doctorId: string;
  appointmentId: string;
  verificationCode: string;
  providerName: string;
  providerQualification: string;
  providerRegistrationNumber: string;
  patientName: string;
  patientAge: string;
  patientGender: string;
  issuedAt: Timestamp;
  status: PrescriptionStatus;
  items: PrescriptionItemDoc[];
  diagnosis?: string | null;
  advice?: string | null;
  followUpDate?: string | null;
  appointmentReference?: string | null;
  /** Recorded because it is what made List B permissible, or not. */
  isFollowUp: boolean;
  /**
   * The write-once PDF this API generated, if it has been stored yet.
   *
   * Nullable because issuing the prescription and storing its document are
   * separate failures: a storage outage must not stop a doctor prescribing.
   * The scheduled sweep retries anything still null.
   */
  pdfPath?: string | null;
  /** SHA-256 of the stored bytes, so a copy can be checked against the record. */
  pdfSha256?: string | null;
  pdfStoredAt?: Timestamp | null;
}

export type RatingStatus = "PENDING_MODERATION" | "PUBLISHED" | "HIDDEN" | "REMOVED";

/**
 * One patient's rating of one completed appointment.
 *
 * The document id **is** the appointment id, which makes "one rating per
 * appointment" a property of the database rather than a check two concurrent
 * requests can both pass.
 */
export interface RatingDoc {
  appointmentId: string;
  patientId: string;
  doctorId: string;
  /** Snapshot at rating time, so a later profile edit does not rewrite history. */
  doctorName: string;
  stars: number;
  comment?: string | null;
  status: RatingStatus;
  createdAt: Timestamp;
  editedAt?: Timestamp | null;
  moderatedAt?: Timestamp | null;
}

/** Mirrors the client's `TicketCategory` one for one. */
export type TicketCategory =
  | "LOGIN_PROBLEM"
  | "BOOKING_PROBLEM"
  | "PAYMENT_PROBLEM"
  | "RECORDS_PROBLEM"
  | "DOCTOR_CONCERN"
  | "OTHER";

export type TicketStatus = "OPEN" | "ASSIGNED" | "ESCALATED" | "CLOSED";

export interface TicketMessageDoc {
  id: string;
  body: string;
  authorName: string;
  fromSupport: boolean;
  at: Timestamp;
}

/**
 * A support ticket.
 *
 * Messages are embedded rather than a subcollection: a ticket is read as a
 * whole every time, the thread is short by nature, and a subcollection would
 * turn one read into N. Firestore's 1 MB document ceiling is the bound, which
 * `MAX_BODY` keeps far away.
 */
export interface SupportTicketDoc {
  userId: string;
  reference: string;
  subject: string;
  category: TicketCategory;
  status: TicketStatus;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  messages: TicketMessageDoc[];
  /** Support agent who picked it up. Never surfaced to the ticket's owner. */
  assignedTo?: string | null;
}

export const now = () => Timestamp.now();

export function tsFromDate(d: Date): Timestamp {
  return Timestamp.fromDate(d);
}
