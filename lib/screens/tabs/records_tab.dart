import 'package:flutter/material.dart';

enum _Source { doctor, mine }

class _HealthDocument {
  final String title;
  final String date;
  final _Source source;
  final String? doctorName;
  final IconData icon;

  const _HealthDocument({
    required this.title,
    required this.date,
    required this.source,
    this.doctorName,
    required this.icon,
  });
}

const _documents = [
  _HealthDocument(
    title: 'Blood Test Report',
    date: '24 Jun 2026',
    source: _Source.doctor,
    doctorName: 'Dr. Anjali Rao',
    icon: Icons.science_outlined,
  ),
  _HealthDocument(
    title: 'Prescription - Diabetes',
    date: '24 Jun 2026',
    source: _Source.doctor,
    doctorName: 'Dr. Anjali Rao',
    icon: Icons.description_outlined,
  ),
  _HealthDocument(
    title: 'X-Ray - Right Knee',
    date: '18 Jun 2026',
    source: _Source.doctor,
    doctorName: 'Dr. Karthik Iyer',
    icon: Icons.image_outlined,
  ),
  _HealthDocument(
    title: 'Old prescription scan',
    date: '10 Jun 2026',
    source: _Source.mine,
    icon: Icons.picture_as_pdf_outlined,
  ),
  _HealthDocument(
    title: 'Insurance card photo',
    date: '02 Jun 2026',
    source: _Source.mine,
    icon: Icons.image_outlined,
  ),
];

class RecordsTab extends StatefulWidget {
  const RecordsTab({super.key});

  @override
  State<RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<RecordsTab> {
  String _query = '';
  _Source _source = _Source.doctor;

  List<_HealthDocument> get _filtered {
    final q = _query.trim().toLowerCase();
    return _documents.where((d) {
      final matchesSource = d.source == _source;
      final matchesQuery = q.isEmpty || d.title.toLowerCase().contains(q);
      return matchesSource && matchesQuery;
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              children: [
                TextField(
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
                const SizedBox(height: 12),
                SegmentedButton<_Source>(
                  segments: const [
                    ButtonSegment(
                      value: _Source.doctor,
                      label: Text('From Doctor'),
                      icon: Icon(Icons.medical_services_outlined),
                    ),
                    ButtonSegment(
                      value: _Source.mine,
                      label: Text('My Uploads'),
                      icon: Icon(Icons.person_outline),
                    ),
                  ],
                  selected: {_source},
                  onSelectionChanged: (s) =>
                      setState(() => _source = s.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.standard,
                  ).copyWith(
                    minimumSize: const WidgetStatePropertyAll(
                      Size(double.infinity, 0),
                    ),
                  ),
                ),
              ],
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
                          Icon(
                            _source == _Source.doctor
                                ? Icons.medical_services_outlined
                                : Icons.upload_file_outlined,
                            size: 64,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _source == _Source.doctor
                                ? 'No documents shared yet'
                                : 'No uploads yet',
                            style: theme.textTheme.titleMedium,
                          ),
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
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          leading: CircleAvatar(
                            backgroundColor:
                                theme.colorScheme.primaryContainer,
                            child: Icon(d.icon, color: theme.colorScheme.primary),
                          ),
                          title: Text(d.title),
                          subtitle: Text(
                            d.source == _Source.doctor
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
