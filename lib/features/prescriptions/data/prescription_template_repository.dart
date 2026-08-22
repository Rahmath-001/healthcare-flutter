import '../../../core/fixtures/fixture_backend.dart';
import '../../../core/network/api_client.dart';
import '../domain/prescription_template.dart';

/// A doctor's saved prescribing sets.
///
/// Private to the doctor who saved them. There is deliberately no sharing
/// between clinicians and no "practice library": a template is a personal
/// shortcut, and one doctor's set becoming another's default is how a
/// prescribing habit spreads without anybody deciding it should.
abstract class PrescriptionTemplateRepository {
  /// The caller's own templates, newest first.
  ///
  /// Items come back with their telemedicine classification resolved from the
  /// catalogue **now**, not as it stood when the template was saved.
  Future<List<PrescriptionTemplate>> list();

  /// Saves the current composer contents as a template.
  Future<PrescriptionTemplate> create({
    required String name,
    required List<TemplateItem> items,
    String? diagnosis,
    String? advice,
  });

  Future<void> delete(String id);
}

class FixturePrescriptionTemplateRepository
    implements PrescriptionTemplateRepository {
  FixturePrescriptionTemplateRepository({
    this.latency = const Duration(milliseconds: 200),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  @override
  Future<List<PrescriptionTemplate>> list() async {
    await Future<void>.delayed(latency);
    return _backend.prescriptionTemplates();
  }

  @override
  Future<PrescriptionTemplate> create({
    required String name,
    required List<TemplateItem> items,
    String? diagnosis,
    String? advice,
  }) async {
    await Future<void>.delayed(latency);
    return _backend.createPrescriptionTemplate(
      name: name,
      items: items,
      diagnosis: diagnosis,
      advice: advice,
    );
  }

  @override
  Future<void> delete(String id) async {
    await Future<void>.delayed(latency);
    _backend.deletePrescriptionTemplate(id);
  }
}

class ApiPrescriptionTemplateRepository
    implements PrescriptionTemplateRepository {
  ApiPrescriptionTemplateRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<PrescriptionTemplate>> list() async {
    final json = await _api.get<List<dynamic>>('/v1/prescriptions/templates');
    return json
        .map((e) => PrescriptionTemplate.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<PrescriptionTemplate> create({
    required String name,
    required List<TemplateItem> items,
    String? diagnosis,
    String? advice,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/prescriptions/templates',
      body: {
        'name': name,
        if (diagnosis != null) 'diagnosis': diagnosis,
        if (advice != null) 'advice': advice,
        // Drug ids and doses only. Names and classifications are the
        // catalogue's to supply, and sending them would store a second copy
        // that can drift away from it.
        'items': [for (final i in items) i.toJson()],
      },
    );
    return PrescriptionTemplate.fromJson(json);
  }

  @override
  Future<void> delete(String id) =>
      _api.delete<Map<String, dynamic>>('/v1/prescriptions/templates/$id');
}
