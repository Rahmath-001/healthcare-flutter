import 'package:flutter/material.dart';

class _Medication {
  final String name;
  final String dosage;
  final List<String> times;
  final String condition;
  final int total;
  final int consumed;

  const _Medication({
    required this.name,
    required this.dosage,
    required this.times,
    required this.condition,
    required this.total,
    required this.consumed,
  });
}

const _medications = [
  _Medication(
    name: 'Metformin',
    dosage: '500mg',
    times: ['8:00 AM', '8:00 PM'],
    condition: 'Diabetes',
    total: 60,
    consumed: 42,
  ),
  _Medication(
    name: 'Glimepiride',
    dosage: '1mg',
    times: ['8:00 AM'],
    condition: 'Diabetes',
    total: 30,
    consumed: 22,
  ),
  _Medication(
    name: 'Amlodipine',
    dosage: '5mg',
    times: ['9:00 AM'],
    condition: 'Hypertension',
    total: 30,
    consumed: 18,
  ),
  _Medication(
    name: 'Atorvastatin',
    dosage: '10mg',
    times: ['9:00 PM'],
    condition: 'Cholesterol',
    total: 30,
    consumed: 30,
  ),
];

class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byCondition = <String, List<_Medication>>{};
    for (final m in _medications) {
      byCondition.putIfAbsent(m.condition, () => []).add(m);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Medications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: byCondition.entries.expand((entry) {
          return [
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: Text(entry.key, style: theme.textTheme.titleSmall),
            ),
            ...entry.value.map((m) => _MedicationCard(med: m)),
            const SizedBox(height: 12),
          ];
        }).toList(),
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  final _Medication med;

  const _MedicationCard({required this.med});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = med.total == 0 ? 0.0 : med.consumed / med.total;
    final done = med.consumed >= med.total;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medication_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${med.name} · ${med.dosage}',
                      style: theme.textTheme.titleMedium),
                ),
                if (done)
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: med.times
                  .map((t) => Chip(
                        label: Text(t),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Text('${med.consumed}/${med.total} tablets consumed',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
