import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// An encrypted, expiring, sign-out-wiped cache for clinical *metadata*.
///
/// ## This reverses a previous rule, deliberately
///
/// `CLAUDE.md` used to say, flatly: never persist clinical data locally.
/// `purgeLegacyHealthData()` exists because an earlier build wrote age and
/// blood group into plaintext `SharedPreferences`. That rule was the right
/// response to that bug and too broad as a permanent policy — it also
/// prohibited the thing a patient on an Indian mobile network most needs,
/// which is to see when their appointment is while standing in a lift.
///
/// The rule is now narrower rather than absent, and every clause is load
/// bearing:
///
///  * **Encrypted at rest.** Keychain on iOS, AES-GCM under an RSA-wrapped
///    KeyStore key on Android — the same store the refresh token uses, not
///    `SharedPreferences`.
///  * **Never on web.** `flutter_secure_storage` on web is `localStorage`,
///    readable by any injected script. Caching a prescription list there would
///    be the original bug with a better name.
///  * **Metadata only.** Appointment times, doctor names, prescription
///    summaries. Never record file bytes, never a prescription PDF, never
///    anything from the records download path.
///  * **Expiring.** A stale clinical list is worse than none: an appointment
///    cancelled last week must not still be sitting on the phone as fact.
///  * **Wiped on sign-out**, before the next person on a shared phone signs in.
///
/// What it buys: the app opens to something useful with no signal. What it
/// costs is written down above, so the next person to read this can decide
/// whether the trade still holds rather than discovering it.
class ClinicalCache {
  ClinicalCache({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  /// Everything this class writes shares a prefix, so [wipe] can find it all
  /// without a registry that someone will forget to add a key to.
  static const _prefix = 'midoctor.cache.';

  /// How long a cached clinical list may still be shown.
  ///
  /// Twelve hours. Long enough to cover a commute, an overnight, and a day
  /// with no signal; short enough that an appointment cancelled yesterday is
  /// not still being presented as today's plan.
  static const maxAge = Duration(hours: 12);

  /// Disabled on web, where "secure storage" is `localStorage`.
  bool get isSupported => !kIsWeb;

  Future<void> write(String key, Object json) async {
    if (!isSupported) return;
    try {
      await _storage.write(
        key: '$_prefix$key',
        value: jsonEncode({
          'cachedAt': DateTime.now().toIso8601String(),
          'data': json,
        }),
      );
    } catch (e) {
      // A cache that cannot be written is a slower app, not a broken one.
      if (kDebugMode) debugPrint('Cache write failed for $key: $e');
    }
  }

  /// Returns the cached value and when it was stored, or null.
  ///
  /// Null covers every failure the same way — missing, expired, corrupt — and
  /// an expired entry is deleted on the way out rather than left to be read
  /// again and rejected again.
  Future<({Object data, DateTime cachedAt})?> read(String key) async {
    if (!isSupported) return null;
    try {
      final raw = await _storage.read(key: '$_prefix$key');
      if (raw == null) return null;

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.parse(decoded['cachedAt'] as String);

      if (DateTime.now().difference(cachedAt) > maxAge) {
        await _storage.delete(key: '$_prefix$key');
        return null;
      }

      return (data: decoded['data'] as Object, cachedAt: cachedAt);
    } catch (e) {
      // A corrupt entry is dropped rather than crashing a screen. It will be
      // rewritten by the next successful fetch.
      if (kDebugMode) debugPrint('Cache read failed for $key: $e');
      await _storage.delete(key: '$_prefix$key');
      return null;
    }
  }

  /// Removes everything. Called on sign-out.
  ///
  /// Reads the whole keychain rather than deleting a known list of keys,
  /// because a known list is a list somebody forgets to add to — and the
  /// consequence of forgetting here is one person's prescriptions surviving on
  /// a phone into the next person's session.
  Future<void> wipe() async {
    if (!isSupported) return;
    try {
      final all = await _storage.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_prefix)) await _storage.delete(key: key);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Cache wipe failed: $e');
    }
  }
}

final clinicalCacheProvider = Provider<ClinicalCache>((ref) => ClinicalCache());

/// When a screen is showing a cached copy rather than a live one.
///
/// Exposed so the UI can say so. An app that silently renders yesterday's
/// appointment list as though it were today's is not offline support — it is a
/// wrong answer delivered confidently, which for a clinical list is the worst
/// of the three possible behaviours.
class OfflineCacheStatus extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() => const {};

  void servedFromCache(String key, DateTime cachedAt) {
    state = {...state, key: cachedAt};
  }

  void servedLive(String key) {
    if (!state.containsKey(key)) return;
    final next = {...state}..remove(key);
    state = next;
  }
}

final offlineCacheStatusProvider =
    NotifierProvider<OfflineCacheStatus, Map<String, DateTime>>(
  OfflineCacheStatus.new,
);

/// Cache keys. Constants rather than inline strings so a typo cannot silently
/// create a second, never-read cache entry.
abstract final class CacheKeys {
  static const patientAppointments = 'appointments.patient';
  static const prescriptions = 'prescriptions.patient';
}
