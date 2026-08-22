import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/haptics.dart';
import '../domain/prescription.dart';
import '../domain/prescription_template.dart';

/// Provider-side prescription composer.
///
/// The telemedicine drug lists are enforced in the UI as well as on the server:
/// a medicine that cannot legally be prescribed on this consultation is shown,
/// disabled, with the reason. Hiding it would leave the doctor wondering why a
/// drug they know exists is missing.
class PrescribeScreen extends ConsumerStatefulWidget {
  const PrescribeScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  ConsumerState<PrescribeScreen> createState() => _PrescribeScreenState();
}

class _PrescribeScreenState extends ConsumerState<PrescribeScreen> {
  final _diagnosisCtrl = TextEditingController();
  final _adviceCtrl = TextEditingController();
  final _items = <PrescriptionItem>[];

  /// Whether this is a follow-up. Drives List B eligibility, which may only be
  /// prescribed as a refill on an established consultation.
  bool _isFollowUp = false;
  bool _issuing = false;

  @override
  void dispose() {
    _diagnosisCtrl.dispose();
    _adviceCtrl.dispose();
    super.dispose();
  }

  Future<void> _addMedicine() async {
    final item = await showModalBottomSheet<PrescriptionItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DrugPickerSheet(isFollowUp: _isFollowUp),
    );
    if (item != null) setState(() => _items.add(item));
  }

  /// Picks a template and fills the composer from it.
  ///
  /// Applying appends rather than replaces: a doctor part-way through a
  /// prescription who reaches for a template is adding to what they have,
  /// and silently discarding typed-in medicines would be the worst possible
  /// reading of the gesture.
  Future<void> _openTemplates() async {
    final applied = await showModalBottomSheet<PrescriptionTemplate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TemplatePickerSheet(isFollowUp: _isFollowUp),
    );
    if (applied == null || !mounted) return;

    // Only what may be prescribed on *this* consultation. The sheet has
    // already shown the doctor what was excluded and why.
    final usable = applied.prescribableOn(isFollowUp: _isFollowUp);

    setState(() {
      for (final item in usable) {
        final already = _items.any((existing) =>
            existing.drugId == item.drugId &&
            existing.strength == item.strength);
        if (!already) _items.add(item.toPrescriptionItem());
      }
      // Offered, never forced: a template's diagnosis is about a condition,
      // not about a set of drugs, so it fills only an empty field.
      if (applied.diagnosis != null && _diagnosisCtrl.text.trim().isEmpty) {
        _diagnosisCtrl.text = applied.diagnosis!;
      }
      if (applied.advice != null && _adviceCtrl.text.trim().isEmpty) {
        _adviceCtrl.text = applied.advice!;
      }
    });
  }

  Future<void> _saveTemplate() async {
    final messenger = ScaffoldMessenger.of(context);
    // Captured before the dialog, so the snackbar text does not need the
    // context back after the await.
    final savedLabel = context.l10n.templatesSaved;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameTemplateDialog(),
    );
    if (name == null || !mounted) return;

    // Templates are keyed on drug id, because that is what the catalogue is
    // re-read by. An item composed without one cannot be re-checked against
    // the drug lists later, so it is left out rather than saved unverifiable.
    final items = <TemplateItem>[
      for (final i in _items)
        if (i.drugId != null)
          TemplateItem(
            drugId: i.drugId!,
            drugName: i.drugName,
            genericName: i.genericName,
            strength: i.strength,
            form: i.form,
            frequency: i.frequency,
            durationDays: i.durationDays,
            instructions: i.instructions,
            // Not stored; the catalogue supplies it on read. Any value here
            // is discarded on the way out.
            telemedicineList: TelemedicineDrugList.listO,
          ),
    ];

    try {
      await ref.read(prescriptionTemplateRepositoryProvider).create(
            name: name,
            items: items,
            diagnosis: _diagnosisCtrl.text.trim().isEmpty
                ? null
                : _diagnosisCtrl.text.trim(),
            advice: _adviceCtrl.text.trim().isEmpty
                ? null
                : _adviceCtrl.text.trim(),
          );
      ref.invalidate(prescriptionTemplatesProvider);
      Haptics.success();
      messenger.showSnackBar(
        SnackBar(content: Text(savedLabel)),
      );
    } on Failure catch (e) {
      Haptics.warning();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _issue() async {
    setState(() => _issuing = true);
    try {
      await ref.read(prescriptionRepositoryProvider).issue(
            appointmentId: widget.appointmentId,
            patientName: 'Rohan Gupta',
            patientAge: '34',
            patientGender: 'Male',
            items: _items,
            isFollowUp: _isFollowUp,
            diagnosis: _diagnosisCtrl.text.trim().isEmpty
                ? null
                : _diagnosisCtrl.text.trim(),
            advice: _adviceCtrl.text.trim().isEmpty
                ? null
                : _adviceCtrl.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.prescribeIssued2)),
      );
    } on Failure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.prescribeWriteTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.templatesTitle,
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: _openTemplates,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  SwitchListTile(
                    value: _isFollowUp,
                    onChanged: (v) => setState(() => _isFollowUp = v),
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.prescribeFollowUpConsultation),
                    subtitle: const Text(
                      'Some medicines may only be refilled on a follow-up.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  // A doctor types diagnoses into this field all day. Without
                  // these two flags the phone's personal dictionary slowly
                  // accumulates every patient's condition and offers them as
                  // suggestions in other apps. See `edit_profile_screen.dart`.
                  TextField(
                    controller: _diagnosisCtrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: context.l10n.prescribeDiagnosis,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(context.l10n.prescribeMedicines,
                          style: theme.textTheme.titleSmall),
                      const Spacer(),
                      if (_items.isNotEmpty)
                        TextButton.icon(
                          onPressed: _saveTemplate,
                          icon:
                              const Icon(Icons.bookmark_add_outlined, size: 18),
                          label: Text(context.l10n.templatesSave),
                        ),
                      TextButton.icon(
                        onPressed: _addMedicine,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(context.l10n.prescribeAdd),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (_items.isEmpty)
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(context.l10n.prescribeNoMedicines,
                              style: theme.textTheme.bodySmall),
                        ),
                      ),
                    )
                  else
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < _items.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              title: Text(_items[i].drugName),
                              subtitle: Text(_items[i].summary),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    setState(() => _items.removeAt(i)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _adviceCtrl,
                    maxLines: 4,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: context.l10n.prescribeAdviceToPatient,
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.gavel_outlined,
                          size: 16, color: theme.colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your name and registration number are recorded on '
                          'this prescription and cannot be changed after it is '
                          'issued.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _items.isEmpty || _issuing ? null : _issue,
                  child: _issuing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Text(context.l10n.prescribeIssue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrugPickerSheet extends ConsumerStatefulWidget {
  const _DrugPickerSheet({required this.isFollowUp});

  final bool isFollowUp;

  @override
  ConsumerState<_DrugPickerSheet> createState() => _DrugPickerSheetState();
}

class _DrugPickerSheetState extends ConsumerState<_DrugPickerSheet> {
  final _searchCtrl = TextEditingController();
  final _frequencyCtrl = TextEditingController(text: '1-0-1');
  final _durationCtrl = TextEditingController(text: '5');
  final _instructionsCtrl = TextEditingController();

  Drug? _selected;
  String? _strength;
  List<Drug> _results = [];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _frequencyCtrl.dispose();
    _durationCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final results =
        await ref.read(prescriptionRepositoryProvider).searchDrugs(q);
    if (mounted) setState(() => _results = results);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: _selected == null
            ? Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    onChanged: _search,
                    decoration: InputDecoration(
                      hintText: context.l10n.prescribeSearchMedicines,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final drug = _results[i];
                        final allowed = drug.isPrescribableOn(
                            isFollowUp: widget.isFollowUp);
                        final reason =
                            drug.blockedReason(isFollowUp: widget.isFollowUp);

                        return ListTile(
                          enabled: allowed,
                          title: Text(drug.name),
                          subtitle: Text(
                            allowed
                                ? '${drug.genericName} · ${drug.form}'
                                : reason!,
                            style: allowed
                                ? null
                                : TextStyle(color: theme.colorScheme.error),
                          ),
                          trailing: StatusChip(
                            label: drug.telemedicineList.label,
                            tone: allowed ? Tone.success : Tone.danger,
                          ),
                          onTap: allowed
                              ? () => setState(() {
                                    _selected = drug;
                                    _strength =
                                        drug.commonStrengths.firstOrNull;
                                  })
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              )
            : ListView(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_selected!.name,
                        style: theme.textTheme.titleMedium),
                    subtitle: Text(_selected!.genericName),
                    trailing: TextButton(
                      onPressed: () => setState(() => _selected = null),
                      child: Text(context.l10n.prescribeChange),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_selected!.commonStrengths.isNotEmpty) ...[
                    Text(context.l10n.prescribeStrength,
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _selected!.commonStrengths
                          .map((s) => ChoiceChip(
                                label: Text(s),
                                selected: _strength == s,
                                onSelected: (_) =>
                                    setState(() => _strength = s),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _frequencyCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.prescribeFrequency,
                      helperText: 'e.g. 1-0-1 (morning-noon-night)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _durationCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.l10n.prescribeDurationDays,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _instructionsCtrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: context.l10n.prescribeInstructionsOptional,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: () {
                        final days = int.tryParse(_durationCtrl.text) ?? 1;
                        Navigator.of(context).pop(
                          PrescriptionItem(
                            drugId: _selected!.id,
                            drugName: _selected!.name,
                            genericName: _selected!.genericName,
                            strength: _strength ?? '',
                            form: _selected!.form,
                            frequency: _frequencyCtrl.text.trim(),
                            durationDays: days,
                            instructions: _instructionsCtrl.text.trim().isEmpty
                                ? null
                                : _instructionsCtrl.text.trim(),
                          ),
                        );
                      },
                      child: Text(context.l10n.prescribeAddToPrescription),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A doctor's saved prescribing sets.
final prescriptionTemplatesProvider =
    FutureProvider<List<PrescriptionTemplate>>((ref) async {
  return ref.watch(prescriptionTemplateRepositoryProvider).list();
});

/// Choose a template, having been told what it will not carry across.
class _TemplatePickerSheet extends ConsumerWidget {
  const _TemplatePickerSheet({required this.isFollowUp});

  final bool isFollowUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(prescriptionTemplatesProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.gutter, 0, Insets.gutter, Insets.sm),
              child:
                  Text(l10n.templatesTitle, style: theme.textTheme.titleLarge),
            ),
            Flexible(
              child: AsyncView<List<PrescriptionTemplate>>(
                value: templates,
                onRetry: () => ref.invalidate(prescriptionTemplatesProvider),
                data: (list) => list.isEmpty
                    ? EmptyState(
                        icon: Icons.bookmarks_outlined,
                        title: l10n.templatesNone,
                        message: l10n.templatesNoneBody,
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: Insets.gutter),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _TemplateTile(
                          template: list[i],
                          isFollowUp: isFollowUp,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateTile extends ConsumerWidget {
  const _TemplateTile({required this.template, required this.isFollowUp});

  final PrescriptionTemplate template;
  final bool isFollowUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tones = context.tones;
    final l10n = context.l10n;

    final blocked = template.blockedOn(isFollowUp: isFollowUp);
    final usable = template.prescribableOn(isFollowUp: isFollowUp);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(template.name, style: theme.textTheme.titleSmall),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            template.items.map((i) => i.drugName).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          // Said before applying, not after. A doctor who discovers the
          // exclusion only once rows are greyed out has already committed to
          // the template.
          if (blocked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Insets.xs),
              child: Text(
                l10n.templatesBlockedHere(blocked.length),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tones.warning,
                ),
              ),
            ),
        ],
      ),
      trailing: IconButton(
        tooltip: l10n.templatesDelete,
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(context, ref),
      ),
      // Nothing to apply is not a tap worth accepting.
      onTap: usable.isEmpty ? null : () => Navigator.of(context).pop(template),
      enabled: usable.isNotEmpty,
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(prescriptionTemplateRepositoryProvider)
          .delete(template.id);
      ref.invalidate(prescriptionTemplatesProvider);
    } on Failure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _NameTemplateDialog extends StatefulWidget {
  const _NameTemplateDialog();

  @override
  State<_NameTemplateDialog> createState() => _NameTemplateDialogState();
}

class _NameTemplateDialogState extends State<_NameTemplateDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = _controller.text.trim();

    return AlertDialog(
      title: Text(l10n.templatesSave),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: PrescriptionTemplate.maxNameLength,
        textCapitalization: TextCapitalization.sentences,
        // A template name is the doctor's own shorthand, not clinical text
        // about a patient, so the keyboard dictionary rule does not apply.
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: l10n.templatesName,
          hintText: l10n.templatesNameHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed:
              name.isEmpty ? null : () => Navigator.of(context).pop(name),
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}
