import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/features/settings/data/account_repository.dart';
import 'package:healthcare_mobile/features/settings/domain/account_deletion.dart';
import 'package:healthcare_mobile/features/settings/domain/patient_profile.dart';

void main() {
  group('PatientProfile', () {
    test('derives age from the date of birth', () {
      final now = DateTime.now();
      final profile = PatientProfile(
        userId: 'u1',
        dateOfBirth: DateTime(now.year - 30, now.month, now.day),
      );
      expect(profile.age, 30);
    });

    test('does not count a birthday that has not happened yet this year', () {
      final now = DateTime.now();
      // One day short of the birthday, so the person is still 29.
      final dob = now
          .add(const Duration(days: 1))
          .subtract(const Duration(days: 365 * 30));
      final profile = PatientProfile(userId: 'u1', dateOfBirth: dob);
      expect(profile.age, lessThan(30));
    });

    test('age is null when no date of birth is known', () {
      expect(const PatientProfile(userId: 'u1').age, isNull);
    });

    test('parses the wire shape, including absent clinical fields', () {
      final profile = PatientProfile.fromJson(const {
        'userId': 'u1',
        'displayName': 'Priya',
        'dateOfBirth': '1994-04-12',
        'gender': 'FEMALE',
        'bloodGroup': 'O_POSITIVE',
        'allergies': ['Penicillin'],
        'chronicConditions': <String>[],
        'emergencyContactName': null,
        'emergencyContactPhone': null,
        'email': null,
        'phone': null,
      });

      expect(profile.displayName, 'Priya');
      expect(profile.gender, Gender.female);
      expect(profile.bloodGroup, BloodGroup.oPositive);
      expect(profile.dateOfBirth, DateTime(1994, 4, 12));
      expect(profile.allergies, ['Penicillin']);
      expect(profile.chronicConditions, isEmpty);
      expect(profile.emergencyContactName, isNull);
    });

    test('an unknown enum value degrades to null rather than throwing', () {
      // A server that adds a blood group the client has not shipped yet must
      // not crash every profile screen.
      expect(BloodGroup.fromWire('BOMBAY_POSITIVE'), isNull);
      expect(Gender.fromWire('NONBINARY'), isNull);
      expect(BloodGroup.fromWire(null), isNull);
    });
  });

  group('PatientProfileDraft', () {
    test('omits every field that was not set', () {
      // The API treats an absent key as "leave alone". Serialising nulls would
      // silently erase a patient's allergy list on any partial edit.
      const draft = PatientProfileDraft(displayName: 'Priya');
      expect(draft.toJson(), {'displayName': 'Priya'});
    });

    test('sends a date of birth as a calendar day, not an instant', () {
      // An ISO timestamp shifts across timezones and changes the day.
      final draft = PatientProfileDraft(dateOfBirth: DateTime(1994, 4, 5));
      expect(draft.toJson()['dateOfBirth'], '1994-04-05');
    });

    test('sends enums as their wire values', () {
      const draft = PatientProfileDraft(
        gender: Gender.undisclosed,
        bloodGroup: BloodGroup.abNegative,
      );
      expect(draft.toJson()['gender'], 'UNDISCLOSED');
      expect(draft.toJson()['bloodGroup'], 'AB_NEGATIVE');
    });

    test('an empty list is sent, because clearing a list is a real edit', () {
      const draft = PatientProfileDraft(allergies: []);
      expect(draft.toJson(), containsPair('allergies', isEmpty));
    });
  });

  group('AccountDeletion', () {
    test('carries the date the retained clinical tail may be destroyed', () {
      final outcome = AccountDeletion.fromJson(const {
        'status': 'REQUESTED',
        'clinicalRetentionUntil': '2029-01-01T00:00:00.000Z',
      });
      expect(outcome.clinicalRetentionUntil.year, 2029);
    });
  });

  group('FixtureAccountRepository', () {
    test('an update is visible on the next read', () async {
      final repo = FixtureAccountRepository(latency: Duration.zero);
      await repo.updateProfile(
        const PatientProfileDraft(bloodGroup: BloodGroup.abPositive),
      );
      final profile = await repo.profile();
      expect(profile.bloodGroup, BloodGroup.abPositive);
    });

    test('an update leaves untouched fields alone', () async {
      final repo = FixtureAccountRepository(latency: Duration.zero);
      final before = await repo.profile();
      await repo.updateProfile(const PatientProfileDraft(displayName: 'Meera'));
      final after = await repo.profile();

      expect(after.displayName, 'Meera');
      expect(after.allergies, before.allergies);
      expect(after.bloodGroup, before.bloodGroup);
    });

    test('the export is valid JSON a person could open', () async {
      final repo = FixtureAccountRepository(latency: Duration.zero);
      final decoded = jsonDecode(await repo.exportData());
      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map)['account'], isNotNull);
    });

    test('deletion reports a retention date in the future', () async {
      final repo = FixtureAccountRepository(latency: Duration.zero);
      final outcome = await repo.requestDeletion();
      expect(outcome.clinicalRetentionUntil.isAfter(DateTime.now()), isTrue);
    });
  });
}
