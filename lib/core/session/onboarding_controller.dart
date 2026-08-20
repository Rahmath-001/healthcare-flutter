import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';

/// Whether the patient has finished first-run onboarding.
///
/// Backed by SharedPreferences because it is a UI preference, not user data.
class OnboardingController extends Notifier<bool> {
  static const _key = 'onboarding_complete';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> markComplete() async {
    await ref.read(sharedPreferencesProvider).setBool(_key, true);
    state = true;
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);

/// Keys written by builds that stored health data in plaintext SharedPreferences.
const _legacyHealthKeys = <String>['profile_age', 'profile_blood_group'];

/// Deletes clinical data left behind by earlier builds.
///
/// Age and blood group were previously written to SharedPreferences, which is
/// unencrypted and included in device backups. They now live server-side in
/// `patient_profiles`. This runs once at startup on upgrade; it is idempotent
/// and safe to call on a fresh install.
///
/// Returns the number of keys removed, so startup can log that the migration
/// actually happened without logging the values themselves.
Future<int> purgeLegacyHealthData(SharedPreferences prefs) async {
  var removed = 0;
  for (final key in _legacyHealthKeys) {
    if (prefs.containsKey(key)) {
      await prefs.remove(key);
      removed++;
    }
  }
  return removed;
}
