import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/appointments/data/api_appointment_repository.dart';
import '../features/appointments/data/appointment_repository.dart';
import '../features/appointments/data/cached_appointment_repository.dart';
import '../features/availability/data/api_availability_repository.dart';
import '../features/availability/data/availability_repository.dart';
import '../features/booking/data/api_booking_repository.dart';
import '../features/booking/data/booking_repository.dart';
import '../features/consent/data/api_consent_repository.dart';
import '../features/consent/data/consent_repository.dart';
import '../features/consultation/data/api_consultation_repository.dart';
import '../features/consultation/data/consultation_repository.dart';
import '../features/consultation/data/consultation_note_repository.dart';
import '../features/consultation/data/hms_telehealth_provider.dart';
import '../features/consultation/data/telehealth_provider.dart';
import '../features/credentials/data/api_credentials_repository.dart';
import '../features/credentials/data/credentials_repository.dart';
import '../features/prescriptions/data/api_prescription_repository.dart';
import '../features/prescriptions/data/cached_prescription_repository.dart';
import '../features/medications/data/medication_repository.dart';
import '../features/prescriptions/data/prescription_repository.dart';
import '../features/prescriptions/data/prescription_template_repository.dart';
import '../features/providers_search/data/api_doctor_repository.dart';
import '../features/providers_search/data/doctor_repository.dart';
import '../features/ratings/data/api_ratings_repository.dart';
import '../features/notifications/data/notification_repository.dart';
import '../features/ratings/data/ratings_repository.dart';
import '../features/records/data/api_records_repository.dart';
import '../features/records/data/records_repository.dart';
import '../features/settings/data/account_repository.dart';
import '../features/settings/data/device_session_repository.dart';
import '../features/support/data/api_support_repository.dart';
import '../features/support/data/support_repository.dart';
import 'files/blob_client.dart';
import 'providers.dart';
import 'service_providers.dart';
import 'storage/clinical_cache.dart';

/// Repository bindings for every feature.
///
/// Every surface now resolves to an API-backed implementation when
/// `USE_FIXTURES=false`, and to an in-memory fixture otherwise. The fixtures are
/// not scaffolding to be deleted: they are what keeps the whole app — router,
/// shells, interceptors, screens — runnable and testable without a backend, and
/// they mirror the server's semantics closely enough to be worth trusting.
///
///
/// Tests override any of these via `ProviderScope(overrides: [...])`. Keeping
/// them in one file makes a backend cutover a single reviewable diff rather
/// than a change scattered across a dozen feature folders.

final doctorRepositoryProvider = Provider<DoctorRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureDoctorRepository();
  return ApiDoctorRepository(ref.watch(apiClientProvider));
});

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureBookingRepository();
  return ApiBookingRepository(ref.watch(apiClientProvider));
});

/// Wraps whichever appointment repository is bound in an offline copy.
///
/// The decorator sits outside both implementations, so the caching policy is
/// in one readable place — and it wraps the fixture too, which is what makes
/// this testable on sample data: put the device in flight mode and the fixture
/// is never reached either.
final appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  return CachedAppointmentRepository(
    inner: ref.watch(_liveAppointmentRepositoryProvider),
    cache: ref.watch(clinicalCacheProvider),
    status: ref.watch(offlineCacheStatusProvider.notifier),
    // Read at call time rather than watched: a repository rebuilt on every
    // connectivity flap would drop in-flight requests every time a train
    // passes a tunnel.
    //
    // Unknown counts as online, and so does any failure to determine it. The
    // request fails on its own if there is no connection and the cache catches
    // that — whereas treating "I could not ask the platform" as offline would
    // serve a stored copy to someone with perfect signal.
    isOnline: () async {
      try {
        return ref.read(isOnlineProvider).value ?? true;
      } catch (_) {
        return true;
      }
    },
  );
});

final _liveAppointmentRepositoryProvider =
    Provider<AppointmentRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureAppointmentRepository();
  return ApiAppointmentRepository(ref.watch(apiClientProvider));
});

final recordsRepositoryProvider = Provider<RecordsRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureRecordsRepository();
  return ApiRecordsRepository(
    ref.watch(apiClientProvider),
    ref.watch(blobClientProvider),
  );
});

/// Profile plus the two DPDP rights that act on the whole account.
///
/// Backed by `/v1/me`, `/v1/me/export` and `DELETE /v1/me`, all of which exist.
final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureAccountRepository();
  return ApiAccountRepository(ref.watch(apiClientProvider));
});

/// Where this account is signed in.
final deviceSessionRepositoryProvider =
    Provider<DeviceSessionRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureDeviceSessionRepository();
  return ApiDeviceSessionRepository(ref.watch(apiClientProvider));
});

final consentRepositoryProvider = Provider<ConsentRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureConsentRepository();
  return ApiConsentRepository(ref.watch(apiClientProvider));
});

