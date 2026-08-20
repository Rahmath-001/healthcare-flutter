import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error/failure.dart';
import '../core/feature_providers.dart';
import '../core/session/onboarding_controller.dart';
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

  Widget _buildNotificationsPage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_active_outlined,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text('Stay in the loop',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Get reminders for appointments, medication schedules, and health tips.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () {
              // In production: request notification permission here.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notifications enabled')),
              );
            },
            icon: const Icon(Icons.notifications),
            label: const Text('Enable notifications'),
          ),
        ],
      ),
    );
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
