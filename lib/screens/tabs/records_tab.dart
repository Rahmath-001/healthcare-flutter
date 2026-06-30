import 'package:flutter/material.dart';

class _HealthDocument {
  final String title;
  final String date;
  final bool fromDoctor;
  final String? doctorName;
  final IconData icon;

  const _HealthDocument({
    required this.title,
    required this.date,
    required this.fromDoctor,
    this.doctorName,
    required this.icon,
  });
}

const _documents = [
  _HealthDocument(
    title: 'Blood Test Report',
    date: '24 Jun 2026',
    fromDoctor: true,
    doctorName: 'Dr. Anjali Rao',
    icon: Icons.science_outlined,
  ),
  _HealthDocument(
    title: 'Prescription - Diabetes',
    date: '24 Jun 2026',
    fromDoctor: true,
    doctorName: 'Dr. Anjali Rao',
    icon: Icons.description_outlined,
  ),
  _HealthDocument(
    title: 'X-Ray - Right Knee',
    date: '18 Jun 2026',
    fromDoctor: true,
    doctorName: 'Dr. Karthik Iyer',
    icon: Icons.image_outlined,
  ),
  _HealthDocument(
    title: 'Old prescription scan',
    date: '10 Jun 2026',
    fromDoctor: false,
    icon: Icons.picture_as_pdf_outlined,
  ),
  _HealthDocument(
    title: 'Insurance card photo',
    date: '02 Jun 2026',
    fromDoctor: false,
    icon: Icons.image_outlined,
  ),
];

const _filters = ['All', 'From Doctor', 'My Uploads'];

class RecordsTab extends StatefulWidget {
  const RecordsTab({super.key});

  @override
  State<RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<RecordsTab> {
  String _query = '';
  String _filter = 'All';

  List<_HealthDocument> get _filtered {
    return _documents.where((d) {
      final matchesFilter = switch (_filter) {
        'From Doctor' => d.fromDoctor,
        'My Uploads' => !d.fromDoctor,
        _ => true,
      };
      final q = _query.trim().toLowerCase();
      final matchesQuery = q.isEmpty || d.title.toLowerCase().contains(q);
      return matchesFilter && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _filtered;

    return SafeArea(
      child: Column(
        children: [
          AppBar(
            title: const Text('Health Records'),
            centerTitle: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.upload_file_outlined),
                tooltip: 'Upload document',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Upload not wired up yet')),
                  );
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search records',
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
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = _filters[i];
                return ChoiceChip(
                  label: Text(f),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                );
              },
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.description_outlined,
                              size: 64, color: theme.colorScheme.primary),
                          const SizedBox(height: 16),
                          Text('No records found',
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final d = results[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                theme.colorScheme.primaryContainer,
                            child: Icon(d.icon, color: theme.colorScheme.primary),
                          ),
                          title: Text(d.title),
                          subtitle: Text(
                            d.fromDoctor
                                ? '${d.date} · Shared by ${d.doctorName}'
                                : '${d.date} · Uploaded by you',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Opening ${d.title}...')),
                            );
                          },
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
