import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error/failure.dart';
import '../core/feature_providers.dart';
import '../core/session/onboarding_controller.dart';
import '../features/notifications/data/push_service.dart';
import '../features/notifications/presentation/push_coordinator.dart';
import '../features/settings/domain/patient_profile.dart';
import '../features/settings/presentation/account_controller.dart';
import '../l10n/l10n.dart';
import '../shared/formatters.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _currentPage = 0;

  DateTime? _dateOfBirth;
  BloodGroup? _selectedBloodGroup;
  bool _saving = false;

  /// Starts unknown and is resolved on first build. Rendering the "enable"
  /// button to someone who already granted permission asks them to do
  /// something that is already done.
  PushPermission _pushPermission = PushPermission.notDetermined;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final current = await ref.read(pushServiceProvider).currentPermission();
      if (mounted) setState(() => _pushPermission = current);
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < 2) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: context.l10n.onboardingDateOfBirth,
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _finish() async {
    setState(() => _saving = true);

    // Clinical data is never written to the device: it goes straight to
    // `patientProfiles` behind the session. Both fields are optional here — a
    // patient who skips them should still reach the app, so a failure to save
    // them must not block onboarding.
    if (_dateOfBirth != null || _selectedBloodGroup != null) {
      try {
        await ref.read(accountRepositoryProvider).updateProfile(
              PatientProfileDraft(
                dateOfBirth: _dateOfBirth,
                bloodGroup: _selectedBloodGroup,
              ),
            );
        ref.invalidate(patientProfileProvider);
      } on Failure catch (f) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${f.message} You can add this later in Profile.'),
            ),
          );
        }
      }
    }

    await ref.read(onboardingControllerProvider.notifier).markComplete();
    // The router redirect moves the user to the patient shell once onboarding
    // is marked complete, so this screen does not navigate itself.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildWelcomePage(theme),
                  _buildProfilePage(theme),
                  _buildNotificationsPage(theme),
                ],
              ),
            ),
            _buildDots(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed:
                      _saving ? null : (_currentPage < 2 ? _next : _finish),
                  child: Text(
                    _currentPage < 2 ? 'Next' : 'Get Started',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Hero(
            tag: 'app-logo',
            child: Icon(Icons.health_and_safety,
                size: 88, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 24),
          Text('Your health, simplified',
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Track your health, book appointments, and stay connected with your care team.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePage(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Center(
            child: Icon(Icons.person_outline,
                size: 64, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text('Quick health profile',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(context.l10n.onboardingHealthBody,
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 28),
          Text(context.l10n.onboardingDateOfBirth,
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.cake_outlined),
              title: Text(
                _dateOfBirth == null
                    ? context.l10n.onboardingNotSet
                    : Fmt.date(_dateOfBirth!),
              ),
              subtitle: Text(context.l10n.onboardingDateOfBirthHelp),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDateOfBirth,
            ),
          ),
          const SizedBox(height: 24),
          Text(context.l10n.onboardingBloodGroup,
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: BloodGroup.values
                .map((bg) => ChoiceChip(
                      label: Text(bg.label),
                      selected: _selectedBloodGroup == bg,
                      onSelected: (_) =>
                          setState(() => _selectedBloodGroup = bg),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  /// The notifications step.
  ///
  /// This used to be a button whose handler was a comment and a snackbar that
  /// said "Notifications enabled" without asking the OS anything — the app
  /// claiming a capability it did not have. It now shows the real system
  /// prompt, reports the real answer, and says what will actually be sent.
  ///
  /// The copy no longer promises "medication schedules" either. There is no
  /// medication module, deliberately: adherence tracking implies drug-
  /// interaction liability nobody has scoped.
  Widget _buildNotificationsPage(ThemeData theme) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _pushPermission == PushPermission.granted
                ? Icons.notifications_active
                : Icons.notifications_active_outlined,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text('Stay in the loop',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            l10n.notificationsOnboardingBody,
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          switch (_pushPermission) {
            PushPermission.granted => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle,
                      color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(l10n.notificationsEnabled),
                ],
              ),
            // Once denied, the OS will not prompt again — only Settings can
            // change it. Offering the button again would be a button that
            // does nothing, so this says where to go instead.
            PushPermission.denied => Text(
                l10n.notificationsDenied,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            PushPermission.unsupported => const SizedBox.shrink(),
            PushPermission.notDetermined => OutlinedButton.icon(
                onPressed: _requestPush,
                icon: const Icon(Icons.notifications),
                label: Text(l10n.notificationsEnable),
              ),
          },
        ],
      ),
    );
  }

  Future<void> _requestPush() async {
    final push = ref.read(pushServiceProvider);
    final result = await push.requestPermission();
    if (!mounted) return;
    setState(() => _pushPermission = result);

    if (result != PushPermission.granted) return;

    // Registers immediately rather than waiting for the next launch: the
    // patient has just been told they will get reminders, and the first one
    // may be for an appointment they book in the next minute.
    final token = await push.token();
    if (token == null || !mounted) return;
    try {
      await ref.read(notificationRepositoryProvider).registerDevice(
            token: token,
            platform: defaultTargetPlatform.name,
          );
    } catch (_) {
      // The coordinator retries on the next launch or token refresh.
    }
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
