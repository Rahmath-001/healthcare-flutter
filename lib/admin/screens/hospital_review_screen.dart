import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failure.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/async_view.dart';
import '../data/operations_repository.dart';
import '../providers/operations_providers.dart';

/// The decision point that turns a public hospital request into a directory
/// record. Publishing is deliberately a human decision, never a form submit.
class HospitalReviewScreen extends ConsumerWidget {
  const HospitalReviewScreen({super.key});

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    HospitalApplication application,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve hospital?'),
        content: Text(
          'Publish ${application.name} in the patient directory and make it available for provider affiliations.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(operationsRepositoryProvider)
          .approveHospitalApplication(application.id);
      ref.invalidate(hospitalApplicationsProvider);
    } on Failure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  Future<void> _reject(
    BuildContext context,
    WidgetRef ref,
    HospitalApplication application,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reject hospital application'),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Reason for the applicant',
              helperText: 'At least 10 characters',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(operationsRepositoryProvider)
          .rejectHospitalApplication(application.id, reason: reason);
      ref.invalidate(hospitalApplicationsProvider);
    } on Failure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applications = ref.watch(hospitalApplicationsProvider);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Hospital applications', style: theme.textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(hospitalApplicationsProvider),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Approve only after independently verifying the organisation and registration number.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: AsyncView<List<HospitalApplication>>(
              value: applications,
              onRetry: () => ref.invalidate(hospitalApplicationsProvider),
              data: (items) => items.isEmpty
                  ? const EmptyState(
                      icon: Icons.fact_check_outlined,
                      title: 'Nothing waiting',
                      message: 'There are no submitted hospital applications.',
                    )
                  : Card(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final application = items[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.local_hospital_outlined),
                            ),
                            title: Text(application.name),
                            subtitle: Text(
                              '${application.city}, ${application.state}\nRegistration ${application.registrationNumber}',
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(Fmt.relative(application.submittedAt)),
                                const SizedBox(width: 12),
                                FilledButton(
                                  onPressed: () =>
                                      _approve(context, ref, application),
                                  child: const Text('Review'),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Reject',
                                  icon: const Icon(Icons.close_outlined),
                                  onPressed: () =>
                                      _reject(context, ref, application),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
