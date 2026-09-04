import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../domain/hospital.dart';
import 'hospital_controller.dart';

/// Public hospital directory. It remains intentionally separate from provider
/// discovery: only a hospital that an operator approved is shown here.
class HospitalSearchScreen extends ConsumerStatefulWidget {
  const HospitalSearchScreen({super.key, this.publicBrowse = false});

  final bool publicBrowse;

  @override
  ConsumerState<HospitalSearchScreen> createState() =>
      _HospitalSearchScreenState();
}

class _HospitalSearchScreenState extends ConsumerState<HospitalSearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final hospitals = ref.watch(hospitalDirectoryProvider);
    final normalised = _query.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Hospitals')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Find a hospital',
                prefixIcon: Icon(Icons.search_outlined),
              ),
            ),
          ),
          Expanded(
            child: AsyncView<List<HospitalDirectoryEntry>>(
              value: hospitals,
              onRetry: () => ref.invalidate(hospitalDirectoryProvider),
              skeleton: const SkeletonList(count: 4, rows: 2),
              data: (items) {
                final matches = items.where((hospital) {
                  if (normalised.isEmpty) return true;
                  return '${hospital.name} ${hospital.city} ${hospital.state}'
                      .toLowerCase()
                      .contains(normalised);
                }).toList(growable: false);
                if (matches.isEmpty) {
                  return const EmptyState(
                    icon: Icons.local_hospital_outlined,
                    title: 'No approved hospitals yet',
                    message:
                        'Hospitals appear here after their organisation application is reviewed.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.refresh(hospitalDirectoryProvider.future),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: matches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, index) => _HospitalCard(
                      hospital: matches[index],
                      publicBrowse: widget.publicBrowse,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HospitalCard extends StatelessWidget {
  const _HospitalCard({required this.hospital, required this.publicBrowse});

  final HospitalDirectoryEntry hospital;
  final bool publicBrowse;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading:
              const CircleAvatar(child: Icon(Icons.local_hospital_outlined)),
          title: Text(hospital.name),
          subtitle: Text(hospital.location),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(
            publicBrowse
                ? Routes.publicHospitalDetail(hospital.id)
                : Routes.hospitalDetail(hospital.id),
          ),
        ),
      );
}
