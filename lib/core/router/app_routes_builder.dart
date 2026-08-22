import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/appointments/domain/appointment.dart';
import '../../features/appointments/presentation/appointment_detail_screen.dart';
import '../../features/appointments/presentation/appointments_screen.dart';
import '../../features/availability/presentation/availability_screen.dart';
import '../../features/auth/presentation/role_selection_screen.dart';
import '../../features/blocked/presentation/blocked_screen.dart';
import '../../features/booking/presentation/booking_confirmed_screen.dart';
import '../../features/booking/presentation/booking_screen.dart';
import '../../features/consent/presentation/sharing_screen.dart';
import '../../features/consultation/presentation/consultation_note_screen.dart';
import '../../features/consultation/presentation/consultation_screen.dart';
import '../../features/credentials/presentation/credentials_screen.dart';
import '../../features/mfa/presentation/mfa_enrolment_screen.dart';
import '../../features/medications/presentation/medications_screen.dart';
import '../../features/prescriptions/presentation/prescribe_screen.dart';
import '../../features/prescriptions/presentation/prescriptions_screen.dart';
import '../../features/prescriptions/presentation/refills_screen.dart';
import '../../features/provider_home/presentation/provider_tabs.dart';
import '../../features/provider_home/presentation/provider_today_screen.dart';
import '../../features/provider_verification/presentation/provider_verification_screen.dart';
import '../../features/providers_search/presentation/doctor_detail_screen.dart';
import '../../features/providers_search/presentation/doctor_search_screen.dart';
import '../../features/ratings/presentation/provider_ratings_screen.dart';
import '../../features/ratings/presentation/rate_appointment_screen.dart';
import '../../features/records/presentation/record_detail_screen.dart';
import '../../features/records/presentation/record_upload_screen.dart';
import '../../features/records/presentation/records_screen.dart';
import '../../features/settings/presentation/edit_profile_screen.dart';
import '../../features/settings/presentation/privacy_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/notifications/presentation/notification_settings_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/support/presentation/support_screen.dart';
import '../../screens/login_screen.dart';
import '../../screens/onboarding_screen.dart';
import '../../screens/otp_screen.dart';
import '../../screens/phone_input_screen.dart';
import '../../screens/signup_screen.dart';
import '../../screens/tabs/home_tab.dart';
import '../../screens/tabs/profile_tab.dart';
import '../../l10n/l10n.dart';
import '../security/screen_protection.dart';
import 'routes.dart';

/// Bottom-nav scaffold shared by both shells.
class ShellScaffold extends StatelessWidget {
  const ShellScaffold({
    super.key,
    required this.navigationShell,
    required this.destinations,
  });

