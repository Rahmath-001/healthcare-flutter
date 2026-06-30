import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/onboarding_service.dart';
import 'dashboard_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _currentPage = 0;

  String? _selectedAge;
  String? _selectedBloodGroup;

  static const _ageRanges = [
    '18-24', '25-34', '35-44', '45-54', '55-64', '65+',
  ];

  static const _bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-',
  ];

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

  Future<void> _finish() async {
    final svc = context.read<OnboardingService>();
    await svc.saveProfile(age: _selectedAge, bloodGroup: _selectedBloodGroup);
    await svc.markComplete();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
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
                  onPressed: _currentPage < 2 ? _next : _finish,
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
          Text('Help us personalize your experience.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 28),
          Text('Age range', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ageRanges
                .map((a) => ChoiceChip(
                      label: Text(a),
                      selected: _selectedAge == a,
                      onSelected: (_) => setState(() => _selectedAge = a),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
          Text('Blood group', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _bloodGroups
                .map((bg) => ChoiceChip(
                      label: Text(bg),
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
