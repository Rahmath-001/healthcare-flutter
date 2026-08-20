/**
 * Seeds specialties, approved doctors and their availability.
 *
 * Search returns nothing until doctors exist, and slots come from availability
 * rules — so without this the app is correctly wired and completely empty,
 * which is indistinguishable from broken.
 *
 * Run against the emulator:
 *   firebase emulators:start --only firestore
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 npm run seed
 *
 * Or against a real project (destructive to these collections only):
 *   GOOGLE_APPLICATION_CREDENTIALS=key.json npm run seed
 *
 * Idempotent: every document has a fixed id, so re-running overwrites rather
 * than duplicating.
 */
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import { C, type AvailabilityRuleDoc, type DoctorDoc } from "./api/db";
import type { DrugDoc } from "./api/prescriptions/drug_rules";

initializeApp();
const db = getFirestore();

const SPECIALTIES = [
  { code: "GEN", name: "General Physician" },
  { code: "CARD", name: "Cardiology" },
  { code: "DERM", name: "Dermatology" },
  { code: "PED", name: "Paediatrics" },
  { code: "ORTH", name: "Orthopaedics" },
  { code: "GYN", name: "Gynaecology" },
  { code: "PSY", name: "Psychiatry" },
  { code: "ENT", name: "ENT" },
];

const DOCTORS: (DoctorDoc & { id: string })[] = [
  {
    id: "d1",
    name: "Dr Anjali Rao",
    specialties: [{ code: "CARD", name: "Cardiology" }],
    qualification: "MBBS, MD (Cardiology)",
    registrationNumber: "KMC-48219",
    yearsExperience: 14,
    consultationFeeInr: 800,
    videoFeeInr: 600,
    rating: 4.8,
    ratingCount: 213,
    hospital: { id: "h1", name: "Apollo Hospitals", city: "Bengaluru", address: "Bannerghatta Road" },
    languages: ["English", "Hindi", "Kannada"],
    modes: ["VIDEO", "AUDIO", "IN_PERSON"],
    photoUrl: null,
    bio: "Interventional cardiologist with a focus on preventive care and hypertension management.",
    providerStatus: "APPROVED",
    userId: "seed-d1",
    city: "Bengaluru",
    specialtyCodes: ["CARD"],
  },
  {
    id: "d2",
    name: "Dr Vikram Nair",
    specialties: [{ code: "GEN", name: "General Physician" }],
    qualification: "MBBS, MD (Internal Medicine)",
    registrationNumber: "TNMC-31882",
    yearsExperience: 9,
    consultationFeeInr: 500,
    videoFeeInr: 400,
    rating: 4.5,
    ratingCount: 147,
    hospital: { id: "h2", name: "Fortis Malar", city: "Chennai", address: "Adyar" },
    languages: ["English", "Tamil"],
    modes: ["VIDEO", "AUDIO"],
    photoUrl: null,
    bio: "General medicine, diabetes and thyroid care.",
    providerStatus: "APPROVED",
    userId: "seed-d2",
    city: "Chennai",
    specialtyCodes: ["GEN"],
  },
  {
    id: "d3",
    name: "Dr Meera Shah",
    specialties: [{ code: "DERM", name: "Dermatology" }],
    qualification: "MBBS, DDVL",
    registrationNumber: "MMC-77401",
    yearsExperience: 6,
    consultationFeeInr: 700,
    videoFeeInr: 550,
    rating: 4.6,
    ratingCount: 88,
    hospital: { id: "h3", name: "Lilavati Hospital", city: "Mumbai", address: "Bandra West" },
    languages: ["English", "Hindi", "Gujarati"],
    modes: ["VIDEO", "IN_PERSON"],
    photoUrl: null,
    bio: "Acne, pigmentation and paediatric dermatology.",
    providerStatus: "APPROVED",
    userId: "seed-d3",
    city: "Mumbai",
    specialtyCodes: ["DERM"],
  },
  {
    id: "d4",
    name: "Dr Sanjay Gupta",
    specialties: [{ code: "PED", name: "Paediatrics" }],
    qualification: "MBBS, MD (Paediatrics)",
    registrationNumber: "DMC-20934",
    yearsExperience: 18,
    consultationFeeInr: 650,
    videoFeeInr: 500,
    rating: 4.9,
    ratingCount: 402,
    hospital: { id: "h4", name: "Max Super Speciality", city: "Delhi", address: "Saket" },
    languages: ["English", "Hindi"],
    modes: ["VIDEO", "AUDIO", "IN_PERSON"],
    photoUrl: null,
    bio: "Newborn and child health, vaccination schedules.",
    providerStatus: "APPROVED",
    userId: "seed-d4",
    city: "Delhi",
    specialtyCodes: ["PED"],
  },
];

