import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/files/file_picker_service.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../domain/medical_record.dart';
import 'records_controller.dart';

/// Upload a record (FR-MR-001: reports, scans, X-rays, PDFs).
///
/// Camera capture and document picking are both wired. The server still
/// re-derives the content type, scans for malware and strips EXIF regardless
/// of what is sent.
class RecordUploadScreen extends ConsumerStatefulWidget {
  const RecordUploadScreen({super.key});

  @override
  ConsumerState<RecordUploadScreen> createState() => _RecordUploadScreenState();
}

class _RecordUploadScreenState extends ConsumerState<RecordUploadScreen> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  RecordType _type = RecordType.labReport;
  DateTime _recordedAt = DateTime.now();
  PickedFile? _picked;
  double _progress = 0;
  bool _uploading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile(String source) async {
    final picker = ref.read(filePickerServiceProvider);
    try {
      final picked = switch (source) {
        'camera' => await picker.captureWithCamera(),
        'gallery' => await picker.pickImageFromGallery(),
        _ => await picker.pickDocument(),
      };
      if (picked == null) return; // user cancelled

      picker.validate(picked, maxBytes: FilePickerService.maxRecordBytes);

      setState(() {
        // The bytes are held, not a path: they are what gets uploaded, and a
        // path is neither portable nor available for cloud-provider files.
        _picked = picked;
        // Default the title to the file name, which is usually close enough
        // that the user only has to tidy it.
        if (_titleCtrl.text.trim().isEmpty) {
          _titleCtrl.text = picked.name.split('.').first.replaceAll('_', ' ');
        }
      });
    } on Failure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordedAt,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      helpText: 'When was this taken?',
    );
    if (picked != null) setState(() => _recordedAt = picked);
  }

  Future<void> _upload() async {
    if (_titleCtrl.text.trim().isEmpty || _picked == null) return;

    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      await ref.read(recordsRepositoryProvider).upload(
            title: _titleCtrl.text.trim(),
            type: _type,
            recordedAt: _recordedAt,
            file: _picked!,
            notes:
                _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            onProgress: (sent, total) {
              if (mounted && total > 0) {
                setState(() => _progress = sent / total);
              }
            },
          );
      ref.invalidate(ownRecordsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uploaded. It will be available once checked.'),
        ),
      );
    } on Failure catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canUpload =
        _titleCtrl.text.trim().isNotEmpty && _picked != null && !_uploading;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.uploadTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_picked == null)
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo_camera_outlined),
                      title: const Text('Scan with camera'),
                      subtitle: const Text('Best for paper reports'),
                      onTap: () => _pickFile('camera'),
                    ),
                    const Divider(height: 1),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('Choose a photo'),
                      subtitle: const Text('From your gallery'),
                      onTap: () => _pickFile('gallery'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.attach_file),
                      title: const Text('Choose a file'),
                      subtitle: const Text('PDF, JPG, PNG or HEIC'),
                      onTap: () => _pickFile('file'),
                    ),
                  ],
                ),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(Icons.insert_drive_file_outlined,
                      color: theme.colorScheme.primary),
                  title: Text(_picked!.name),
                  subtitle: Text(
                      '${(_picked!.sizeBytes / 1024).toStringAsFixed(0)} KB'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _picked = null;
                    }),
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // "HIV panel", "Oncology discharge summary" — a record title is
            // as revealing as the file. No keyboard learning; see
            // `edit_profile_screen.dart`.
            TextField(
              controller: _titleCtrl,
              onChanged: (_) => setState(() {}),
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.l10n.uploadRecordTitle,
                hintText: context.l10n.uploadRecordTitleHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            Text(context.l10n.uploadRecordType,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: RecordType.values
                  .map((t) => ChoiceChip(
                        label: Text(t.label),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),

            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(context.l10n.uploadDateOnReport),
                subtitle: Text(Fmt.date(_recordedAt)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              maxLength: 300,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: context.l10n.uploadNotes,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),

            // Sets the expectation that upload is not instantly readable, and
            // states plainly that nobody sees it without an explicit grant.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline,
                    size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your records are private to you. A doctor can only see '
                    'one if you share it, and you can revoke that at any time. '
                    'Files are validated and private before they become '
                    'available.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // A 25 MB upload on Indian mobile data is slow enough that an
            // indeterminate spinner reads as a hang.
            if (_uploading) ...[
              LinearProgressIndicator(
                value: _progress > 0 && _progress < 1 ? _progress : null,
              ),
              const SizedBox(height: 12),
            ],

            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: canUpload ? _upload : null,
                child: _uploading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('Upload'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
