import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/widgets/async_view.dart';
import '../../appointments/domain/appointment.dart';
import '../../appointments/presentation/appointments_controller.dart';
import '../domain/rating.dart';

/// Rate a completed consultation.
///
/// Search filters by rating, so this is the only thing that produces the
/// numbers doctors are ranked by. One rating per completed appointment,
/// editable for 14 days, and moderated before publication.
class RateAppointmentScreen extends ConsumerWidget {
  const RateAppointmentScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointment = ref.watch(appointmentByIdProvider(appointmentId));

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.rateTitle)),
      body: AsyncView<Appointment>(
        value: appointment,
        onRetry: () => ref.invalidate(appointmentByIdProvider(appointmentId)),
        data: (a) => _Form(appointment: a),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.appointment});

  final Appointment appointment;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _commentCtrl = TextEditingController();
  int _stars = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ref.read(ratingsRepositoryProvider).submit(
            appointmentId: widget.appointment.id,
            doctorName: widget.appointment.doctor.name,
            stars: _stars,
            comment: _commentCtrl.text.trim().isEmpty
                ? null
                : _commentCtrl.text.trim(),
          );
      ref.invalidate(patientAppointmentsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thank you. Your rating will appear once reviewed.'),
        ),
      );
    } on Failure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.appointment;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 8),
                Center(
                  child: CircleAvatar(
                    radius: 36,
                    child: Text(a.doctor.name.split(' ').last[0],
                        style: theme.textTheme.headlineSmall),
                  ),
                ),
                const SizedBox(height: 12),
                Text(a.doctor.name,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center),
                Text(a.doctor.specialtyLabel,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: 28),
                Text('How was your consultation?',
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final value = i + 1;
                    return IconButton(
                      iconSize: 40,
                      onPressed: () => setState(() => _stars = value),
                      icon: Icon(
                        value <= _stars
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: Colors.amber.shade700,
                      ),
                    );
                  }),
                ),
                if (_stars > 0)
                  Text(
                    switch (_stars) {
                      1 => 'Poor',
                      2 => 'Below expectations',
                      3 => 'Fine',
                      4 => 'Good',
                      _ => 'Excellent',
                    },
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 24),
                TextField(
                  controller: _commentCtrl,
                  maxLines: 4,
                  maxLength: Rating.maxCommentLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Add a comment (optional)',
                    hintText: 'What went well, or what could be better?',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 15, color: theme.colorScheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ratings are reviewed before they are published, and '
                        'you can edit yours for 14 days. Please do not include '
                        'personal health details in your comment.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _stars == 0 || _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('Submit rating'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
