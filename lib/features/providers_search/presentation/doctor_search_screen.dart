import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/skeleton.dart';
import '../domain/doctor.dart';
import 'doctor_search_controller.dart';

/// The client wireframe's live speciality/location directory. It is available
/// both before sign-in and inside the signed-in patient experience.
class DoctorSearchScreen extends ConsumerWidget {
  const DoctorSearchScreen({super.key, this.publicBrowse = false});

  final bool publicBrowse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(doctorSearchFiltersProvider);
    final results = ref.watch(doctorSearchResultsProvider);
    final specialties =
        ref.watch(doctorSpecialtiesProvider).value ?? const <Specialty>[];
    final cities = ref.watch(doctorCitiesProvider).value ?? const <String>[];
    final controller = ref.read(doctorSearchFiltersProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !publicBrowse,
        title: const Text('MiDoctor'),
        actions: publicBrowse
            ? [
                TextButton(
                  onPressed: () => context.push('/hospitals'),
                  child: const Text('Hospitals'),
                ),
                TextButton(
                  onPressed: () =>
                      context.push('${Routes.login}?wireframe=true'),
                  child: const Text('Login'),
                ),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
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
                          child: _SearchableFilterField<Specialty>(
                            label: 'Speciality',
                            allLabel: 'All specialities',
                            value: filters.specialtyCode == null
                                ? null
                                : specialties
                                    .where(
                                      (specialty) =>
                                          specialty.code ==
                                          filters.specialtyCode,
                                    )
                                    .firstOrNull,
                            options: specialties,
                            optionLabel: (specialty) => specialty.name,
                            onSelected: (specialty) {
                              controller.setQuery('');
                              controller.setSpecialty(specialty?.code);
                            },
                            onTyped: (query) {
                              controller.setSpecialty(null);
                              controller.setQuery(query);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SearchableFilterField<String>(
                            label: 'Location',
                            allLabel: 'All locations',
                            value: filters.city,
                            options: cities,
                            optionLabel: (city) => city,
                            onSelected: controller.setCity,
                            onTyped: (query) {
                              controller.setCity(null);
                              controller.setQuery(query);
                            },
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
                    return RefreshIndicator(
                      onRefresh: () async {
                        await Future.wait([
                          ref.refresh(doctorSearchResultsProvider.future),
                          ref.refresh(doctorSpecialtiesProvider.future),
                          ref.refresh(doctorCitiesProvider.future),
                        ]);
                      },
                      child: Scrollbar(
                        thumbVisibility: true,
                        interactive: true,
                        thickness: 5,
                        radius: const Radius.circular(8),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 16, 12, 24),
                          itemCount: doctors.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, index) => FadeSlideIn(
                            index: index,
                            child: DoctorCard(
                              doctor: doctors[index],
                              publicBrowse: publicBrowse,
                            ),
                          ),
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
                            onPressed: () =>
                                context.push('${Routes.login}?wireframe=true'),
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
      ),
    );
  }
}

/// An editable picker that keeps the familiar select affordance without
/// trapping a patient inside a long native dropdown. Typing filters the list
/// underneath the field; a free-text speciality also searches the catalogue.
class _SearchableFilterField<T extends Object> extends StatefulWidget {
  const _SearchableFilterField({
    required this.label,
    required this.allLabel,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onSelected,
    required this.onTyped,
  });

  final String label;
  final String allLabel;
  final T? value;
  final List<T> options;
  final String Function(T option) optionLabel;
  final ValueChanged<T?> onSelected;
  final ValueChanged<String> onTyped;

  @override
  State<_SearchableFilterField<T>> createState() =>
      _SearchableFilterFieldState<T>();
}

class _SearchableFilterFieldState<T extends Object>
    extends State<_SearchableFilterField<T>> {
  TextEditingController? _controller;
  String _typedValue = '';

  @override
  void didUpdateWidget(covariant _SearchableFilterField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value || _controller == null) return;

    // Selecting a suggestion should replace the typed text. Clearing a
    // selected filter should not erase a new free-text query while it is being
    // entered.
    if (widget.value != null) {
      final label = widget.optionLabel(widget.value as T);
      _controller!.value = TextEditingValue(
        text: label,
        selection: TextSelection.collapsed(offset: label.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Autocomplete<T>(
      displayStringForOption: widget.optionLabel,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return widget.options;
        return widget.options.where(
          (option) => widget.optionLabel(option).toLowerCase().contains(query),
        );
      },
      onSelected: (option) {
        widget.onSelected(option);
        setState(() => _typedValue = widget.optionLabel(option));
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        _controller = controller;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onChanged: (value) {
            setState(() => _typedValue = value);
            widget.onTyped(value);
          },
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.allLabel,
            prefixIcon: const Icon(Icons.search_outlined),
            suffixIcon: controller.text.isEmpty
                ? IconButton(
                    tooltip: focusNode.hasFocus
                        ? 'Close ${widget.label.toLowerCase()} options'
                        : 'Show ${widget.label.toLowerCase()} options',
                    icon: Icon(
                      focusNode.hasFocus
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                    ),
                    onPressed: () {
                      if (focusNode.hasFocus) {
                        focusNode.unfocus();
                      } else {
                        focusNode.requestFocus();
                      }
                    },
                  )
                : IconButton(
                    tooltip: 'Clear ${widget.label.toLowerCase()}',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      controller.clear();
                      setState(() => _typedValue = '');
                      widget.onSelected(null);
                      widget.onTyped('');
                      focusNode.requestFocus();
                    },
                  ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final matches = options.toList(growable: false);
        final hasQuery = _typedValue.trim().isNotEmpty;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: scheme.surface,
            elevation: 10,
            shadowColor: scheme.shadow.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 224),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                children: [
                  if (matches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No matching ${widget.label.toLowerCase()}.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  else
                    ...matches.map(
                      (option) => ListTile(
                        dense: true,
                        minTileHeight: 44,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        title: Text(widget.optionLabel(option)),
                        trailing: widget.value == option
                            ? Icon(Icons.check_rounded, color: scheme.primary)
                            : null,
                        onTap: () => onSelected(option),
                      ),
                    ),
                  if (hasQuery && widget.value == null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.manage_search_rounded,
                            size: 20,
                            color: scheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Searching “${_typedValue.trim()}”',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class DoctorCard extends StatelessWidget {
  const DoctorCard(
      {super.key, required this.doctor, this.publicBrowse = false});

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
                  backgroundImage: doctor.photoUrl == null
                      ? null
                      : AssetImage(doctor.photoUrl!),
                  child: doctor.photoUrl == null
                      ? Text(
                          doctor.name
                              .replaceFirst('Dr ', '')
                              .split(' ')
                              .map((part) => part[0])
                              .take(2)
                              .join(),
                          style: theme.textTheme.titleMedium,
                        )
                      : null,
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
                      Text(
                          '${doctor.hospital.city} · ${Fmt.rupees(doctor.consultationFeeInr)}'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.star_rounded,
                              size: 18, color: Colors.amber.shade700),
                          const SizedBox(width: 3),
                          Text(
                              '${doctor.rating.toStringAsFixed(1)} (${doctor.ratingCount})'),
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
