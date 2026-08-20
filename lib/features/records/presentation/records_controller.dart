import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../domain/medical_record.dart';

final ownRecordsProvider = FutureProvider<List<MedicalRecord>>((ref) async {
  return ref.watch(recordsRepositoryProvider).listOwn();
});

/// Records the signed-in provider may read for one patient.
///
/// Always resolved against a live consent grant server-side; there is no call
/// that returns a patient's records without one.
final grantedRecordsProvider =
    FutureProvider.family<List<MedicalRecord>, String>((ref, patientId) async {
  return ref.watch(recordsRepositoryProvider).listGranted(patientId);
});

/// Filter for the records list.
enum RecordFilter {
  all,
  fromDoctors,
  mine;

  String get label => switch (this) {
        RecordFilter.all => 'All',
        RecordFilter.fromDoctors => 'From doctors',
        RecordFilter.mine => 'Uploaded by me',
      };

  bool matches(MedicalRecord r) => switch (this) {
        RecordFilter.all => true,
        RecordFilter.fromDoctors => r.source == RecordSource.provider,
        RecordFilter.mine => r.source == RecordSource.patient,
      };
}

class RecordFilterNotifier extends Notifier<RecordFilter> {
  @override
  RecordFilter build() => RecordFilter.all;

  void set(RecordFilter filter) => state = filter;
}

final recordFilterProvider =
    NotifierProvider<RecordFilterNotifier, RecordFilter>(
  RecordFilterNotifier.new,
);
