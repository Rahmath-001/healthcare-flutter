import 'package:flutter/material.dart';

import '../doctors_screen.dart';

enum _Status { upcoming, completed, cancelled }

class _Appointment {
  final String doctorName;
  final String specialty;
  final String dateTime;
  final String mode; // 'Video consultation' | 'In-person'
  final String location;
  final _Status status;

  const _Appointment({
    required this.doctorName,
    required this.specialty,
    required this.dateTime,
    required this.mode,
    required this.location,
    required this.status,
  });
}

const _appointments = [
  _Appointment(
    doctorName: 'Dr. Anjali Rao',
    specialty: 'Cardiology',
    dateTime: 'Today, 4:30 PM',
    mode: 'Video consultation',
    location: 'Online',
    status: _Status.upcoming,
  ),
  _Appointment(
    doctorName: 'Dr. Karthik Iyer',
    specialty: 'Orthopedics',
    dateTime: 'Tomorrow, 11:30 AM',
    mode: 'In-person',
    location: 'Apollo Clinic, Indiranagar',
    status: _Status.upcoming,
  ),
  _Appointment(
    doctorName: 'Dr. Vikram Shah',
    specialty: 'General Physician',
    dateTime: '18 Jun 2026, 6:00 PM',
    mode: 'In-person',
    location: 'Manipal Hospital, HSR',
    status: _Status.completed,
  ),
  _Appointment(
    doctorName: 'Dr. Sneha Reddy',
    specialty: 'Pediatrics',
    dateTime: '10 Jun 2026, 5:00 PM',
    mode: 'Video consultation',
    location: 'Online',
    status: _Status.cancelled,
  ),
];

class AppointmentsTab extends StatelessWidget {
  const AppointmentsTab({super.key});

  void _openBooking(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DoctorsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          const SliverAppBar(
            floating: true,
            title: Text('Appointments'),
            centerTitle: false,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openBooking(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Book Appointment'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ),
          if (_appointments.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month_outlined,
                          size: 72, color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      Text('No appointments yet',
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(
                        'Book a consultation with your care team to see it here.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverList.separated(
                itemCount: _appointments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _AppointmentCard(a: _appointments[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final _Appointment a;

  const _AppointmentCard({required this.a});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = a.mode == 'Video consultation';

    final (Color bg, Color fg, String label) = switch (a.status) {
      _Status.upcoming => (
          theme.colorScheme.primaryContainer,
          theme.colorScheme.primary,
          'Upcoming'
        ),
      _Status.completed => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
          'Completed'
        ),
      _Status.cancelled => (
          theme.colorScheme.errorContainer,
          theme.colorScheme.error,
          'Cancelled'
        ),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.person, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.doctorName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(a.specialty, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.event_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(a.dateTime, style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(isVideo ? Icons.videocam_outlined : Icons.place_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(a.location,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            if (a.status == _Status.upcoming) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () {}, child: const Text('Cancel')),
                  const SizedBox(width: 4),
                  FilledButton.tonal(
                    onPressed: () {},
                    child: const Text('Reschedule'),
                  ),
                ],
              ),
            ] else if (a.status == _Status.completed) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: const Text('View Summary'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
