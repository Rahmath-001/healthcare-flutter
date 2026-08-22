import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/providers.dart';
import '../../../core/session/user_role.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/consultation_note.dart';

final consultationNoteProvider =
    FutureProvider.family<ConsultationNote?, String>(
        (ref, appointmentId) async {
  return ref
      .watch(consultationNoteRepositoryProvider)
      .forAppointment(appointmentId);
});

/// The doctor's write-up of a consultation, as both sides see it.
///
/// One screen for two audiences, because it is one document. The patient reads
/// it; the doctor who wrote it can append to it. Building two screens would
/// mean two renderings of the same clinical text, and the day they diverge is
/// the day the patient is reading something the doctor did not write.
class ConsultationNoteScreen extends ConsumerWidget {
  const ConsultationNoteScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(consultationNoteProvider(appointmentId));
    final isProvider =
        ref.watch(currentSessionProvider)?.role == UserRole.provider;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.noteTitle)),
      body: AsyncView<ConsultationNote?>(
        value: note,
        onRetry: () => ref.invalidate(consultationNoteProvider(appointmentId)),
        data: (n) {
          if (n == null) {
            return EmptyState(
              icon: Icons.notes_outlined,
              title: l10n.noteNone,
              message: isProvider ? null : l10n.noteNoneBody,
              action: isProvider
                  ? FilledButton.icon(
                      onPressed: () => _compose(context, ref),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      label: Text(l10n.noteWrite),
                    )
                  : null,
            );
          }
          return _NoteView(
            note: n,
            isProvider: isProvider,
            onAddAddendum: () => _compose(context, ref, noteId: n.id),
          );
        },
      ),
    );
  }

  Future<void> _compose(
    BuildContext context,
    WidgetRef ref, {
    String? noteId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = noteId == null
        ? context.l10n.noteSaved
        : context.l10n.noteAddendumSaved;

    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ComposeSheet(
        appointmentId: appointmentId,
        noteId: noteId,
      ),
    );

    if (done ?? false) {
      ref.invalidate(consultationNoteProvider(appointmentId));
      messenger.showSnackBar(SnackBar(content: Text(saved)));
    }
  }
}

class _NoteView extends StatelessWidget {
  const _NoteView({
    required this.note,
    required this.isProvider,
    required this.onAddAddendum,
  });

  final ConsultationNote note;
  final bool isProvider;
  final VoidCallback onAddAddendum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Insets.lg,
        Insets.gutter,
        Insets.xxl,
      ),
      children: [
        // The registration number is on the note for the same reason it is on
        // a prescription: it is what makes this a clinical record rather than
        // a message from somebody.
        Text(
          l10n.noteWrittenBy(note.authorName, note.authorRegistrationNumber),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: Insets.xs),
        Text(Fmt.dateTime(note.writtenAt), style: theme.textTheme.labelSmall),
        const SizedBox(height: Insets.lg),

        SelectableText(note.body, style: theme.textTheme.bodyLarge),

        // Addenda are shown after the note and separately, never merged into
        // it. A correction that reads as part of the original is a rewriting
        // of the past with extra steps.
        for (final addendum in note.addenda) ...[
          const SizedBox(height: Insets.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Insets.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: Radii.smAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(l10n.noteAddendumLabel,
                        style: theme.textTheme.labelMedium),
                    const Spacer(),
                    Text(
                      Fmt.dateTime(addendum.writtenAt),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: Insets.xs),
                SelectableText(addendum.body,
                    style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],

        if (isProvider) ...[
          const SizedBox(height: Insets.xl),
          OutlinedButton.icon(
            onPressed: onAddAddendum,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.noteAddendum),
          ),
          const SizedBox(height: Insets.sm),
          Text(l10n.noteImmutable, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _ComposeSheet extends ConsumerStatefulWidget {
  const _ComposeSheet({required this.appointmentId, this.noteId});

  final String appointmentId;

  /// Null when writing the note itself; set when appending an addendum.
  final String? noteId;

  @override
  ConsumerState<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends ConsumerState<_ComposeSheet> {
  final _controller = TextEditingController();
  bool _saving = false;

  bool get _isAddendum => widget.noteId != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    try {
      final repo = ref.read(consultationNoteRepositoryProvider);
      if (_isAddendum) {
        await repo.addAddendum(widget.noteId!, body: _controller.text);
      } else {
        await repo.write(widget.appointmentId, body: _controller.text);
      }
      Haptics.success();
      navigator.pop(true);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _saving = false);
      Haptics.warning();
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Insets.gutter,
          0,
          Insets.gutter,
          Insets.gutter + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isAddendum ? l10n.noteAddendum : l10n.noteWrite,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: Insets.sm),
            // Said before writing, not after saving. Somebody who learns a note
            // is permanent only once it is permanent has been told too late.
            Text(l10n.noteImmutable, style: theme.textTheme.bodySmall),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _controller,
              maxLines: 8,
              maxLength: _isAddendum
                  ? ConsultationNote.maxAddendumLength
                  : ConsultationNote.maxBodyLength,
              autofocus: true,
              // The most clinical free text in the app. Same
              // keyboard-dictionary rule as everywhere else — see
              // `edit_profile_screen.dart`.
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.noteHint,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Insets.sm),
            FilledButton(
              onPressed:
                  _controller.text.trim().isEmpty || _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Text(_isAddendum ? l10n.noteAddendumSave : l10n.noteSave),
            ),
          ],
        ),
      ),
    );
  }
}
