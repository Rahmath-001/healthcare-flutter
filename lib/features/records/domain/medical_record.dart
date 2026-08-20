import 'package:flutter/foundation.dart';

enum RecordType {
  labReport('LAB_REPORT'),
  scan('SCAN'),
  xray('XRAY'),
  prescription('PRESCRIPTION'),
  dischargeSummary('DISCHARGE_SUMMARY'),
  vaccination('VACCINATION'),
  other('OTHER');

  const RecordType(this.wire);

  final String wire;

  String get label => switch (this) {
        RecordType.labReport => 'Lab report',
        RecordType.scan => 'Scan',
        RecordType.xray => 'X-ray',
        RecordType.prescription => 'Prescription',
        RecordType.dischargeSummary => 'Discharge summary',
        RecordType.vaccination => 'Vaccination',
        RecordType.other => 'Other',
      };

  /// Falls back to [other] rather than throwing: a server that adds a record
  /// type the client has not shipped yet must not break the whole list.
  static RecordType fromWire(String? wire) => RecordType.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => RecordType.other,
      );
}

/// Antivirus / content-inspection state.
///
/// A record is not readable until it is CLEAN. Uploads land in a quarantine
/// bucket first and are only promoted after scanning, magic-byte verification,
/// EXIF stripping and PDF re-encoding.
enum ScanStatus {
  pending('PENDING'),
  clean('CLEAN'),
  infected('INFECTED'),
  failed('FAILED');

  const ScanStatus(this.wire);

  final String wire;

  /// An unrecognised state is treated as [failed], not as clean. Anything this
  /// client cannot reason about must not become readable by default.
  static ScanStatus fromWire(String? wire) => ScanStatus.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => ScanStatus.failed,
      );
}

/// Who put the record into the system.
///
/// The patient owns every record regardless (FR-MR-002); this only records
/// provenance, which matters clinically — a doctor-issued report carries
/// different weight from a phone photo.
enum RecordSource {
  patient('PATIENT'),
  provider('PROVIDER');

  const RecordSource(this.wire);

  final String wire;

  static RecordSource fromWire(String? wire) => RecordSource.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => RecordSource.patient,
      );
}

@immutable
class MedicalRecord {
  const MedicalRecord({
    required this.id,
    required this.title,
    required this.type,
    required this.source,
    required this.recordedAt,
    required this.uploadedAt,
    required this.scanStatus,
    required this.sizeBytes,
    required this.contentType,
    this.issuedByName,
    this.notes,
    this.pageCount,
  });

  final String id;
  final String title;
  final RecordType type;
  final RecordSource source;

  /// When the study/test actually happened — not when it was uploaded.
  final DateTime recordedAt;
  final DateTime uploadedAt;
  final ScanStatus scanStatus;
  final int sizeBytes;
  final String contentType;
  final String? issuedByName;
  final String? notes;
  final int? pageCount;

  factory MedicalRecord.fromJson(Map<String, dynamic> json) {
    return MedicalRecord(
      id: json['id'] as String,
      title: json['title'] as String,
      type: RecordType.fromWire(json['type'] as String?),
      source: RecordSource.fromWire(json['source'] as String?),
      recordedAt: DateTime.parse(json['recordedAt'] as String).toLocal(),
      uploadedAt: DateTime.parse(json['uploadedAt'] as String).toLocal(),
      scanStatus: ScanStatus.fromWire(json['scanStatus'] as String?),
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      contentType: json['contentType'] as String,
      issuedByName: json['issuedByName'] as String?,
      notes: json['notes'] as String?,
      pageCount: (json['pageCount'] as num?)?.toInt(),
    );
  }

  MedicalRecord copyWith({ScanStatus? scanStatus, String? notes}) =>
      MedicalRecord(
        id: id,
        title: title,
        type: type,
        source: source,
        recordedAt: recordedAt,
        uploadedAt: uploadedAt,
        scanStatus: scanStatus ?? this.scanStatus,
        sizeBytes: sizeBytes,
        contentType: contentType,
        issuedByName: issuedByName,
        notes: notes ?? this.notes,
        pageCount: pageCount,
      );

  bool get isReadable => scanStatus == ScanStatus.clean;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
