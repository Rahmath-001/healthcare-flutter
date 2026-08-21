import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/prescription.dart';

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
      appBar: AppBar(title: Text(context.l10n.prescribeWriteTitle)),
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
