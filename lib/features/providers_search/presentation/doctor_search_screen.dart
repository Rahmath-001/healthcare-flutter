import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../utils/debouncer.dart';
import '../data/doctor_fixtures.dart';
import '../domain/doctor.dart';
import 'doctor_search_controller.dart';

class DoctorSearchScreen extends ConsumerStatefulWidget {
  const DoctorSearchScreen({super.key});

  @override
  ConsumerState<DoctorSearchScreen> createState() => _DoctorSearchScreenState();
}

class _DoctorSearchScreenState extends ConsumerState<DoctorSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 350));

  @override
  void dispose() {
    _debouncer.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    // Debounced so typing does not fire a request per keystroke. The API
    // request itself is cancellable via Dio's CancelToken.
    _debouncer.run(() {
      if (mounted) {
        ref.read(doctorSearchFiltersProvider.notifier).setQuery(value);
      }
    });
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(doctorSearchFiltersProvider);
    final results = ref.watch(doctorSearchResultsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.searchTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onQueryChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: context.l10n.searchDoctorHint,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  ref
                                      .read(
                                          doctorSearchFiltersProvider.notifier)
                                      .setQuery('');
                                  setState(() {});
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Badge(
                    isLabelVisible: filters.activeCount > 0,
                    label: Text('${filters.activeCount}'),
                    child: IconButton.filledTonal(
                      onPressed: _openFilters,
                      icon: const Icon(Icons.tune),
                      tooltip: context.l10n.searchFilters,
                    ),
                  ),
                ],
              ),
            ),
            const _SpecialtyChips(),
            const Divider(height: 1),
            Expanded(
              child: AsyncView<List<Doctor>>(
                value: results,
                onRetry: () => ref.invalidate(doctorSearchResultsProvider),
                skeleton: const SkeletonList(
                  count: 4,
                  rows: 4,
                  padding: EdgeInsets.all(Insets.lg),
                ),
                data: (doctors) {
                  if (doctors.isEmpty) {
                    return EmptyState(
                      icon: Icons.search_off_outlined,
                      title: context.l10n.searchNoMatch,
                      message: context.l10n.searchNoResultsBody,
                      action: filters.activeCount > 0
                          ? FilledButton.tonal(
                              onPressed: () => ref
                                  .read(doctorSearchFiltersProvider.notifier)
                                  .clearFilters(),
                              child: Text(context.l10n.searchClearFiltersShort),
                            )
                          : null,
                    );
                  }
                  return ListView.separated(
                    // The count is a list item rather than a fixed header, so
                    // it scrolls away with the results instead of eating a row
                    // of a short phone permanently.
                    padding: const EdgeInsets.fromLTRB(
                      Insets.lg,
                      Insets.md,
                      Insets.lg,
                      Insets.xl,
                    ),
                    itemCount: doctors.length + 1,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Insets.md),
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return Text(
                          context.l10n.searchResultCount(doctors.length),
                          style: Theme.of(context).textTheme.labelMedium,
                        );
                      }
                      return FadeSlideIn(
                        // Search results are replaced wholesale on every
                        // keystroke past the debounce.
                        key: ValueKey(doctors[i - 1].id),
                        index: i - 1,
                        child: DoctorCard(doctor: doctors[i - 1]),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecialtyChips extends ConsumerWidget {
  const _SpecialtyChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(doctorSearchFiltersProvider).specialtyCode;

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: DoctorFixtures.specialties.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final specialty = DoctorFixtures.specialties[i];
          final isSelected = selected == specialty.code;
          return FilterChip(
            label: Text(specialty.name),
            selected: isSelected,
            onSelected: (_) => ref
                .read(doctorSearchFiltersProvider.notifier)
                .setSpecialty(isSelected ? null : specialty.code),
          );
        },
      ),
    );
  }
}

class DoctorCard extends StatelessWidget {
  const DoctorCard({super.key, required this.doctor});

  final Doctor doctor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PressableScale(
      child: Card(
        child: InkWell(
          onTap: () => context.push('${Routes.doctorSearch}/${doctor.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: doctor.photoUrl != null
                          ? NetworkImage(doctor.photoUrl!)
                          : null,
                      child: doctor.photoUrl == null
                          ? Text(
                              doctor.name.split(' ').last[0],
                              style: theme.textTheme.titleLarge,
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(doctor.name, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            doctor.specialtyLabel,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: theme.colorScheme.primary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${doctor.qualification} · ${doctor.yearsExperience} yrs',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          StarRating(
                            rating: doctor.rating,
                            count: doctor.ratingCount,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.local_hospital_outlined,
                        size: 16, color: theme.colorScheme.outline),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${doctor.hospital.name}, ${doctor.hospital.city}',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ...doctor.modes.map((m) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: StatusChip(
                            label: m.label,
                            tone: Tone.brand,
                            icon: switch (m) {
                              ConsultationMode.inPerson => Icons.person_outline,
                              ConsultationMode.video => Icons.videocam_outlined,
                              ConsultationMode.audio => Icons.call_outlined,
                            },
                          ),
                        )),
                    const Spacer(),
                    Text(
                      Fmt.rupees(doctor.consultationFeeInr),
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(doctorSearchFiltersProvider);
    final notifier = ref.read(doctorSearchFiltersProvider.notifier);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(context.l10n.searchFilters,
                    style: theme.textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: notifier.clearFilters,
                  child: Text(context.l10n.searchClearFilters),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.l10n.searchMode, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ConsultationMode.values
                  .map((m) => ChoiceChip(
                        label: Text(m.label),
                        selected: filters.mode == m,
                        onSelected: (_) =>
                            notifier.setMode(filters.mode == m ? null : m),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            Text(context.l10n.searchCity, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: DoctorFixtures.cities
                  .map((c) => ChoiceChip(
                        label: Text(c),
                        selected: filters.city == c,
                        onSelected: (_) =>
                            notifier.setCity(filters.city == c ? null : c),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            Text(context.l10n.searchMaxFee, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: const [500, 750, 1000, 1500]
                  .map((fee) => ChoiceChip(
                        label:
                            Text(context.l10n.searchUpToFee(Fmt.rupees(fee))),
                        selected: filters.maxFeeInr == fee,
                        onSelected: (_) => notifier
                            .setMaxFee(filters.maxFeeInr == fee ? null : fee),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            Text(context.l10n.searchMinRating,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: const [4.0, 4.5, 4.8]
                  .map((r) => ChoiceChip(
                        label: Text('$r+'),
                        selected: filters.minRating == r,
                        onSelected: (_) => notifier
                            .setMinRating(filters.minRating == r ? null : r),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),

            // FR-SRCH-002 lists Fee, Rating and Availability as filters.
            SwitchListTile(
              value: filters.availableToday,
              onChanged: notifier.setAvailableToday,
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.searchAvailableToday),
              subtitle: Text(context.l10n.searchAvailableTodayBody),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.searchApply),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
