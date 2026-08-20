import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../../providers_search/domain/doctor.dart';
import '../domain/availability.dart';

final availabilityRulesProvider =
    FutureProvider<List<AvailabilityRule>>((ref) async {
  return ref.watch(availabilityRepositoryProvider).rules();
});

final availabilityExceptionsProvider =
    FutureProvider<List<AvailabilityException>>((ref) async {
  return ref.watch(availabilityRepositoryProvider).exceptions();
});

/// Provider availability editor.
///
/// The RBAC matrix grants "Manage Availability" but the spec defines no module
/// behind it. Without this screen a doctor can be approved and still have no
/// bookable slots, which makes search results unbookable.
class AvailabilityScreen extends ConsumerWidget {
  const AvailabilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(availabilityRulesProvider);
    final exceptions = ref.watch(availabilityExceptionsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.availabilityMySchedule)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const _AddRuleSheet(),
        ),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.availabilityAddHours),
      ),
      body: AsyncView<List<AvailabilityRule>>(
        value: rules,
        onRetry: () => ref.invalidate(availabilityRulesProvider),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.event_available_outlined,
              title: context.l10n.availabilityNone,
              message: 'Add your weekly hours so patients can book with you.',
            );
          }

          final byDay = <int, List<AvailabilityRule>>{};
          for (final r in list) {
            byDay.putIfAbsent(r.weekday, () => []).add(r);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              for (final weekday in byDay.keys.toList()..sort()) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 4),
                  child: Text(
                    AvailabilityRule.weekdayNames[weekday] ?? '',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                ...byDay[weekday]!.map((r) => _RuleCard(rule: r)),
                const SizedBox(height: 12),
              ],
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(context.l10n.availabilityDaysOff,
                    style: theme.textTheme.titleSmall),
              ),
              ...(exceptions.value ?? const <AvailabilityException>[])
                  .map((e) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.event_busy_outlined),
                          title: Text(Fmt.date(e.date)),
                          subtitle: Text(e.reason ?? 'Not available'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await ref
                                  .read(availabilityRepositoryProvider)
                                  .deleteException(e.id);
                              ref.invalidate(availabilityExceptionsProvider);
                            },
                          ),
                        ),
                      )),
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 180)),
                    helpText: 'Which day are you unavailable?',
                  );
                  if (date == null) return;
                  await ref.read(availabilityRepositoryProvider).blockDay(date);
                  ref.invalidate(availabilityExceptionsProvider);
                },
                icon: const Icon(Icons.event_busy_outlined, size: 18),
                label: Text(context.l10n.availabilityMarkDayOff),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RuleCard extends ConsumerWidget {
  const _RuleCard({required this.rule});

  final AvailabilityRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final r = rule;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          switch (r.mode) {
            ConsultationMode.inPerson => Icons.person_outline,
            ConsultationMode.video => Icons.videocam_outlined,
            ConsultationMode.audio => Icons.call_outlined,
          },
          color: r.isActive ? theme.colorScheme.primary : theme.disabledColor,
        ),
        title: Text('${r.start.format()} - ${r.end.format()}'),
        subtitle: Text(
          '${r.mode.label} · ${r.slotMinutes} min slots · '
          '${r.slotCount} appointments',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: r.isActive,
              onChanged: (v) async {
                await ref
                    .read(availabilityRepositoryProvider)
                    .toggleRule(r.id, active: v);
                ref.invalidate(availabilityRulesProvider);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref.read(availabilityRepositoryProvider).deleteRule(r.id);
                ref.invalidate(availabilityRulesProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AddRuleSheet extends ConsumerStatefulWidget {
  const _AddRuleSheet();

  @override
  ConsumerState<_AddRuleSheet> createState() => _AddRuleSheetState();
}

class _AddRuleSheetState extends ConsumerState<_AddRuleSheet> {
  int _weekday = DateTime.monday;
  TimeOfDayValue _start = const TimeOfDayValue(9, 0);
  TimeOfDayValue _end = const TimeOfDayValue(13, 0);
  ConsultationMode _mode = ConsultationMode.video;
  int _slotMinutes = 30;
  bool _saving = false;

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (picked == null) return;
    setState(() {
      final value = TimeOfDayValue(picked.hour, picked.minute);
      if (isStart) {
        _start = value;
      } else {
        _end = value;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(availabilityRepositoryProvider).addRule(
            weekday: _weekday,
            start: _start,
            end: _end,
            mode: _mode,
            slotMinutes: _slotMinutes,
          );
      ref.invalidate(availabilityRulesProvider);
      if (mounted) Navigator.of(context).pop();
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.availabilityAddAvailability,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(context.l10n.availabilityDay,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: AvailabilityRule.weekdayNames.entries
                  .map((e) => ChoiceChip(
                        label: Text(e.value.substring(0, 3)),
                        selected: _weekday == e.key,
                        onSelected: (_) => setState(() => _weekday = e.key),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isStart: true),
                    child: Text('From ${_start.format()}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isStart: false),
                    child: Text('To ${_end.format()}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(context.l10n.availabilityConsultationType,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ConsultationMode.values
                  .map((m) => ChoiceChip(
                        label: Text(m.label),
                        selected: _mode == m,
                        onSelected: (_) => setState(() => _mode = m),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Text(context.l10n.availabilityAppointmentLength,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: const [10, 15, 20, 30, 45]
                  .map((m) => ChoiceChip(
                        label: Text('$m min'),
                        selected: _slotMinutes == m,
                        onSelected: (_) => setState(() => _slotMinutes = m),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(context.l10n.actionSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
