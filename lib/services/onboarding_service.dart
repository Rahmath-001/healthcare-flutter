import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  final SharedPreferences _prefs;

  OnboardingService(this._prefs);

  static const _keyComplete = 'onboarding_complete';
  static const _keyAge = 'profile_age';
  static const _keyBloodGroup = 'profile_blood_group';

  bool get isComplete => _prefs.getBool(_keyComplete) ?? false;

  Future<void> markComplete() => _prefs.setBool(_keyComplete, true);

  Future<void> saveProfile({String? age, String? bloodGroup}) async {
    if (age != null) await _prefs.setString(_keyAge, age);
    if (bloodGroup != null) await _prefs.setString(_keyBloodGroup, bloodGroup);
  }

  String? get age => _prefs.getString(_keyAge);
  String? get bloodGroup => _prefs.getString(_keyBloodGroup);
}