/// Wrapped in an offline copy, like appointments.
///
/// The most defensible list in the app to hold on a device: a patient at a
/// pharmacy counter with no signal is exactly who needs it, and it is the one
/// list where not being able to open the app has an immediate physical
/// consequence.
final prescriptionRepositoryProvider = Provider<PrescriptionRepository>((ref) {
  return CachedPrescriptionRepository(
    inner: ref.watch(_livePrescriptionRepositoryProvider),
    cache: ref.watch(clinicalCacheProvider),
    status: ref.watch(offlineCacheStatusProvider.notifier),
    isOnline: () async {
      try {
        return ref.read(isOnlineProvider).value ?? true;
      } catch (_) {
        return true;
      }
    },
  );
});

final _livePrescriptionRepositoryProvider =
    Provider<PrescriptionRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixturePrescriptionRepository();
  return ApiPrescriptionRepository(ref.watch(apiClientProvider));
});

/// The dose log.
///
/// Not cached offline, unlike prescriptions. The list of medicines is worth
/// holding on the device because a patient at a pharmacy counter needs it; the
/// record of which tablets they ticked is a write-heavy log with no value
/// without a connection, and queueing marks locally would mean reconciling two
/// versions of what somebody claims to have taken.
final medicationRepositoryProvider = Provider<MedicationRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureMedicationRepository();
  return ApiMedicationRepository(ref.watch(apiClientProvider));
});

/// A doctor's saved prescribing sets.
///
/// Not cached offline: a template is only useful inside the composer, which
/// needs the drug catalogue and a live consultation anyway.
final prescriptionTemplateRepositoryProvider =
    Provider<PrescriptionTemplateRepository>((ref) {
  if (ref.watch(useFixturesProvider)) {
    return FixturePrescriptionTemplateRepository();
  }
  return ApiPrescriptionTemplateRepository(ref.watch(apiClientProvider));
});

final credentialsRepositoryProvider = Provider<CredentialsRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureCredentialsRepository();
  return ApiCredentialsRepository(
    ref.watch(apiClientProvider),
    ref.watch(blobClientProvider),
  );
});

final availabilityRepositoryProvider = Provider<AvailabilityRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureAvailabilityRepository();
  return ApiAvailabilityRepository(ref.watch(apiClientProvider));
});

final ratingsRepositoryProvider = Provider<RatingsRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureRatingsRepository();
  return ApiRatingsRepository(ref.watch(apiClientProvider));
});

/// The fourteenth repository. Notifications are the one surface where the
/// fixture and the API differ in kind rather than in source: sample data files
/// notifications into an in-memory list and nothing is ever pushed, because
/// there is no FCM project behind it. Everything the user can *see* — the
/// centre, the unread count, the preferences, quiet hours — behaves identically
/// either way.
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureNotificationRepository();
  return ApiNotificationRepository(ref.watch(apiClientProvider));
});

/// The doctor's clinical note on a consultation.
///
/// Its own repository rather than part of records: a record is a file a patient
/// uploaded and a scanner cleared; a note is text a clinician authored, with a
/// different author, a different authorization rule and an append-only life.
final consultationNoteRepositoryProvider =
    Provider<ConsultationNoteRepository>((ref) {
  if (ref.watch(useFixturesProvider)) {
    return FixtureConsultationNoteRepository();
  }
  return ApiConsultationNoteRepository(ref.watch(apiClientProvider));
});

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureSupportRepository();
  return ApiSupportRepository(ref.watch(apiClientProvider));
});

final consultationRepositoryProvider = Provider<ConsultationRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureConsultationRepository();
  return ApiConsultationRepository(
    ref.watch(apiClientProvider),
    // Chat needs to know which messages are the caller's own; the server sends
    // a sender id rather than a flag, because "mine" differs per participant.
    currentUserId: ref.watch(currentSessionProvider)?.userId ?? '',
  );
});

/// Media vendor for live consultations.
///
/// Resolves to 100ms once the API can mint join tokens; until then the fixture
/// keeps the whole consultation flow — consent gate, waiting room, controls,
/// chat, audio fallback — exercisable without a vendor account.
///
/// Nothing outside [TelehealthProvider] knows which one is in use.
final telehealthProviderProvider = Provider<TelehealthProvider>((ref) {
  if (ref.watch(useFixturesProvider)) {
    final provider = FixtureTelehealthProvider();
    ref.onDispose(provider.dispose);
    return provider;
  }
  // 100ms is Android/iOS only. Its method-channel Dart surface compiles for web
  // and then throws MissingPluginException on join, so web is bound to the
  // unsupported stub and fails as a readable message instead of a crash.
  if (kIsWeb) return const UnsupportedTelehealthProvider();

  final provider = HmsTelehealthProvider(api: ref.watch(apiClientProvider));
  ref.onDispose(provider.dispose);
  return provider;
});