/** Weekday mornings and evenings, video and in-person. */
function rulesFor(doctorId: string): AvailabilityRuleDoc[] {
  const out: AvailabilityRuleDoc[] = [];
  for (let weekday = 1; weekday <= 5; weekday++) {
    out.push({
      doctorId,
      weekday,
      startMinutes: 10 * 60,
      endMinutes: 13 * 60,
      mode: "VIDEO",
      slotMinutes: 30,
      active: true,
    });
    out.push({
      doctorId,
      weekday,
      startMinutes: 17 * 60,
      endMinutes: 20 * 60,
      mode: "IN_PERSON",
      slotMinutes: 30,
      active: true,
    });
  }
  return out;
}

/**
 * A small telemedicine formulary.
 *
 * Enough to exercise every branch of the MoHFW rules — an OTC drug, a List A
 * drug, a List B refill-only drug and a prohibited one — and deliberately not
 * more. A real deployment loads the current schedule from a maintained source;
 * a hand-written formulary that drifts is worse than an obviously partial one.
 */
const DRUGS: (DrugDoc & { id: string })[] = [
  {
    id: "paracetamol-500",
    name: "Paracetamol 500mg",
    genericName: "Paracetamol",
    form: "Tablet",
    telemedicineList: "LIST_O",
    commonStrengths: ["500mg", "650mg"],
    searchTerms: ["par", "ace", "cal", "dol"],
  },
  {
    id: "ors",
    name: "ORS Sachet",
    genericName: "Oral rehydration salts",
    form: "Powder",
    telemedicineList: "LIST_O",
    commonStrengths: ["21.8g"],
    searchTerms: ["ors", "ora", "reh"],
  },
  {
    id: "cetirizine-10",
    name: "Cetirizine 10mg",
    genericName: "Cetirizine",
    form: "Tablet",
    telemedicineList: "LIST_O",
    commonStrengths: ["5mg", "10mg"],
    searchTerms: ["cet", "ceti", "all"],
  },
  {
    id: "amoxicillin-500",
    name: "Amoxicillin 500mg",
    genericName: "Amoxicillin",
    form: "Capsule",
    telemedicineList: "LIST_A",
    commonStrengths: ["250mg", "500mg"],
    searchTerms: ["amo", "amox", "pen"],
  },
  {
    id: "azithromycin-500",
    name: "Azithromycin 500mg",
    genericName: "Azithromycin",
    form: "Tablet",
    telemedicineList: "LIST_A",
    commonStrengths: ["250mg", "500mg"],
    searchTerms: ["azi", "azit", "mac"],
  },
  {
    id: "metformin-500",
    name: "Metformin 500mg",
    genericName: "Metformin",
    form: "Tablet",
    // Chronic-disease maintenance: a refill at a follow-up, never a first
    // remote consultation.
    telemedicineList: "LIST_B",
    commonStrengths: ["500mg", "850mg", "1000mg"],
    searchTerms: ["met", "metf", "glu"],
  },
  {
    id: "amlodipine-5",
    name: "Amlodipine 5mg",
    genericName: "Amlodipine",
    form: "Tablet",
    telemedicineList: "LIST_B",
    commonStrengths: ["2.5mg", "5mg", "10mg"],
    searchTerms: ["aml", "amlo", "nor"],
  },
  {
    id: "alprazolam-025",
    name: "Alprazolam 0.25mg",
    genericName: "Alprazolam",
    form: "Tablet",
    // Schedule H1 psychotropic. Never prescribable in a teleconsultation, by
    // anyone, on any consultation type.
    telemedicineList: "PROHIBITED",
    commonStrengths: ["0.25mg", "0.5mg"],
    searchTerms: ["alp", "alpr", "xan"],
  },
  {
    id: "tramadol-50",
    name: "Tramadol 50mg",
    genericName: "Tramadol",
    form: "Capsule",
    telemedicineList: "PROHIBITED",
    commonStrengths: ["50mg", "100mg"],
    searchTerms: ["tra", "tram", "ult"],
  },
];

async function main() {
  const batch = db.batch();

  for (const s of SPECIALTIES) {
    batch.set(db.collection(C.specialties).doc(s.code), { name: s.name });
  }

  for (const { id, ...doctor } of DOCTORS) {
    batch.set(db.collection(C.doctors).doc(id), doctor);
    rulesFor(id).forEach((rule, i) => {
      batch.set(db.collection(C.availabilityRules).doc(`${id}-r${i}`), rule);
    });
  }

  for (const { id, ...drug } of DRUGS) {
    batch.set(db.collection(C.drugs).doc(id), drug);
  }

  await batch.commit();
  console.log(
    `Seeded ${SPECIALTIES.length} specialties, ${DOCTORS.length} doctors with ` +
      `availability, and ${DRUGS.length} drugs.`
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
