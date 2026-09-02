import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/skeleton.dart';
import '../data/doctor_fixtures.dart';
import '../domain/doctor.dart';
import 'doctor_search_controller.dart';

/// The client wireframe's speciality/location catalogue. It is available both
/// before sign-in and inside the signed-in patient experience.
class DoctorSearchScreen extends ConsumerWidget {
  const DoctorSearchScreen({super.key, this.publicBrowse = false});

  final bool publicBrowse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(doctorSearchFiltersProvider);
    final results = ref.watch(doctorSearchResultsProvider);
    final controller = ref.read(doctorSearchFiltersProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !publicBrowse,
        title: const Text('MiDoctor'),
        actions: publicBrowse
            ? [
                TextButton(
                  onPressed: () => context.push(Routes.login),
                  child: const Text('Login'),
                ),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Browse doctors by speciality or location',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _DropdownField<String>(
                          label: 'Speciality',
                          value: filters.specialtyCode,
                          items: DoctorFixtures.specialties
                              .map((specialty) => DropdownMenuItem(
                                    value: specialty.code,
                                    child: Text(specialty.name),
                                  ))
                              .toList(),
                          onChanged: controller.setSpecialty,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DropdownField<String>(
                          label: 'Location',
                          value: filters.city,
                          items: DoctorFixtures.cities
                              .map((city) => DropdownMenuItem(
                                    value: city,
                                    child: Text(city),
                                  ))
                              .toList(),
                          onChanged: controller.setCity,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: AsyncView<List<Doctor>>(
                value: results,
                onRetry: () => ref.invalidate(doctorSearchResultsProvider),
                skeleton: const SkeletonList(count: 5, rows: 3),
                data: (doctors) {
                  if (doctors.isEmpty) {
                    return EmptyState(
                      icon: Icons.search_off_outlined,
                      title: 'No doctors found',
                      message: 'Try a different speciality or location.',
                      action: FilledButton.tonal(
                        onPressed: controller.clearAll,
                        child: const Text('Clear filters'),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    itemCount: doctors.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, index) => FadeSlideIn(
                      index: index,
                      child: DoctorCard(
                        doctor: doctors[index],
                        publicBrowse: publicBrowse,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (publicBrowse)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => context.push(Routes.roleSelection),
                          child: const Text('Register'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.push(Routes.login),
                          child: const Text('Login'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem<T>(value: null, child: Text('All $label')),
          ...items,
        ],
        onChanged: onChanged,
      );
}

class DoctorCard extends StatelessWidget {
  const DoctorCard({super.key, required this.doctor, this.publicBrowse = false});

  final Doctor doctor;
  final bool publicBrowse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressableScale(
      child: Card(
        child: InkWell(
          onTap: () => context.push(
            publicBrowse
                ? Routes.publicDoctorDetail(doctor.id)
                : Routes.doctorDetail(doctor.id),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.primary,
                child: Text(
                  doctor.name.replaceFirst('Dr ', '').split(' ').map((part) => part[0]).take(2).join(),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doctor.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      doctor.specialtyLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('${doctor.yearsExperience} years experience'),
                    const SizedBox(height: 3),
                    Text('${doctor.hospital.city} · ${Fmt.rupees(doctor.consultationFeeInr)}'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.star_rounded, size: 18, color: Colors.amber.shade700),
                        const SizedBox(width: 3),
                        Text('${doctor.rating.toStringAsFixed(1)} (${doctor.ratingCount})'),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
