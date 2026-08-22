/// Route paths, hand-written so there is exactly one place to change them.
///
/// go_router_builder is deliberately not used: it would be the project's only
/// codegen step, and route strings are the part of this app least in need of
/// type generation.
abstract final class Routes {
  static const splash = '/splash';

  // --- Auth ----------------------------------------------------------------
  static const login = '/auth/login';
  static const roleSelection = '/auth/role';
  static const signup = '/auth/signup';
  static const phone = '/auth/phone';
  static const otp = '/auth/otp';

  // --- Onboarding ----------------------------------------------------------
  static const onboardingPatient = '/onboarding/patient';

  // --- Patient shell -------------------------------------------------------
  static const patientHome = '/patient/home';
  static const patientAppointments = '/patient/appointments';
  static const patientRecords = '/patient/records';
  static const patientProfile = '/patient/profile';

  /// Doctor search lives under the Home branch so "Book" keeps the bottom nav.
  static const doctorSearch = '/patient/doctors';

  // --- Patient: pushed routes ---------------------------------------------
  static const bookingConfirmed = '/patient/booking-confirmed';
  static const sharing = '/patient/sharing';
  static const recordUpload = '/patient/records/upload';
  static const prescriptions = '/patient/prescriptions';
  static const refills = '/patient/refills';
  static const medications = '/patient/medications';

  /// The doctor's write-up of one consultation. Same screen both sides.
  static String consultationNote(String appointmentId) =>
      '/consultation-note/$appointmentId';
  static const supportTickets = '/patient/support';
  static const notifications = '/patient/notifications';
  static const notificationSettings = '/patient/notifications/settings';
  static const settings = '/patient/settings';
  static const editProfile = '/patient/settings/profile';
  static const privacy = '/patient/settings/privacy';

  static String doctorDetail(String id) => '$doctorSearch/$id';
  static String booking(String id) => '$doctorSearch/$id/book';
  static String appointmentDetail(String id) => '$patientAppointments/$id';
  static String recordDetail(String id) => '$patientRecords/$id';
  static String prescriptionDetail(String id) => '$prescriptions/$id';
  static String consultation(String id) => '/patient/consultation/$id';
  static String rateAppointment(String id) => '/patient/rate/$id';

  // --- Provider shell ------------------------------------------------------
  static const providerToday = '/provider/today';
  static const providerSchedule = '/provider/schedule';
  static const providerPatients = '/provider/patients';
  static const providerProfile = '/provider/profile';
  static const providerRatings = '/provider/ratings';
  static const providerRefills = '/provider/refills';

  /// Terminal screen for a provider who is not APPROVED. Mirrors the RBAC
  /// matrix, where an unverified provider may only read their own profile and
  /// submit credentials.
  static const providerVerification = '/provider/verification';
  static const providerCredentials = '/provider/verification/credentials';
  static const providerMfa = '/provider/verification/mfa';

  static String providerPrescribe(String appointmentId) =>
      '/provider/prescribe/$appointmentId';
  static String providerConsultation(String id) => '/provider/consultation/$id';

  /// Terminal screen for a suspended or deactivated account, and for staff
  /// roles that this app has no UI for.
  static const blocked = '/blocked';
}
