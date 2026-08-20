import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../error/failure.dart';

/// A file the user chose, normalised across the camera and file pickers.
///
/// Carries the **bytes**, not a path. A path is not portable — web has none,
/// and Android content URIs from cloud providers do not resolve to a local
/// file — and an upload needs the content anyway. The size ceiling is 25 MB, so
/// holding it in memory is bounded.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;

  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';

  /// Best-effort content type from the extension.
  ///
  /// Advisory only: the server re-derives the real type from magic bytes and
  /// refuses anything that disagrees with what was claimed.
  String get contentType => switch (extension) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'heic' => 'image/heic',
        'jpg' || 'jpeg' => 'image/jpeg',
        _ => 'application/octet-stream',
      };
}

/// Camera and document picking for medical records and provider credentials.
///
/// Validation here is a courtesy to the user, not a security control: the
/// server re-derives the real content type from magic bytes, scans for malware
/// and re-encodes PDFs regardless of what the client claims.
class FilePickerService {
  FilePickerService({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  /// Types accepted for upload. Matches the server's allow-list.
  static const allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'heic'];

  static const maxRecordBytes = 25 * 1024 * 1024;
  static const maxCredentialBytes = 15 * 1024 * 1024;

  /// Photograph a paper report or certificate.
  ///
  /// Images are downscaled and recompressed before upload: a modern phone
  /// camera produces 8–12 MB files, which are slow to send on Indian mobile
  /// data and no more legible than a 2000px capture.
  Future<PickedFile?> captureWithCamera() async {
    final shot = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
    );
    if (shot == null) return null;
    return _fromXFile(shot);
  }

  Future<PickedFile?> pickImageFromGallery() async {
    final shot = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
    );
    if (shot == null) return null;
    return _fromXFile(shot);
  }

  /// Pick a PDF or image from the device's files.
  Future<PickedFile?> pickDocument() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (file == null) return null;

    // `readAsBytes` rather than a path: `PlatformFile.path` is null for cloud
    // provider content URIs and on web, and an upload needs the content anyway.
    return PickedFile(name: file.name, bytes: await file.readAsBytes());
  }

  /// Rejects anything the server would reject anyway, but with a message the
  /// user can act on before spending their data allowance on the upload.
  void validate(PickedFile file, {required int maxBytes}) {
    if (!allowedExtensions.contains(file.extension)) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Only PDF, JPG, PNG and HEIC files can be uploaded.',
        code: 'UNSUPPORTED_FILE_TYPE',
      );
    }
    if (file.sizeBytes > maxBytes) {
      final mb = (maxBytes / (1024 * 1024)).round();
      throw Failure(
        kind: FailureKind.validation,
        message: 'Files must be smaller than $mb MB.',
        code: 'FILE_TOO_LARGE',
      );
    }
    if (file.sizeBytes == 0) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'That file appears to be empty.',
        code: 'EMPTY_FILE',
      );
    }
  }

  Future<PickedFile> _fromXFile(XFile x) async {
    // XFile.readAsBytes works on every platform; File(x.path) does not.
    return PickedFile(name: x.name, bytes: await x.readAsBytes());
  }
}

final filePickerServiceProvider = Provider<FilePickerService>(
  (ref) => FilePickerService(),
);
