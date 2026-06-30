import 'package:flutter/material.dart';

class _Doctor {
  final String name;
  final String specialty;
  final double rating;
  final String nextAvailable;

  const _Doctor({
    required this.name,
    required this.specialty,
    required this.rating,
    required this.nextAvailable,
  });
}

const _doctors = [
  _Doctor(name: 'Dr. Anjali Rao', specialty: 'Cardiology', rating: 4.8, nextAvailable: 'Today, 4:30 PM'),
  _Doctor(name: 'Dr. Vikram Shah', specialty: 'General Physician', rating: 4.6, nextAvailable: 'Today, 6:00 PM'),
  _Doctor(name: 'Dr. Priya Nair', specialty: 'Dermatology', rating: 4.9, nextAvailable: 'Tomorrow, 10:00 AM'),
  _Doctor(name: 'Dr. Karthik Iyer', specialty: 'Orthopedics', rating: 4.5, nextAvailable: 'Tomorrow, 11:30 AM'),
  _Doctor(name: 'Dr. Sneha Reddy', specialty: 'Pediatrics', rating: 4.7, nextAvailable: 'Today, 5:00 PM'),
  _Doctor(name: 'Dr. Arjun Mehta', specialty: 'Cardiology', rating: 4.4, nextAvailable: 'Fri, 9:00 AM'),
  _Doctor(name: 'Dr. Fatima Sheikh', specialty: 'General Physician', rating: 4.8, nextAvailable: 'Today, 3:00 PM'),
];

const _specialties = [
  'All',
  'Cardiology',
  'General Physician',
  'Dermatology',
  'Orthopedics',
  'Pediatrics',
];

class DoctorsScreen extends StatefulWidget {
  const DoctorsScreen({super.key});

  @override
  State<DoctorsScreen> createState() => _DoctorsScreenState();
}

class _DoctorsScreenState extends State<DoctorsScreen> {
  String _query = '';
  String _specialty = 'All';

  List<_Doctor> get _filtered {
    return _doctors.where((d) {
      final matchesSpecialty = _specialty == 'All' || d.specialty == _specialty;
      final q = _query.trim().toLowerCase();
      final matchesQuery = q.isEmpty ||
          d.name.toLowerCase().contains(q) ||
          d.specialty.toLowerCase().contains(q);
      return matchesSpecialty && matchesQuery;
    }).toList();
  }

  void _book(_Doctor d) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Appointment requested with ${d.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _filtered;

    return Scaffold(
      appBar: AppBar(title: const Text('Find a Doctor')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search doctor or specialty',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              scrollDirection: Axis.horizontal,
              itemCount: _specialties.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = _specialties[i];
                return ChoiceChip(
                  label: Text(s),
                  selected: _specialty == s,
                  onSelected: (_) => setState(() => _specialty = s),
                );
              },
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text('No doctors match your search',
                        style: theme.textTheme.bodyMedium),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final d = results[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                child: Icon(Icons.person,
                                    color: theme.colorScheme.primary),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.name,
                                        style: theme.textTheme.titleMedium),
                                    const SizedBox(height: 2),
                                    Text(d.specialty,
                                        style: theme.textTheme.bodySmall),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.star,
                                            size: 14, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Text('${d.rating}',
                                            style: theme.textTheme.bodySmall),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            d.nextAvailable,
                                            style: theme.textTheme.bodySmall,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => _book(d),
                                child: const Text('Book'),
                              ),
                            ],
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
