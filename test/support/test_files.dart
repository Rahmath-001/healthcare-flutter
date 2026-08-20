import 'dart:typed_data';

import 'package:healthcare_mobile/core/files/file_picker_service.dart';

/// A picked file for tests.
///
/// Carries real bytes rather than a stub, because [PickedFile] derives its size
/// and content type from them — a zero-length placeholder would be rejected by
/// the same validation the app runs.
PickedFile testFile({
  required String name,
  int sizeBytes = 4096,
}) =>
    PickedFile(
      name: name,
      bytes: Uint8List.fromList(List<int>.filled(sizeBytes, 0x41)),
    );