  final StatefulNavigationShell navigationShell;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        destinations: destinations,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          // Tapping the active tab returns it to its root, which is the
          // behaviour users expect from a bottom nav.
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

/// Two shells rather than one shell with conditional tabs.
///
/// Patient and provider journeys diverge enough — Book vs Schedule, Records vs
/// Patients — that a single shell full of `if (role == ...)` would rot quickly.
/// Separate shells also make it structurally impossible for a patient build to
/// render a provider tab.
List<RouteBase> buildRoutes() => [
      GoRoute(
        path: Routes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.blocked,
        builder: (_, __) => const BlockedScreen(),
      ),

      // --- Auth ------------------------------------------------------------
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: Routes.roleSelection,
        builder: (_, __) => const RoleSelectionScreen(),
      ),
      GoRoute(path: Routes.signup, builder: (_, __) => const SignupScreen()),
      GoRoute(
        path: Routes.phone,
        builder: (_, state) => PhoneInputScreen(
          displayName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: Routes.otp,
        builder: (_, state) => OtpScreen(
          e164: state.uri.queryParameters['phone'] ?? '',
          displayName: state.uri.queryParameters['name'],
        ),
      ),

      // --- Onboarding ------------------------------------------------------
      GoRoute(
        path: Routes.onboardingPatient,
        builder: (_, __) => const OnboardingScreen(),
      ),

      // --- Patient: pushed over the shell ----------------------------------
      GoRoute(
        path: Routes.bookingConfirmed,
        builder: (_, state) =>
            BookingConfirmedScreen(appointment: state.extra! as Appointment),
      ),
      GoRoute(
        path: Routes.sharing,
        builder: (_, __) => const ProtectedScreen(child: SharingScreen()),
      ),
      GoRoute(
          path: Routes.settings, builder: (_, __) => const SettingsScreen()),
      GoRoute(path: Routes.privacy, builder: (_, __) => const PrivacyScreen()),
      GoRoute(
        path: Routes.editProfile,
        // Carries allergies and chronic conditions in free text — the same
        // class of data as a record, and previously the only PHI screen with
        // no screenshot protection at all.
        builder: (_, __) => const ProtectedScreen(child: EditProfileScreen()),
      ),
      GoRoute(
        // Outside both shells: one document, read by the patient and appended
        // to by the doctor who wrote it. Two routes would mean two renderings
        // of the same clinical text.
        path: '/consultation-note/:id',
        builder: (_, state) => ProtectedScreen(
          child: ConsultationNoteScreen(
            appointmentId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: Routes.refills,
        builder: (_, __) => const ProtectedScreen(child: RefillsScreen()),
      ),
      GoRoute(
        path: Routes.providerRefills,
        builder: (_, __) => const ProtectedScreen(child: RefillsScreen()),
      ),
      GoRoute(
        path: Routes.notifications,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.notificationSettings,
        builder: (_, __) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: Routes.supportTickets,
        builder: (_, __) => const SupportScreen(),
      ),
      GoRoute(
        path: '/patient/consultation/:id',
        builder: (_, state) => ProtectedScreen(
          child: ConsultationScreen(
            consultationId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/patient/rate/:id',
        builder: (_, state) => RateAppointmentScreen(
          appointmentId: state.pathParameters['id']!,
        ),
      ),

      // --- Provider: verification path -------------------------------------
      GoRoute(
        path: Routes.providerVerification,
        builder: (_, __) => const ProviderVerificationScreen(),
      ),
      GoRoute(
        path: Routes.providerCredentials,
        builder: (_, __) => const CredentialsScreen(),
      ),
      GoRoute(
        path: Routes.providerRatings,
        builder: (_, __) => const ProviderRatingsScreen(),
      ),
      GoRoute(
        path: Routes.providerMfa,
        // Renders the TOTP seed, its QR code and the recovery codes. A
        // screenshot of this screen is a permanent second-factor bypass
        // sitting in the gallery.
        builder: (_, __) => const ProtectedScreen(child: MfaEnrolmentScreen()),
      ),
      GoRoute(
        path: '/provider/prescribe/:id',
        // A prescription being composed names the patient, the diagnosis and
        // the drug. Protected on the way in, not only once it is issued and
        // showing on the patient's device.
        builder: (_, state) => ProtectedScreen(
          child: PrescribeScreen(
            appointmentId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/provider/consultation/:id',
        builder: (_, state) => ProtectedScreen(
          child: ConsultationScreen(
            consultationId: state.pathParameters['id']!,
          ),
        ),
      ),

      // --- Patient shell ---------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (context, __, shell) => ShellScaffold(
          navigationShell: shell,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: context.l10n.navHome,
            ),
            NavigationDestination(
              icon: const Icon(Icons.calendar_month_outlined),
              selectedIcon: const Icon(Icons.calendar_month),
              label: context.l10n.navAppointments,
            ),
            NavigationDestination(
              icon: const Icon(Icons.folder_shared_outlined),
              selectedIcon: const Icon(Icons.folder_shared),
              label: context.l10n.navRecords,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: context.l10n.navProfile,
            ),
          ],
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.patientHome,
              builder: (_, __) => const HomeTab(),
            ),
            GoRoute(
              path: Routes.doctorSearch,
              builder: (_, __) => const DoctorSearchScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, state) => DoctorDetailScreen(
                    doctorId: state.pathParameters['id']!,
                  ),
                  routes: [
                    GoRoute(
                      path: 'book',
                      builder: (_, state) => BookingScreen(
                        doctorId: state.pathParameters['id']!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.patientAppointments,
              builder: (_, __) => const AppointmentsScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  // Shows the reason for visit and any linked prescription.
                  builder: (_, state) => ProtectedScreen(
                    child: AppointmentDetailScreen(
                      appointmentId: state.pathParameters['id']!,
                    ),
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.patientRecords,
              builder: (_, __) => const ProtectedScreen(child: RecordsScreen()),
              routes: [
                GoRoute(
                  path: 'upload',
                  builder: (_, __) => const RecordUploadScreen(),
                ),
                // Must stay after 'upload' — go_router matches children in
                // order, and ':id' would otherwise swallow that literal path.
                GoRoute(
                  path: ':id',
                  builder: (_, state) => ProtectedScreen(
                    child: RecordDetailScreen(
                      recordId: state.pathParameters['id']!,
                    ),
                  ),
                ),
              ],
            ),
            // Renders drug names, so it is PHI and wrapped like every other
            // screen that shows any.
            GoRoute(
              path: Routes.medications,
              builder: (_, __) =>
                  const ProtectedScreen(child: MedicationsScreen()),
            ),
            GoRoute(
              path: Routes.prescriptions,
              builder: (_, __) =>
                  const ProtectedScreen(child: PrescriptionsScreen()),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, state) => ProtectedScreen(
                    child: PrescriptionDetailScreen(
                      prescriptionId: state.pathParameters['id']!,
                    ),
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.patientProfile,
              builder: (_, __) => const ProfileTab(),
            ),
          ]),
        ],
      ),

      // --- Provider shell (approved only) ----------------------------------
      StatefulShellRoute.indexedStack(
        builder: (context, __, shell) => ShellScaffold(
          navigationShell: shell,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.today_outlined),
              selectedIcon: const Icon(Icons.today),
              label: context.l10n.navToday,
            ),
            NavigationDestination(
              icon: const Icon(Icons.event_available_outlined),
              selectedIcon: const Icon(Icons.event_available),
              label: context.l10n.navSchedule,
            ),
            NavigationDestination(
              icon: const Icon(Icons.folder_shared_outlined),
              selectedIcon: const Icon(Icons.folder_shared),
              label: context.l10n.navPatients,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: context.l10n.navProfile,
            ),
          ],
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.providerToday,
              builder: (_, __) => const ProviderTodayScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.providerSchedule,
              builder: (_, __) => const AvailabilityScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.providerPatients,
              builder: (_, __) => const ProviderPatientsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.providerProfile,
              builder: (_, __) => const ProviderProfileTab(),
            ),
          ]),
        ],
      ),
    ];
