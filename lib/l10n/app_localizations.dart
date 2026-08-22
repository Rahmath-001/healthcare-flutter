import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'MiDoctor'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navAppointments.
  ///
  /// In en, this message translates to:
  /// **'Appointments'**
  String get navAppointments;

  /// No description provided for @navRecords.
  ///
  /// In en, this message translates to:
  /// **'Records'**
  String get navRecords;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @navToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get navToday;

  /// No description provided for @navSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get navSchedule;

  /// No description provided for @navPatients.
  ///
  /// In en, this message translates to:
  /// **'Patients'**
  String get navPatients;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get actionSignOut;

  /// No description provided for @actionBook.
  ///
  /// In en, this message translates to:
  /// **'Book appointment'**
  String get actionBook;

  /// No description provided for @actionJoin.
  ///
  /// In en, this message translates to:
  /// **'Join consultation'**
  String get actionJoin;

  /// No description provided for @actionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// No description provided for @actionSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get actionSend;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get actionNext;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get actionUpload;

  /// No description provided for @actionSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get actionSubmit;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get actionSkip;

  /// No description provided for @actionNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get actionNotNow;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'You are offline'**
  String get offline;

  /// No description provided for @offlineCopy.
  ///
  /// In en, this message translates to:
  /// **'Offline copy from {when}'**
  String offlineCopy(String when);

  /// No description provided for @offlineCopyBody.
  ///
  /// In en, this message translates to:
  /// **'This may be out of date. It will refresh when you are back online.'**
  String get offlineCopyBody;

  /// No description provided for @offlineCopyStale.
  ///
  /// In en, this message translates to:
  /// **'Saved {when} — check before relying on it'**
  String offlineCopyStale(String when);

  /// No description provided for @offlineCopyStaleBody.
  ///
  /// In en, this message translates to:
  /// **'Anything booked or cancelled since then is not shown here.'**
  String get offlineCopyStaleBody;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification settings'**
  String get notificationsSettings;

  /// No description provided for @notificationsMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get notificationsMarkAllRead;

  /// No description provided for @notificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get notificationsEmpty;

  /// No description provided for @notificationsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Appointment reminders and updates will appear here.'**
  String get notificationsEmptyBody;

  /// No description provided for @notificationsWhatToSend.
  ///
  /// In en, this message translates to:
  /// **'What to send'**
  String get notificationsWhatToSend;

  /// No description provided for @notificationsAlwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always sent — you need to know'**
  String get notificationsAlwaysOn;

  /// No description provided for @notificationsIgnoresQuietHours.
  ///
  /// In en, this message translates to:
  /// **'Sent even during quiet hours'**
  String get notificationsIgnoresQuietHours;

  /// No description provided for @notificationsQuietHours.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours'**
  String get notificationsQuietHours;

  /// No description provided for @notificationsQuietHoursBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing will be sent during these hours, except appointment changes and account alerts.'**
  String get notificationsQuietHoursBody;

  /// No description provided for @notificationsQuietFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get notificationsQuietFrom;

  /// No description provided for @notificationsQuietTo.
  ///
  /// In en, this message translates to:
  /// **'Until'**
  String get notificationsQuietTo;

  /// No description provided for @notificationKindReminder.
  ///
  /// In en, this message translates to:
  /// **'Appointment reminders'**
  String get notificationKindReminder;

  /// No description provided for @notificationKindChanged.
  ///
  /// In en, this message translates to:
  /// **'Appointment moved or cancelled'**
  String get notificationKindChanged;

  /// No description provided for @notificationKindPrescription.
  ///
  /// In en, this message translates to:
  /// **'New prescriptions'**
  String get notificationKindPrescription;

  /// No description provided for @notificationKindConsent.
  ///
  /// In en, this message translates to:
  /// **'Requests to see your records'**
  String get notificationKindConsent;

  /// No description provided for @notificationKindRecord.
  ///
  /// In en, this message translates to:
  /// **'Uploads finished checking'**
  String get notificationKindRecord;

  /// No description provided for @notificationKindRating.
  ///
  /// In en, this message translates to:
  /// **'Rate a consultation'**
  String get notificationKindRating;

  /// No description provided for @notificationKindAccount.
  ///
  /// In en, this message translates to:
  /// **'Account and verification'**
  String get notificationKindAccount;

  /// No description provided for @notificationsEnable.
  ///
  /// In en, this message translates to:
  /// **'Turn on notifications'**
  String get notificationsEnable;

  /// No description provided for @notificationsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Notifications are on'**
  String get notificationsEnabled;

  /// No description provided for @notificationsDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off. You can turn them on in your phone settings.'**
  String get notificationsDenied;

  /// No description provided for @notificationsOnboardingBody.
  ///
  /// In en, this message translates to:
  /// **'We will remind you before a consultation and tell you when a prescription is ready. No health details ever appear on your lock screen.'**
  String get notificationsOnboardingBody;

  /// No description provided for @sessionTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Signed out after 15 minutes of inactivity, to keep your health information private.'**
  String get sessionTimedOut;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'No internet connection.'**
  String get errorNetwork;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @authWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authWelcomeBack;

  /// No description provided for @authSignInToContinue.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get authSignInToContinue;

  /// No description provided for @authContinueWithPhone.
  ///
  /// In en, this message translates to:
  /// **'Continue with phone'**
  String get authContinueWithPhone;

  /// No description provided for @authContinueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueWithGoogle;

  /// No description provided for @authContinueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple'**
  String get authContinueWithApple;

  /// No description provided for @authNewHere.
  ///
  /// In en, this message translates to:
  /// **'New here? '**
  String get authNewHere;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authAlreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get authAlreadyHaveAccount;

  /// No description provided for @authSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// No description provided for @authSampleData.
  ///
  /// In en, this message translates to:
  /// **'Explore with sample data'**
  String get authSampleData;

  /// Shown only when the app is running on fixtures.
  ///
  /// In en, this message translates to:
  /// **'Signs in as Priya Sharma, a patient with appointments, records and prescriptions already in place.'**
  String get authSampleDataHint;

  /// No description provided for @authExploreAsDoctor.
  ///
  /// In en, this message translates to:
  /// **'Explore as an approved doctor'**
  String get authExploreAsDoctor;

  /// No description provided for @authExploreAsPendingDoctor.
  ///
  /// In en, this message translates to:
  /// **'Explore as a doctor awaiting verification'**
  String get authExploreAsPendingDoctor;

  /// No description provided for @authOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOr;

  /// No description provided for @authGoogleFailed.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in failed. Please try again.'**
  String get authGoogleFailed;

  /// No description provided for @authAppleFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple failed. Please try again.'**
  String get authAppleFailed;

  /// No description provided for @authRoleTitle.
  ///
  /// In en, this message translates to:
  /// **'How will you use MiDoctor?'**
  String get authRoleTitle;

  /// No description provided for @authRoleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You can only change this by contacting support, so choose carefully.'**
  String get authRoleSubtitle;

  /// No description provided for @authRolePatient.
  ///
  /// In en, this message translates to:
  /// **'I am a patient'**
  String get authRolePatient;

  /// No description provided for @authRolePatientBody.
  ///
  /// In en, this message translates to:
  /// **'Book appointments, keep your records, and consult a doctor.'**
  String get authRolePatientBody;

  /// No description provided for @authRoleProvider.
  ///
  /// In en, this message translates to:
  /// **'I am a doctor'**
  String get authRoleProvider;

  /// No description provided for @authRoleProviderBody.
  ///
  /// In en, this message translates to:
  /// **'See patients, write prescriptions, and manage your hours. Your credentials are verified before you can practise.'**
  String get authRoleProviderBody;

  /// No description provided for @phoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Your phone number'**
  String get phoneTitle;

  /// No description provided for @phoneIndiaOnly.
  ///
  /// In en, this message translates to:
  /// **'India only · Airtel, Jio or Vi · internet calling numbers are not accepted'**
  String get phoneIndiaOnly;

  /// No description provided for @phoneSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get phoneSendCode;

  /// No description provided for @phoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We will send a one-time code to confirm it is you.'**
  String get phoneSubtitle;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get phoneLabel;

  /// No description provided for @phoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 10-digit Indian mobile number.'**
  String get phoneInvalid;

  /// No description provided for @phoneCheckingCarrier.
  ///
  /// In en, this message translates to:
  /// **'Checking your number…'**
  String get phoneCheckingCarrier;

  /// No description provided for @phoneVoipRejected.
  ///
  /// In en, this message translates to:
  /// **'That looks like an internet calling number. Please use a mobile number.'**
  String get phoneVoipRejected;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get otpTitle;

  /// No description provided for @otpSentTo.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {phone}.'**
  String otpSentTo(String phone);

  /// No description provided for @otpResend.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get otpResend;

  /// No description provided for @otpResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String otpResendIn(int seconds);

  /// No description provided for @otpVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get otpVerify;

  /// No description provided for @otpInvalid.
  ///
  /// In en, this message translates to:
  /// **'That code is not right. Check it and try again.'**
  String get otpInvalid;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to MiDoctor'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Consult a doctor, keep your records, and stay in control of who sees them.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingHealthTitle.
  ///
  /// In en, this message translates to:
  /// **'A little about your health'**
  String get onboardingHealthTitle;

  /// No description provided for @onboardingHealthBody.
  ///
  /// In en, this message translates to:
  /// **'Help us personalise your experience.'**
  String get onboardingHealthBody;

  /// No description provided for @onboardingDateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get onboardingDateOfBirth;

  /// No description provided for @onboardingDateOfBirthHelp.
  ///
  /// In en, this message translates to:
  /// **'Used to check medicine doses are safe'**
  String get onboardingDateOfBirthHelp;

  /// No description provided for @onboardingBloodGroup.
  ///
  /// In en, this message translates to:
  /// **'Blood group'**
  String get onboardingBloodGroup;

  /// No description provided for @onboardingNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get onboardingNotSet;

  /// No description provided for @onboardingNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stay in the loop'**
  String get onboardingNotificationsTitle;

  /// No description provided for @onboardingNotificationsBody.
  ///
  /// In en, this message translates to:
  /// **'Reminders for your appointments, so you never miss a consultation.'**
  String get onboardingNotificationsBody;

  /// No description provided for @onboardingEnableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get onboardingEnableNotifications;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String homeGreeting(String name);

  /// No description provided for @homeGoodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get homeGoodMorning;

  /// No description provided for @homeGoodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get homeGoodAfternoon;

  /// No description provided for @homeGoodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get homeGoodEvening;

  /// No description provided for @homeFindDoctor.
  ///
  /// In en, this message translates to:
  /// **'Find a doctor'**
  String get homeFindDoctor;

  /// No description provided for @homeNextAppointment.
  ///
  /// In en, this message translates to:
  /// **'Your next appointment'**
  String get homeNextAppointment;

  /// No description provided for @homeNoUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Nothing booked yet'**
  String get homeNoUpcoming;

  /// No description provided for @homeNoUpcomingBody.
  ///
  /// In en, this message translates to:
  /// **'Search for a doctor to book your first consultation.'**
  String get homeNoUpcomingBody;

  /// No description provided for @homeQuickRecords.
  ///
  /// In en, this message translates to:
  /// **'My records'**
  String get homeQuickRecords;

  /// No description provided for @homeQuickPrescriptions.
  ///
  /// In en, this message translates to:
  /// **'Prescriptions'**
  String get homeQuickPrescriptions;

  /// No description provided for @homeQuickSharing.
  ///
  /// In en, this message translates to:
  /// **'Who can see my records'**
  String get homeQuickSharing;

  /// No description provided for @homeQuickSupport.
  ///
  /// In en, this message translates to:
  /// **'Get help'**
  String get homeQuickSupport;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Find a doctor'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Name, speciality or hospital'**
  String get searchHint;

  /// No description provided for @searchFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get searchFilters;

  /// No description provided for @searchClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get searchClearFilters;

  /// No description provided for @searchSpeciality.
  ///
  /// In en, this message translates to:
  /// **'Speciality'**
  String get searchSpeciality;

  /// No description provided for @searchCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get searchCity;

  /// No description provided for @searchMaxFee.
  ///
  /// In en, this message translates to:
  /// **'Maximum fee'**
  String get searchMaxFee;

  /// No description provided for @searchUpToFee.
  ///
  /// In en, this message translates to:
  /// **'Up to {fee}'**
  String searchUpToFee(String fee);

  /// No description provided for @searchMinRating.
  ///
  /// In en, this message translates to:
  /// **'Minimum rating'**
  String get searchMinRating;

  /// No description provided for @searchMode.
  ///
  /// In en, this message translates to:
  /// **'Consultation type'**
  String get searchMode;

  /// No description provided for @searchApply.
  ///
  /// In en, this message translates to:
  /// **'Show results'**
  String get searchApply;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No doctors match'**
  String get searchNoResults;

  /// No description provided for @searchNoResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Try removing a filter or searching for something broader.'**
  String get searchNoResultsBody;

  /// No description provided for @searchResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No doctors} =1{1 doctor} other{{count} doctors}}'**
  String searchResultCount(int count);

  /// No description provided for @doctorExperience.
  ///
  /// In en, this message translates to:
  /// **'{years, plural, =1{1 year experience} other{{years} years experience}}'**
  String doctorExperience(int years);

  /// LEGAL COPY adjacent. The MoHFW Telemedicine Practice Guidelines require a doctor's council registration number to be visible to the patient before and during a consultation.
  ///
  /// In en, this message translates to:
  /// **'Registration {number}'**
  String doctorRegistration(String number);

  /// No description provided for @doctorAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get doctorAbout;

  /// No description provided for @doctorLanguages.
  ///
  /// In en, this message translates to:
  /// **'Speaks'**
  String get doctorLanguages;

  /// No description provided for @doctorFees.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get doctorFees;

  /// No description provided for @doctorFeeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video consultation'**
  String get doctorFeeVideo;

  /// No description provided for @doctorFeeInPerson.
  ///
  /// In en, this message translates to:
  /// **'In person'**
  String get doctorFeeInPerson;

  /// No description provided for @doctorRatingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No ratings yet} =1{1 rating} other{{count} ratings}}'**
  String doctorRatingCount(int count);

  /// No description provided for @bookingTitle.
  ///
  /// In en, this message translates to:
  /// **'Book an appointment'**
  String get bookingTitle;

  /// No description provided for @bookingChooseDate.
  ///
  /// In en, this message translates to:
  /// **'Choose a date'**
  String get bookingChooseDate;

  /// No description provided for @bookingChooseTime.
  ///
  /// In en, this message translates to:
  /// **'Choose a time'**
  String get bookingChooseTime;

  /// No description provided for @bookingNoSlots.
  ///
  /// In en, this message translates to:
  /// **'No times available'**
  String get bookingNoSlots;

  /// No description provided for @bookingNoSlotsBody.
  ///
  /// In en, this message translates to:
  /// **'This doctor has no free slots that day. Try another date.'**
  String get bookingNoSlotsBody;

  /// No description provided for @waitlistJoin.
  ///
  /// In en, this message translates to:
  /// **'Tell me when a slot opens'**
  String get waitlistJoin;

  /// No description provided for @waitlistJoined.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the list.'**
  String get waitlistJoined;

  /// No description provided for @waitlistLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave the list'**
  String get waitlistLeave;

  /// No description provided for @waitlistOn.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the waiting list'**
  String get waitlistOn;

  /// No description provided for @waitlistNote.
  ///
  /// In en, this message translates to:
  /// **'We will tell everyone waiting at the same time. A slot is not held for you — it is first come, first served.'**
  String get waitlistNote;

  /// No description provided for @waitlistAnyDay.
  ///
  /// In en, this message translates to:
  /// **'Any day'**
  String get waitlistAnyDay;

  /// No description provided for @waitlistForDay.
  ///
  /// In en, this message translates to:
  /// **'For {date}'**
  String waitlistForDay(String date);

  /// No description provided for @bookingReason.
  ///
  /// In en, this message translates to:
  /// **'Reason for visit'**
  String get bookingReason;

  /// No description provided for @bookingReasonHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Fever for three days'**
  String get bookingReasonHint;

  /// No description provided for @bookingHoldExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Slot held for {countdown}'**
  String bookingHoldExpiresIn(String countdown);

  /// No description provided for @bookingHoldExpired.
  ///
  /// In en, this message translates to:
  /// **'That slot was released. Please pick another time.'**
  String get bookingHoldExpired;

  /// No description provided for @bookingNoPaymentNow.
  ///
  /// In en, this message translates to:
  /// **'No payment is taken now. Pay at the clinic or when you see the doctor.'**
  String get bookingNoPaymentNow;

  /// No description provided for @bookingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm booking'**
  String get bookingConfirm;

  /// No description provided for @bookingConfirmedTitle.
  ///
  /// In en, this message translates to:
  /// **'You are booked'**
  String get bookingConfirmedTitle;

  /// No description provided for @bookingConfirmedBody.
  ///
  /// In en, this message translates to:
  /// **'We have sent the details to your phone.'**
  String get bookingConfirmedBody;

  /// No description provided for @bookingReference.
  ///
  /// In en, this message translates to:
  /// **'Reference {code}'**
  String bookingReference(String code);

  /// No description provided for @bookingShareRecords.
  ///
  /// In en, this message translates to:
  /// **'Share your records with this doctor'**
  String get bookingShareRecords;

  /// No description provided for @bookingShareRecordsBody.
  ///
  /// In en, this message translates to:
  /// **'They can only see what you choose, and only until the date you set.'**
  String get bookingShareRecordsBody;

  /// No description provided for @bookingViewAppointment.
  ///
  /// In en, this message translates to:
  /// **'View appointment'**
  String get bookingViewAppointment;

  /// No description provided for @appointmentsUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get appointmentsUpcoming;

  /// No description provided for @appointmentsCancelledTab.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get appointmentsCancelledTab;

  /// No description provided for @appointmentsNoUpcoming.
  ///
  /// In en, this message translates to:
  /// **'No upcoming appointments'**
  String get appointmentsNoUpcoming;

  /// No description provided for @appointmentsNoUpcomingBody.
  ///
  /// In en, this message translates to:
  /// **'Book a consultation and it will show up here.'**
  String get appointmentsNoUpcomingBody;

  /// No description provided for @appointmentsNoPast.
  ///
  /// In en, this message translates to:
  /// **'No past appointments'**
  String get appointmentsNoPast;

  /// No description provided for @appointmentsNoCancelled.
  ///
  /// In en, this message translates to:
  /// **'No cancelled appointments'**
  String get appointmentsNoCancelled;

  /// No description provided for @actionBookShort.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get actionBookShort;

  /// No description provided for @appointmentsPast.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get appointmentsPast;

  /// No description provided for @appointmentsNone.
  ///
  /// In en, this message translates to:
  /// **'No appointments'**
  String get appointmentsNone;

  /// No description provided for @appointmentsNoneBody.
  ///
  /// In en, this message translates to:
  /// **'When you book a consultation it will appear here.'**
  String get appointmentsNoneBody;

  /// No description provided for @appointmentDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Appointment'**
  String get appointmentDetailTitle;

  /// No description provided for @appointmentReasonForVisit.
  ///
  /// In en, this message translates to:
  /// **'Reason for visit'**
  String get appointmentReasonForVisit;

  /// No description provided for @appointmentNoReasonGiven.
  ///
  /// In en, this message translates to:
  /// **'No reason given'**
  String get appointmentNoReasonGiven;

  /// No description provided for @appointmentFee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get appointmentFee;

  /// No description provided for @appointmentCancelTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this appointment?'**
  String get appointmentCancelTitle;

  /// No description provided for @appointmentCancelBody.
  ///
  /// In en, this message translates to:
  /// **'Let the doctor know why, so the slot can be offered to someone else.'**
  String get appointmentCancelBody;

  /// No description provided for @appointmentCancelReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get appointmentCancelReason;

  /// No description provided for @appointmentCancelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel appointment'**
  String get appointmentCancelConfirm;

  /// No description provided for @rescheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Move this appointment'**
  String get rescheduleTitle;

  /// No description provided for @rescheduleCurrent.
  ///
  /// In en, this message translates to:
  /// **'Currently {when}'**
  String rescheduleCurrent(String when);

  /// No description provided for @rescheduleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm new time'**
  String get rescheduleConfirm;

  /// No description provided for @rescheduleAction.
  ///
  /// In en, this message translates to:
  /// **'Reschedule'**
  String get rescheduleAction;

  /// No description provided for @rescheduleHoldNote.
  ///
  /// In en, this message translates to:
  /// **'Your current time is only released once the new one is confirmed.'**
  String get rescheduleHoldNote;

  /// No description provided for @rescheduleNoSlots.
  ///
  /// In en, this message translates to:
  /// **'No free times that day'**
  String get rescheduleNoSlots;

  /// No description provided for @rescheduleNoSlotsBody.
  ///
  /// In en, this message translates to:
  /// **'Try another date.'**
  String get rescheduleNoSlotsBody;

  /// No description provided for @rescheduleCurrentSlot.
  ///
  /// In en, this message translates to:
  /// **'{time} · now'**
  String rescheduleCurrentSlot(String time);

  /// No description provided for @rescheduleDone.
  ///
  /// In en, this message translates to:
  /// **'Appointment moved to {when}.'**
  String rescheduleDone(String when);

  /// No description provided for @appointmentKeepIt.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get appointmentKeepIt;

  /// No description provided for @appointmentCancelled.
  ///
  /// In en, this message translates to:
  /// **'Appointment cancelled.'**
  String get appointmentCancelled;

  /// No description provided for @appointmentFreeCancellation.
  ///
  /// In en, this message translates to:
  /// **'Free to cancel until {when}'**
  String appointmentFreeCancellation(String when);

  /// No description provided for @appointmentRate.
  ///
  /// In en, this message translates to:
  /// **'Rate this consultation'**
  String get appointmentRate;

  /// No description provided for @appointmentViewPrescription.
  ///
  /// In en, this message translates to:
  /// **'View prescription'**
  String get appointmentViewPrescription;

  /// No description provided for @recordsTitle.
  ///
  /// In en, this message translates to:
  /// **'Health records'**
  String get recordsTitle;

  /// No description provided for @recordsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get recordsFilterAll;

  /// No description provided for @recordsFilterFromDoctors.
  ///
  /// In en, this message translates to:
  /// **'From doctors'**
  String get recordsFilterFromDoctors;

  /// No description provided for @recordsFilterMine.
  ///
  /// In en, this message translates to:
  /// **'Uploaded by me'**
  String get recordsFilterMine;

  /// No description provided for @recordsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No records here yet'**
  String get recordsEmpty;

  /// No description provided for @recordsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Upload a report or scan to keep it with you.'**
  String get recordsEmptyBody;

  /// No description provided for @recordsUploadOne.
  ///
  /// In en, this message translates to:
  /// **'Upload a record'**
  String get recordsUploadOne;

  /// No description provided for @recordsWhoCanSee.
  ///
  /// In en, this message translates to:
  /// **'Who can see my records'**
  String get recordsWhoCanSee;

  /// No description provided for @recordsChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking file, available shortly'**
  String get recordsChecking;

  /// No description provided for @recordsCheckingShort.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get recordsCheckingShort;

  /// No description provided for @recordScanFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Check failed'**
  String get recordScanFailedShort;

  /// No description provided for @recordDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get recordDetailTitle;

  /// No description provided for @recordType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get recordType;

  /// No description provided for @recordAddedBy.
  ///
  /// In en, this message translates to:
  /// **'Added by'**
  String get recordAddedBy;

  /// No description provided for @recordAddedByYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get recordAddedByYou;

  /// No description provided for @recordAddedByDoctor.
  ///
  /// In en, this message translates to:
  /// **'A doctor'**
  String get recordAddedByDoctor;

  /// No description provided for @recordTakenOn.
  ///
  /// In en, this message translates to:
  /// **'Taken on'**
  String get recordTakenOn;

  /// No description provided for @recordUploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get recordUploaded;

  /// No description provided for @recordSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get recordSize;

  /// No description provided for @recordPages.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get recordPages;

  /// No description provided for @recordYourNotes.
  ///
  /// In en, this message translates to:
  /// **'Your notes'**
  String get recordYourNotes;

  /// No description provided for @recordOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open file'**
  String get recordOpenFile;

  /// No description provided for @recordDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this record?'**
  String get recordDeleteTitle;

  /// No description provided for @recordDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be removed from your records, and any doctor you have shared it with will lose access to it.\n\nThis cannot be undone.'**
  String recordDeleteBody(String title);

  /// No description provided for @recordKeepIt.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get recordKeepIt;

  /// No description provided for @recordScanPending.
  ///
  /// In en, this message translates to:
  /// **'This file is still being checked for viruses. It will open once the check finishes.'**
  String get recordScanPending;

  /// No description provided for @recordScanInfected.
  ///
  /// In en, this message translates to:
  /// **'This file failed a virus check and cannot be opened or shared.'**
  String get recordScanInfected;

  /// No description provided for @recordScanFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not check this file. Try uploading it again.'**
  String get recordScanFailed;

  /// No description provided for @recordCannotDisplay.
  ///
  /// In en, this message translates to:
  /// **'Cannot display this file'**
  String get recordCannotDisplay;

  /// No description provided for @recordCannotDisplayBody.
  ///
  /// In en, this message translates to:
  /// **'The file downloaded, but this device cannot render that format.'**
  String get recordCannotDisplayBody;

  /// No description provided for @uploadTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload a record'**
  String get uploadTitle;

  /// No description provided for @uploadTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get uploadTakePhoto;

  /// No description provided for @uploadFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get uploadFromGallery;

  /// No description provided for @uploadPickDocument.
  ///
  /// In en, this message translates to:
  /// **'Pick a document'**
  String get uploadPickDocument;

  /// No description provided for @uploadRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get uploadRecordTitle;

  /// No description provided for @uploadRecordTitleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Complete Blood Count'**
  String get uploadRecordTitleHint;

  /// No description provided for @uploadRecordType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get uploadRecordType;

  /// No description provided for @uploadDateOnReport.
  ///
  /// In en, this message translates to:
  /// **'Date on the report'**
  String get uploadDateOnReport;

  /// No description provided for @uploadNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get uploadNotes;

  /// No description provided for @uploadPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Your records are private to you. A doctor can only see one if you share it, and you can revoke that at any time. Files are checked for viruses before they become available.'**
  String get uploadPrivacyNote;

  /// No description provided for @uploadDone.
  ///
  /// In en, this message translates to:
  /// **'Uploaded. It will be available once checked.'**
  String get uploadDone;

  /// No description provided for @sharingTitle.
  ///
  /// In en, this message translates to:
  /// **'Who can see my records'**
  String get sharingTitle;

  /// No description provided for @sharingTabAccess.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get sharingTabAccess;

  /// No description provided for @sharingTabRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get sharingTabRequests;

  /// No description provided for @sharingTabLog.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get sharingTabLog;

  /// LEGAL COPY adjacent. Reassurance about the default state of consent.
  ///
  /// In en, this message translates to:
  /// **'Nobody can see your records'**
  String get sharingNobodyHasAccess;

  /// No description provided for @sharingNobodyHasAccessBody.
  ///
  /// In en, this message translates to:
  /// **'A doctor can only see a record if you share it with them.'**
  String get sharingNobodyHasAccessBody;

  /// No description provided for @sharingStopSharing.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get sharingStopSharing;

  /// No description provided for @sharingEndsIn.
  ///
  /// In en, this message translates to:
  /// **'Ends in {duration}'**
  String sharingEndsIn(String duration);

  /// LEGAL COPY. Confirms revocation of consent, which the DPDP Act requires to be as easy to withdraw as it was to give.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing with {name}? They will lose access immediately.'**
  String sharingRevokeConfirm(String name);

  /// No description provided for @sharingRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access revoked.'**
  String get sharingRevoked;

  /// No description provided for @sharingNoRequests.
  ///
  /// In en, this message translates to:
  /// **'No requests'**
  String get sharingNoRequests;

  /// No description provided for @sharingNoRequestsBody.
  ///
  /// In en, this message translates to:
  /// **'When a doctor asks to see your records, it will appear here.'**
  String get sharingNoRequestsBody;

  /// No description provided for @sharingApprove.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get sharingApprove;

  /// No description provided for @sharingDeny.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get sharingDeny;

  /// No description provided for @sharingNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get sharingNoActivity;

  /// No description provided for @sharingNoActivityBody.
  ///
  /// In en, this message translates to:
  /// **'Every time someone opens one of your records, it is recorded here.'**
  String get sharingNoActivityBody;

  /// No description provided for @sharingExpiresLabel.
  ///
  /// In en, this message translates to:
  /// **'Access ends'**
  String get sharingExpiresLabel;

  /// No description provided for @sharingPurpose.
  ///
  /// In en, this message translates to:
  /// **'Purpose'**
  String get sharingPurpose;

  /// No description provided for @sharingGranted.
  ///
  /// In en, this message translates to:
  /// **'Access granted.'**
  String get sharingGranted;

  /// No description provided for @prescriptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Prescriptions'**
  String get prescriptionsTitle;

  /// No description provided for @prescriptionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No prescriptions'**
  String get prescriptionsEmpty;

  /// No description provided for @prescriptionsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'A prescription written during a consultation will appear here.'**
  String get prescriptionsEmptyBody;

  /// No description provided for @refillRequest.
  ///
  /// In en, this message translates to:
  /// **'Ask for a repeat'**
  String get refillRequest;

  /// No description provided for @refillTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask for a repeat'**
  String get refillTitle;

  /// No description provided for @refillBody.
  ///
  /// In en, this message translates to:
  /// **'Your doctor will review this and decide. A repeat is not automatic.'**
  String get refillBody;

  /// No description provided for @refillNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Anything your doctor should know (optional)'**
  String get refillNoteHint;

  /// No description provided for @refillSend.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get refillSend;

  /// No description provided for @refillSent.
  ///
  /// In en, this message translates to:
  /// **'Sent to your doctor.'**
  String get refillSent;

  /// No description provided for @refillPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your doctor'**
  String get refillPending;

  /// No description provided for @refillWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get refillWithdraw;

  /// No description provided for @refillsTitle.
  ///
  /// In en, this message translates to:
  /// **'Repeat requests'**
  String get refillsTitle;

  /// No description provided for @refillsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No repeat requests'**
  String get refillsEmpty;

  /// No description provided for @refillsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Ask for a repeat from a prescription and it will appear here.'**
  String get refillsEmptyBody;

  /// No description provided for @refillApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve and issue'**
  String get refillApprove;

  /// No description provided for @refillDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get refillDecline;

  /// No description provided for @refillDeclineTitle.
  ///
  /// In en, this message translates to:
  /// **'Decline this repeat'**
  String get refillDeclineTitle;

  /// No description provided for @refillDeclineWhy.
  ///
  /// In en, this message translates to:
  /// **'Why are you declining?'**
  String get refillDeclineWhy;

  /// No description provided for @refillDeclineNote.
  ///
  /// In en, this message translates to:
  /// **'What should the patient do next?'**
  String get refillDeclineNote;

  /// No description provided for @refillDeclineNoteRequired.
  ///
  /// In en, this message translates to:
  /// **'A note is required. The patient needs to know whether to book a review, wait, or stop taking this.'**
  String get refillDeclineNoteRequired;

  /// No description provided for @refillDeclineSend.
  ///
  /// In en, this message translates to:
  /// **'Send decision'**
  String get refillDeclineSend;

  /// No description provided for @refillDecided.
  ///
  /// In en, this message translates to:
  /// **'Decision sent to the patient.'**
  String get refillDecided;

  /// No description provided for @refillApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved — a new prescription has been issued'**
  String get refillApproved;

  /// No description provided for @refillDeclinedBy.
  ///
  /// In en, this message translates to:
  /// **'Declined by {doctor}'**
  String refillDeclinedBy(String doctor);

  /// No description provided for @prescriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Prescription'**
  String get prescriptionTitle;

  /// No description provided for @prescriptionShare.
  ///
  /// In en, this message translates to:
  /// **'Share or save as PDF'**
  String get prescriptionShare;

  /// No description provided for @prescriptionPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get prescriptionPrint;

  /// No description provided for @prescriptionDiagnosis.
  ///
  /// In en, this message translates to:
  /// **'Diagnosis'**
  String get prescriptionDiagnosis;

  /// No description provided for @prescriptionAdvice.
  ///
  /// In en, this message translates to:
  /// **'Advice'**
  String get prescriptionAdvice;

  /// No description provided for @prescriptionMedicines.
  ///
  /// In en, this message translates to:
  /// **'Medicines'**
  String get prescriptionMedicines;

  /// No description provided for @prescriptionFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Follow up on {date}'**
  String prescriptionFollowUp(String date);

  /// No description provided for @followUpBook.
  ///
  /// In en, this message translates to:
  /// **'Book the follow-up'**
  String get followUpBook;

  /// No description provided for @followUpDue.
  ///
  /// In en, this message translates to:
  /// **'Your doctor asked to see you again'**
  String get followUpDue;

  /// No description provided for @followUpOverdue.
  ///
  /// In en, this message translates to:
  /// **'This follow-up was due {when}'**
  String followUpOverdue(String when);

  /// No description provided for @prescriptionVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get prescriptionVerificationCode;

  /// No description provided for @prescriptionVerificationBody.
  ///
  /// In en, this message translates to:
  /// **'A pharmacy can use this to confirm the prescription is genuine.'**
  String get prescriptionVerificationBody;

  /// LEGAL COPY. Retention notice for a clinical record.
  ///
  /// In en, this message translates to:
  /// **'Kept until {date}'**
  String prescriptionRetainedUntil(String date);

  /// No description provided for @consultationTitle.
  ///
  /// In en, this message translates to:
  /// **'Consultation'**
  String get consultationTitle;

  /// No description provided for @noteTitle.
  ///
  /// In en, this message translates to:
  /// **'Consultation notes'**
  String get noteTitle;

  /// No description provided for @noteWrite.
  ///
  /// In en, this message translates to:
  /// **'Write consultation notes'**
  String get noteWrite;

  /// No description provided for @noteHint.
  ///
  /// In en, this message translates to:
  /// **'What you found, what you advised, what happens next'**
  String get noteHint;

  /// No description provided for @noteSave.
  ///
  /// In en, this message translates to:
  /// **'Save notes'**
  String get noteSave;

  /// No description provided for @noteSaved.
  ///
  /// In en, this message translates to:
  /// **'Notes saved to the patient record.'**
  String get noteSaved;

  /// No description provided for @noteImmutable.
  ///
  /// In en, this message translates to:
  /// **'Notes cannot be edited once saved. Corrections are added as an addendum, with their own timestamp.'**
  String get noteImmutable;

  /// No description provided for @noteNone.
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get noteNone;

  /// No description provided for @noteNoneBody.
  ///
  /// In en, this message translates to:
  /// **'Your doctor has not written up this consultation.'**
  String get noteNoneBody;

  /// No description provided for @noteAddendum.
  ///
  /// In en, this message translates to:
  /// **'Add an addendum'**
  String get noteAddendum;

  /// No description provided for @noteAddendumSave.
  ///
  /// In en, this message translates to:
  /// **'Save addendum'**
  String get noteAddendumSave;

  /// No description provided for @noteAddendumSaved.
  ///
  /// In en, this message translates to:
  /// **'Addendum added.'**
  String get noteAddendumSaved;

  /// No description provided for @noteAddendumLabel.
  ///
  /// In en, this message translates to:
  /// **'Addendum'**
  String get noteAddendumLabel;

  /// No description provided for @noteWrittenBy.
  ///
  /// In en, this message translates to:
  /// **'{doctor} · Reg. {registration}'**
  String noteWrittenBy(String doctor, String registration);

  /// LEGAL COPY. Heading of the telemedicine consent gate, shown before a consultation connects. Required by the MoHFW Telemedicine Practice Guidelines. Any translation must be reviewed by a qualified legal translator before release.
  ///
  /// In en, this message translates to:
  /// **'Before you begin'**
  String get consentTelemedicineTitle;

  /// LEGAL COPY. Part of the consent record; its exact text is hashed as proof of what was agreed.
  ///
  /// In en, this message translates to:
  /// **'This consultation is not recorded. No video or audio is saved.'**
  String get consentNotRecorded;

  /// LEGAL COPY. Retention notice. Requires legal review before translation ships.
  ///
  /// In en, this message translates to:
  /// **'Chat messages, the doctor\'s notes and any prescription are kept as part of your medical record.'**
  String get consentRecordKept;

  /// LEGAL COPY. Reflects the MoHFW telemedicine drug lists.
  ///
  /// In en, this message translates to:
  /// **'Some medicines cannot be prescribed remotely. Your doctor may ask you to visit in person.'**
  String get consentRestrictedMedicines;

  /// LEGAL COPY. Safety notice. A mistranslation here is a safety issue, not a cosmetic one.
  ///
  /// In en, this message translates to:
  /// **'Telemedicine is not for emergencies. If this is urgent, go to the nearest hospital.'**
  String get consentNotEmergency;

  /// LEGAL COPY. The agreement itself. Hashed into the consent record.
  ///
  /// In en, this message translates to:
  /// **'I consent to this teleconsultation and confirm the information I give will be accurate.'**
  String get consentAgree;

  /// No description provided for @consultationWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the doctor to join…'**
  String get consultationWaiting;

  /// No description provided for @consultationConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get consultationConnecting;

  /// No description provided for @consultationEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get consultationEnd;

  /// No description provided for @consultationSwitchToAudio.
  ///
  /// In en, this message translates to:
  /// **'Switch to audio'**
  String get consultationSwitchToAudio;

  /// No description provided for @consultationPoorConnection.
  ///
  /// In en, this message translates to:
  /// **'Your connection is poor. Switching to audio may help.'**
  String get consultationPoorConnection;

  /// No description provided for @consultationChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get consultationChat;

  /// No description provided for @consultationChatHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message'**
  String get consultationChatHint;

  /// No description provided for @consultationEnded.
  ///
  /// In en, this message translates to:
  /// **'Consultation ended'**
  String get consultationEnded;

  /// No description provided for @consultationNotRecordedBadge.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get consultationNotRecordedBadge;

  /// No description provided for @consultationCameraOff.
  ///
  /// In en, this message translates to:
  /// **'Camera is off'**
  String get consultationCameraOff;

  /// No description provided for @consultationJoinFromPhone.
  ///
  /// In en, this message translates to:
  /// **'Video consultations are only available in the MiDoctor app. Please join from your phone.'**
  String get consultationJoinFromPhone;

  /// No description provided for @rateTitle.
  ///
  /// In en, this message translates to:
  /// **'Rate your consultation'**
  String get rateTitle;

  /// No description provided for @rateWith.
  ///
  /// In en, this message translates to:
  /// **'How was your consultation with {name}?'**
  String rateWith(String name);

  /// No description provided for @rateComment.
  ///
  /// In en, this message translates to:
  /// **'Tell others what it was like (optional)'**
  String get rateComment;

  /// No description provided for @rateModerationNote.
  ///
  /// In en, this message translates to:
  /// **'Reviews are checked before they are published.'**
  String get rateModerationNote;

  /// No description provided for @rateSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit rating'**
  String get rateSubmit;

  /// No description provided for @rateThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you. Your rating will appear once it is reviewed.'**
  String get rateThanks;

  /// No description provided for @providerRatingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your ratings'**
  String get providerRatingsTitle;

  /// No description provided for @providerRatingsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No ratings yet'**
  String get providerRatingsEmpty;

  /// No description provided for @providerRatingsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Patients can rate a consultation once it is completed.'**
  String get providerRatingsEmptyBody;

  /// No description provided for @ratingReplyAction.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get ratingReplyAction;

  /// No description provided for @ratingReplyTitle.
  ///
  /// In en, this message translates to:
  /// **'Reply publicly'**
  String get ratingReplyTitle;

  /// No description provided for @ratingReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Answer briefly and without clinical detail'**
  String get ratingReplyHint;

  /// No description provided for @ratingReplyNote.
  ///
  /// In en, this message translates to:
  /// **'Your reply is public and is reviewed before it appears. Never include anything about the patient’s condition or treatment.'**
  String get ratingReplyNote;

  /// No description provided for @ratingReplySend.
  ///
  /// In en, this message translates to:
  /// **'Send reply'**
  String get ratingReplySend;

  /// No description provided for @ratingReplyPending.
  ///
  /// In en, this message translates to:
  /// **'Your reply is being reviewed'**
  String get ratingReplyPending;

  /// No description provided for @ratingReplyLabel.
  ///
  /// In en, this message translates to:
  /// **'Your reply'**
  String get ratingReplyLabel;

  /// No description provided for @ratingReplySent.
  ///
  /// In en, this message translates to:
  /// **'Reply sent for review.'**
  String get ratingReplySent;

  /// No description provided for @rateEditWindow.
  ///
  /// In en, this message translates to:
  /// **'You can change this for {duration}'**
  String rateEditWindow(String duration);

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Get help'**
  String get supportTitle;

  /// No description provided for @supportNewTicket.
  ///
  /// In en, this message translates to:
  /// **'New request'**
  String get supportNewTicket;

  /// No description provided for @supportNoTickets.
  ///
  /// In en, this message translates to:
  /// **'No requests yet'**
  String get supportNoTickets;

  /// No description provided for @supportNoTicketsBody.
  ///
  /// In en, this message translates to:
  /// **'If something is not working, tell us and we will look into it.'**
  String get supportNoTicketsBody;

  /// No description provided for @supportSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get supportSubject;

  /// No description provided for @supportCategory.
  ///
  /// In en, this message translates to:
  /// **'What is this about?'**
  String get supportCategory;

  /// No description provided for @supportDescribe.
  ///
  /// In en, this message translates to:
  /// **'Tell us what happened'**
  String get supportDescribe;

  /// Support staff hold no consent grant, so the copy steers users away from clinical detail.
  ///
  /// In en, this message translates to:
  /// **'Please do not include medical details here.'**
  String get supportDescribeHint;

  /// No description provided for @supportReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Write a reply'**
  String get supportReplyHint;

  /// No description provided for @supportCreated.
  ///
  /// In en, this message translates to:
  /// **'Sent. We will get back to you.'**
  String get supportCreated;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileBloodGroup.
  ///
  /// In en, this message translates to:
  /// **'Blood group'**
  String get profileBloodGroup;

  /// No description provided for @profileAge.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get profileAge;

  /// No description provided for @profileEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get profileEditProfile;

  /// No description provided for @profileSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get profileSettings;

  /// No description provided for @profileHelp.
  ///
  /// In en, this message translates to:
  /// **'Help and support'**
  String get profileHelp;

  /// No description provided for @profileNotSet.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get profileNotSet;

  /// No description provided for @editProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfileTitle;

  /// No description provided for @editProfileFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get editProfileFullName;

  /// No description provided for @editProfileNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get editProfileNameRequired;

  /// No description provided for @editProfileDateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get editProfileDateOfBirth;

  /// No description provided for @editProfileGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get editProfileGender;

  /// No description provided for @editProfileBloodGroup.
  ///
  /// In en, this message translates to:
  /// **'Blood group'**
  String get editProfileBloodGroup;

  /// No description provided for @editProfileAllergies.
  ///
  /// In en, this message translates to:
  /// **'Allergies'**
  String get editProfileAllergies;

  /// No description provided for @editProfileAllergiesHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Penicillin, peanuts'**
  String get editProfileAllergiesHint;

  /// No description provided for @editProfileAllergiesHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown to any doctor you consult'**
  String get editProfileAllergiesHelp;

  /// No description provided for @editProfileConditions.
  ///
  /// In en, this message translates to:
  /// **'Ongoing conditions'**
  String get editProfileConditions;

  /// No description provided for @editProfileConditionsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Type 2 diabetes, hypertension'**
  String get editProfileConditionsHint;

  /// No description provided for @editProfileEmergencyContact.
  ///
  /// In en, this message translates to:
  /// **'Emergency contact'**
  String get editProfileEmergencyContact;

  /// No description provided for @emergencyCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get emergencyCall;

  /// No description provided for @emergencyCallFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the dialer on this device.'**
  String get emergencyCallFailed;

  /// No description provided for @editProfileContactName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get editProfileContactName;

  /// No description provided for @editProfilePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get editProfilePhone;

  /// No description provided for @editProfileSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get editProfileSaveChanges;

  /// No description provided for @editProfileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get editProfileUpdated;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy and your rights'**
  String get settingsPrivacy;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// No description provided for @settingsSignOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out of MiDoctor?'**
  String get settingsSignOutConfirm;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy and your rights'**
  String get privacyTitle;

  /// No description provided for @privacyYourRights.
  ///
  /// In en, this message translates to:
  /// **'Your rights'**
  String get privacyYourRights;

  /// LEGAL COPY. DPDP data-principal rights summary. Requires legal review before translation ships.
  ///
  /// In en, this message translates to:
  /// **'Under India\'s Digital Personal Data Protection Act, you can see what we hold about you, correct it, take a copy elsewhere, and ask us to delete it.'**
  String get privacyRightsBody;

  /// No description provided for @privacyDownloadData.
  ///
  /// In en, this message translates to:
  /// **'Download my data'**
  String get privacyDownloadData;

  /// No description provided for @privacyDownloadDataBody.
  ///
  /// In en, this message translates to:
  /// **'Profile, appointments, records and sharing history'**
  String get privacyDownloadDataBody;

  /// No description provided for @privacyCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct my information'**
  String get privacyCorrect;

  /// No description provided for @privacyCorrectBody.
  ///
  /// In en, this message translates to:
  /// **'Update your profile details'**
  String get privacyCorrectBody;

  /// No description provided for @privacyRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'How long we keep things'**
  String get privacyRetentionTitle;

  /// LEGAL COPY. Retention notice. Requires legal review before translation ships.
  ///
  /// In en, this message translates to:
  /// **'Consultation notes and prescriptions: 3 years, as medical record rules require'**
  String get privacyRetentionClinical;

  /// No description provided for @privacyRetentionConsultations.
  ///
  /// In en, this message translates to:
  /// **'Video and audio consultations: never recorded'**
  String get privacyRetentionConsultations;

  /// No description provided for @privacyRetentionChat.
  ///
  /// In en, this message translates to:
  /// **'Chat messages from a consultation: kept with your medical record'**
  String get privacyRetentionChat;

  /// No description provided for @privacyRetentionAccessLog.
  ///
  /// In en, this message translates to:
  /// **'Record access log: kept so you can always audit who looked at what'**
  String get privacyRetentionAccessLog;

  /// No description provided for @privacyGrievanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Questions or complaints'**
  String get privacyGrievanceTitle;

  /// No description provided for @privacyGrievanceOfficer.
  ///
  /// In en, this message translates to:
  /// **'Grievance Officer'**
  String get privacyGrievanceOfficer;

  /// No description provided for @privacyDangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get privacyDangerZone;

  /// No description provided for @privacyDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get privacyDeleteAccount;

  /// No description provided for @privacyDeleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone'**
  String get privacyDeleteAccountBody;

  /// No description provided for @privacyDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get privacyDeleteTitle;

  /// LEGAL COPY. Erasure notice, including the statutory retention exception. Requires legal review before translation ships.
  ///
  /// In en, this message translates to:
  /// **'Your profile, appointments and sharing permissions will be deleted, and every doctor will immediately lose access to your records.\n\nConsultation notes and prescriptions must be kept for 3 years under medical record rules, so those are retained and then deleted. They are not used for anything else.\n\nThis cannot be undone.'**
  String get privacyDeleteWarning;

  /// No description provided for @privacyKeepAccount.
  ///
  /// In en, this message translates to:
  /// **'Keep my account'**
  String get privacyKeepAccount;

  /// LEGAL COPY. Confirms erasure and the statutory retention that survives it.
  ///
  /// In en, this message translates to:
  /// **'Your account is deleted. Consultation notes and prescriptions are kept until {date} because medical record rules require it, and are then destroyed.'**
  String privacyDeleted(String date);

  /// No description provided for @privacyExportReady.
  ///
  /// In en, this message translates to:
  /// **'Your data is ready to save.'**
  String get privacyExportReady;

  /// No description provided for @privacySignedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String privacySignedInAs(String name);

  /// No description provided for @blockedTitle.
  ///
  /// In en, this message translates to:
  /// **'You cannot use MiDoctor right now'**
  String get blockedTitle;

  /// No description provided for @blockedSuspended.
  ///
  /// In en, this message translates to:
  /// **'Your account is suspended. Contact support if you think this is a mistake.'**
  String get blockedSuspended;

  /// No description provided for @blockedDeactivated.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deactivated.'**
  String get blockedDeactivated;

  /// No description provided for @blockedStaff.
  ///
  /// In en, this message translates to:
  /// **'This account is for MiDoctor staff. Please use the operations console.'**
  String get blockedStaff;

  /// No description provided for @blockedContactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get blockedContactSupport;

  /// No description provided for @providerTodayTitle.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get providerTodayTitle;

  /// No description provided for @providerTodayNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled'**
  String get providerTodayNone;

  /// No description provided for @providerTodayNoneBody.
  ///
  /// In en, this message translates to:
  /// **'Your consultations for today will appear here.'**
  String get providerTodayNoneBody;

  /// No description provided for @providerCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Check in'**
  String get providerCheckIn;

  /// No description provided for @providerStartConsultation.
  ///
  /// In en, this message translates to:
  /// **'Start consultation'**
  String get providerStartConsultation;

  /// No description provided for @providerWritePrescription.
  ///
  /// In en, this message translates to:
  /// **'Write prescription'**
  String get providerWritePrescription;

  /// No description provided for @providerRequestRecords.
  ///
  /// In en, this message translates to:
  /// **'Request records'**
  String get providerRequestRecords;

  /// No description provided for @providerPatientsTitle.
  ///
  /// In en, this message translates to:
  /// **'Patients'**
  String get providerPatientsTitle;

  /// No description provided for @providerPatientsNone.
  ///
  /// In en, this message translates to:
  /// **'No patients yet'**
  String get providerPatientsNone;

  /// No description provided for @providerPatientsNoneBody.
  ///
  /// In en, this message translates to:
  /// **'Patients who share records with you will appear here.'**
  String get providerPatientsNoneBody;

  /// No description provided for @availabilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Your hours'**
  String get availabilityTitle;

  /// No description provided for @availabilityAddHours.
  ///
  /// In en, this message translates to:
  /// **'Add hours'**
  String get availabilityAddHours;

  /// No description provided for @availabilityNone.
  ///
  /// In en, this message translates to:
  /// **'No hours set'**
  String get availabilityNone;

  /// No description provided for @availabilityNoneBody.
  ///
  /// In en, this message translates to:
  /// **'Add your working hours so patients can book with you.'**
  String get availabilityNoneBody;

  /// No description provided for @availabilityDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get availabilityDay;

  /// No description provided for @availabilityFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get availabilityFrom;

  /// No description provided for @availabilityTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get availabilityTo;

  /// No description provided for @availabilityAppointmentLength.
  ///
  /// In en, this message translates to:
  /// **'Appointment length'**
  String get availabilityAppointmentLength;

  /// No description provided for @availabilityMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes'**
  String availabilityMinutes(int minutes);

  /// No description provided for @availabilitySlotCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 slot} other{{count} slots}}'**
  String availabilitySlotCount(int count);

  /// No description provided for @availabilityBlockDay.
  ///
  /// In en, this message translates to:
  /// **'Block a day'**
  String get availabilityBlockDay;

  /// No description provided for @availabilityBlockedDays.
  ///
  /// In en, this message translates to:
  /// **'Blocked days'**
  String get availabilityBlockedDays;

  /// No description provided for @availabilityNoBlockedDays.
  ///
  /// In en, this message translates to:
  /// **'No days blocked'**
  String get availabilityNoBlockedDays;

  /// No description provided for @availabilityBlockReason.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get availabilityBlockReason;

  /// No description provided for @availabilityPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get availabilityPaused;

  /// No description provided for @verificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get verificationTitle;

  /// No description provided for @verificationSubmitDocuments.
  ///
  /// In en, this message translates to:
  /// **'Submit documents'**
  String get verificationSubmitDocuments;

  /// No description provided for @verificationResubmitDocuments.
  ///
  /// In en, this message translates to:
  /// **'Resubmit documents'**
  String get verificationResubmitDocuments;

  /// No description provided for @verificationDraftTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get verificationDraftTitle;

  /// No description provided for @verificationDraftBody.
  ///
  /// In en, this message translates to:
  /// **'Upload your degree certificate, medical registration, identity proof and hospital affiliation to start seeing patients.'**
  String get verificationDraftBody;

  /// No description provided for @verificationInProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification in progress'**
  String get verificationInProgressTitle;

  /// No description provided for @verificationInProgressBody.
  ///
  /// In en, this message translates to:
  /// **'Our team is reviewing your documents. This usually takes 2–3 working days, and we will notify you as soon as it is done.'**
  String get verificationInProgressBody;

  /// No description provided for @verificationRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification unsuccessful'**
  String get verificationRejectedTitle;

  /// No description provided for @verificationRejectedBody.
  ///
  /// In en, this message translates to:
  /// **'We could not verify your documents. Check the reason sent to you and submit again.'**
  String get verificationRejectedBody;

  /// No description provided for @verificationResubmitTitle.
  ///
  /// In en, this message translates to:
  /// **'More information needed'**
  String get verificationResubmitTitle;

  /// No description provided for @verificationResubmitBody.
  ///
  /// In en, this message translates to:
  /// **'Some of your documents need to be resubmitted. Please review the notes we sent and upload them again.'**
  String get verificationResubmitBody;

  /// No description provided for @verificationSuspendedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account under review'**
  String get verificationSuspendedTitle;

  /// No description provided for @verificationSuspendedBody.
  ///
  /// In en, this message translates to:
  /// **'Your provider account is temporarily suspended pending a review. Please contact MiDoctor support.'**
  String get verificationSuspendedBody;

  /// No description provided for @verificationDeactivatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account deactivated'**
  String get verificationDeactivatedTitle;

  /// No description provided for @verificationDeactivatedBody.
  ///
  /// In en, this message translates to:
  /// **'Your provider account has been deactivated. Contact support if you would like to reactivate it.'**
  String get verificationDeactivatedBody;

  /// No description provided for @verificationVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verificationVerifiedTitle;

  /// No description provided for @verificationVerifiedBody.
  ///
  /// In en, this message translates to:
  /// **'Your account is verified.'**
  String get verificationVerifiedBody;

  /// No description provided for @credentialsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your credentials'**
  String get credentialsTitle;

  /// No description provided for @credentialsProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} steps done'**
  String credentialsProgress(int done, int total);

  /// No description provided for @credentialsDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get credentialsDocuments;

  /// No description provided for @credentialsRegistrationNumber.
  ///
  /// In en, this message translates to:
  /// **'Council registration number'**
  String get credentialsRegistrationNumber;

  /// No description provided for @credentialsRegistrationHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. KMC-41902'**
  String get credentialsRegistrationHint;

  /// No description provided for @credentialsMfa.
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication'**
  String get credentialsMfa;

  /// No description provided for @credentialsMfaBody.
  ///
  /// In en, this message translates to:
  /// **'Required before you can see patients. Your account can read medical records, so it has to be hard to take over.'**
  String get credentialsMfaBody;

  /// No description provided for @credentialsSetUpMfa.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get credentialsSetUpMfa;

  /// No description provided for @credentialsVerifyIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verify with DigiLocker'**
  String get credentialsVerifyIdentity;

  /// No description provided for @credentialsSubmitForReview.
  ///
  /// In en, this message translates to:
  /// **'Submit for review'**
  String get credentialsSubmitForReview;

  /// No description provided for @credentialsSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted. We will be in touch within 2–3 working days.'**
  String get credentialsSubmitted;

  /// No description provided for @mfaTitle.
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication'**
  String get mfaTitle;

  /// No description provided for @mfaStep1.
  ///
  /// In en, this message translates to:
  /// **'Scan this with your authenticator app'**
  String get mfaStep1;

  /// No description provided for @mfaCantScan.
  ///
  /// In en, this message translates to:
  /// **'Cannot scan? Enter this key instead'**
  String get mfaCantScan;

  /// No description provided for @mfaStep2.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get mfaStep2;

  /// No description provided for @mfaCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get mfaCodeLabel;

  /// No description provided for @mfaConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get mfaConfirm;

  /// No description provided for @mfaRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Save your recovery codes'**
  String get mfaRecoveryTitle;

  /// No description provided for @mfaRecoveryBody.
  ///
  /// In en, this message translates to:
  /// **'Each code works once. Keep them somewhere safe — they are the only way back in if you lose your phone, and we cannot show them again.'**
  String get mfaRecoveryBody;

  /// No description provided for @mfaRecoveryCopied.
  ///
  /// In en, this message translates to:
  /// **'Recovery codes copied.'**
  String get mfaRecoveryCopied;

  /// No description provided for @mfaSavedThem.
  ///
  /// In en, this message translates to:
  /// **'I have saved them'**
  String get mfaSavedThem;

  /// No description provided for @prescribeTitle.
  ///
  /// In en, this message translates to:
  /// **'Write a prescription'**
  String get prescribeTitle;

  /// No description provided for @prescribeSearchDrug.
  ///
  /// In en, this message translates to:
  /// **'Search for a medicine'**
  String get prescribeSearchDrug;

  /// No description provided for @prescribeStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get prescribeStrength;

  /// No description provided for @prescribeFrequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get prescribeFrequency;

  /// No description provided for @prescribeFrequencyHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1-0-1'**
  String get prescribeFrequencyHint;

  /// No description provided for @prescribeDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration (days)'**
  String get prescribeDuration;

  /// No description provided for @prescribeInstructions.
  ///
  /// In en, this message translates to:
  /// **'Instructions'**
  String get prescribeInstructions;

  /// No description provided for @prescribeAdd.
  ///
  /// In en, this message translates to:
  /// **'Add medicine'**
  String get prescribeAdd;

  /// No description provided for @prescribeNoItems.
  ///
  /// In en, this message translates to:
  /// **'No medicines added yet'**
  String get prescribeNoItems;

  /// No description provided for @prescribeDiagnosis.
  ///
  /// In en, this message translates to:
  /// **'Diagnosis'**
  String get prescribeDiagnosis;

  /// No description provided for @prescribeAdvice.
  ///
  /// In en, this message translates to:
  /// **'Advice'**
  String get prescribeAdvice;

  /// No description provided for @prescribeIssue.
  ///
  /// In en, this message translates to:
  /// **'Issue prescription'**
  String get prescribeIssue;

  /// No description provided for @prescribeIssued.
  ///
  /// In en, this message translates to:
  /// **'Prescription issued.'**
  String get prescribeIssued;

  /// No description provided for @prescribeFollowUpOnly.
  ///
  /// In en, this message translates to:
  /// **'Follow-up only'**
  String get prescribeFollowUpOnly;

  /// No description provided for @prescribeNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Not allowed remotely'**
  String get prescribeNotAllowed;

  /// No description provided for @prescribeOtc.
  ///
  /// In en, this message translates to:
  /// **'Over the counter'**
  String get prescribeOtc;

  /// No description provided for @sharingHeading.
  ///
  /// In en, this message translates to:
  /// **'Record sharing'**
  String get sharingHeading;

  /// No description provided for @sharingCurrentlyShared.
  ///
  /// In en, this message translates to:
  /// **'Currently shared'**
  String get sharingCurrentlyShared;

  /// No description provided for @sharingRequestsWaiting.
  ///
  /// In en, this message translates to:
  /// **'Requests waiting for you'**
  String get sharingRequestsWaiting;

  /// No description provided for @sharingNothingToShow.
  ///
  /// In en, this message translates to:
  /// **'Nothing to show yet'**
  String get sharingNothingToShow;

  /// No description provided for @sharingAccessEnded.
  ///
  /// In en, this message translates to:
  /// **'Access ended'**
  String get sharingAccessEnded;

  /// No description provided for @sharingEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get sharingEnded;

  /// No description provided for @sharingKeepSharing.
  ///
  /// In en, this message translates to:
  /// **'Keep sharing'**
  String get sharingKeepSharing;

  /// No description provided for @sharingStopSharingQuestion.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing?'**
  String get sharingStopSharingQuestion;

  /// No description provided for @sharingHowLong.
  ///
  /// In en, this message translates to:
  /// **'How long should access last?'**
  String get sharingHowLong;

  /// No description provided for @sharingShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get sharingShare;

  /// No description provided for @appointmentReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get appointmentReference;

  /// No description provided for @appointmentWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get appointmentWhen;

  /// No description provided for @queueTitle.
  ///
  /// In en, this message translates to:
  /// **'Your place in the queue'**
  String get queueTitle;

  /// No description provided for @queueNext.
  ///
  /// In en, this message translates to:
  /// **'You\'re next'**
  String get queueNext;

  /// No description provided for @queueAhead.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 patient ahead of you} other{{count} patients ahead of you}}'**
  String queueAhead(int count);

  /// No description provided for @queueInProgress.
  ///
  /// In en, this message translates to:
  /// **'The doctor is with a patient'**
  String get queueInProgress;

  /// No description provided for @queueEstimate.
  ///
  /// In en, this message translates to:
  /// **'About {minutes} min'**
  String queueEstimate(int minutes);

  /// No description provided for @queueNotCheckedIn.
  ///
  /// In en, this message translates to:
  /// **'Check in at the clinic to see your place in the queue'**
  String get queueNotCheckedIn;

  /// No description provided for @queueCheckedIn.
  ///
  /// In en, this message translates to:
  /// **'Checked in'**
  String get queueCheckedIn;

  /// No description provided for @appointmentType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get appointmentType;

  /// No description provided for @appointmentTellUsWhy.
  ///
  /// In en, this message translates to:
  /// **'Tell us why'**
  String get appointmentTellUsWhy;

  /// No description provided for @appointmentCancellationReason.
  ///
  /// In en, this message translates to:
  /// **'Cancellation reason'**
  String get appointmentCancellationReason;

  /// No description provided for @appointmentCancelIt.
  ///
  /// In en, this message translates to:
  /// **'Cancel it'**
  String get appointmentCancelIt;

  /// No description provided for @searchAvailableToday.
  ///
  /// In en, this message translates to:
  /// **'Available today'**
  String get searchAvailableToday;

  /// No description provided for @searchAvailableTodayBody.
  ///
  /// In en, this message translates to:
  /// **'Only doctors with a free slot today'**
  String get searchAvailableTodayBody;

  /// No description provided for @searchDoctorHint.
  ///
  /// In en, this message translates to:
  /// **'Doctor, specialty or hospital'**
  String get searchDoctorHint;

  /// No description provided for @searchClearFiltersShort.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get searchClearFiltersShort;

  /// No description provided for @searchNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No doctors match your search'**
  String get searchNoMatch;

  /// No description provided for @doctorTitle.
  ///
  /// In en, this message translates to:
  /// **'Doctor'**
  String get doctorTitle;

  /// No description provided for @doctorConsultationFees.
  ///
  /// In en, this message translates to:
  /// **'Consultation fees'**
  String get doctorConsultationFees;

  /// No description provided for @doctorPractisesAt.
  ///
  /// In en, this message translates to:
  /// **'Practises at'**
  String get doctorPractisesAt;

  /// No description provided for @doctorMedicalRegistration.
  ///
  /// In en, this message translates to:
  /// **'Medical registration'**
  String get doctorMedicalRegistration;

  /// No description provided for @bookingAvailableTimes.
  ///
  /// In en, this message translates to:
  /// **'Available times'**
  String get bookingAvailableTimes;

  /// No description provided for @bookingSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select a date'**
  String get bookingSelectDate;

  /// No description provided for @bookingNoSlotsOnDay.
  ///
  /// In en, this message translates to:
  /// **'No slots on this day'**
  String get bookingNoSlotsOnDay;

  /// No description provided for @bookingReasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason for visit (optional)'**
  String get bookingReasonOptional;

  /// No description provided for @bookingSymptomsHint.
  ///
  /// In en, this message translates to:
  /// **'Briefly describe your symptoms or concern'**
  String get bookingSymptomsHint;

  /// No description provided for @consultAgreeContinue.
  ///
  /// In en, this message translates to:
  /// **'Agree and continue'**
  String get consultAgreeContinue;

  /// No description provided for @consultEndQuestion.
  ///
  /// In en, this message translates to:
  /// **'End consultation?'**
  String get consultEndQuestion;

  /// No description provided for @consultEitherCanEnd.
  ///
  /// In en, this message translates to:
  /// **'Either of you can end the consultation.'**
  String get consultEitherCanEnd;

  /// No description provided for @consultStay.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get consultStay;

  /// No description provided for @consultSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get consultSwitch;

  /// No description provided for @consultNoMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get consultNoMessages;

  /// No description provided for @consultKeptWithRecord.
  ///
  /// In en, this message translates to:
  /// **'Kept as part of your medical record'**
  String get consultKeptWithRecord;

  /// No description provided for @privacyThisCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone'**
  String get privacyThisCannotBeUndone;

  /// No description provided for @privacyUpdateDetails.
  ///
  /// In en, this message translates to:
  /// **'Update your profile details'**
  String get privacyUpdateDetails;

  /// No description provided for @credentialsStepDocuments.
  ///
  /// In en, this message translates to:
  /// **'1. Documents'**
  String get credentialsStepDocuments;

  /// No description provided for @credentialsStepRegistration.
  ///
  /// In en, this message translates to:
  /// **'2. Registration number'**
  String get credentialsStepRegistration;

  /// No description provided for @credentialsStepMfa.
  ///
  /// In en, this message translates to:
  /// **'3. Two-factor authentication'**
  String get credentialsStepMfa;

  /// No description provided for @credentialsAuthenticatorApp.
  ///
  /// In en, this message translates to:
  /// **'Authenticator app'**
  String get credentialsAuthenticatorApp;

  /// No description provided for @credentialsPaperCertificate.
  ///
  /// In en, this message translates to:
  /// **'Best for a paper certificate'**
  String get credentialsPaperCertificate;

  /// No description provided for @credentialsChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose a file'**
  String get credentialsChooseFile;

  /// No description provided for @credentialsCouncilRegistration.
  ///
  /// In en, this message translates to:
  /// **'Council registration'**
  String get credentialsCouncilRegistration;

  /// No description provided for @credentialsRegistrationNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Medical registration number'**
  String get credentialsRegistrationNumberLabel;

  /// No description provided for @credentialsFileTypes.
  ///
  /// In en, this message translates to:
  /// **'PDF, JPG, PNG or HEIC'**
  String get credentialsFileTypes;

  /// No description provided for @credentialsGetVerified.
  ///
  /// In en, this message translates to:
  /// **'Get verified'**
  String get credentialsGetVerified;

  /// No description provided for @credentialsSubmittedForReview.
  ///
  /// In en, this message translates to:
  /// **'Submitted for review'**
  String get credentialsSubmittedForReview;

  /// No description provided for @credentialsTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get credentialsTakePhoto;

  /// No description provided for @availabilityMySchedule.
  ///
  /// In en, this message translates to:
  /// **'My schedule'**
  String get availabilityMySchedule;

  /// No description provided for @availabilityAddAvailability.
  ///
  /// In en, this message translates to:
  /// **'Add availability'**
  String get availabilityAddAvailability;

  /// No description provided for @availabilityDaysOff.
  ///
  /// In en, this message translates to:
  /// **'Days off'**
  String get availabilityDaysOff;

  /// No description provided for @availabilityMarkDayOff.
  ///
  /// In en, this message translates to:
  /// **'Mark a day off'**
  String get availabilityMarkDayOff;

  /// No description provided for @availabilityConsultationType.
  ///
  /// In en, this message translates to:
  /// **'Consultation type'**
  String get availabilityConsultationType;

  /// No description provided for @mfaInstallApp.
  ///
  /// In en, this message translates to:
  /// **'1. Install an authenticator app'**
  String get mfaInstallApp;

  /// No description provided for @mfaAddKey.
  ///
  /// In en, this message translates to:
  /// **'2. Add this key'**
  String get mfaAddKey;

  /// No description provided for @mfaEnterCode.
  ///
  /// In en, this message translates to:
  /// **'3. Enter the 6-digit code'**
  String get mfaEnterCode;

  /// No description provided for @mfaCopyKey.
  ///
  /// In en, this message translates to:
  /// **'Copy key'**
  String get mfaCopyKey;

  /// No description provided for @mfaKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Key copied'**
  String get mfaKeyCopied;

  /// No description provided for @mfaClipboardCleared.
  ///
  /// In en, this message translates to:
  /// **'Copied. The clipboard clears itself in a minute.'**
  String get mfaClipboardCleared;

  /// No description provided for @mfaCopyAllCodes.
  ///
  /// In en, this message translates to:
  /// **'Copy all codes'**
  String get mfaCopyAllCodes;

  /// No description provided for @mfaVerifyEnable.
  ///
  /// In en, this message translates to:
  /// **'Verify and enable'**
  String get mfaVerifyEnable;

  /// No description provided for @mfaIsOn.
  ///
  /// In en, this message translates to:
  /// **'Two-factor is on'**
  String get mfaIsOn;

  /// No description provided for @prescribeWriteTitle.
  ///
  /// In en, this message translates to:
  /// **'Write prescription'**
  String get prescribeWriteTitle;

  /// No description provided for @prescribeSearchMedicines.
  ///
  /// In en, this message translates to:
  /// **'Search medicines'**
  String get prescribeSearchMedicines;

  /// No description provided for @prescribeAddToPrescription.
  ///
  /// In en, this message translates to:
  /// **'Add to prescription'**
  String get prescribeAddToPrescription;

  /// No description provided for @prescribeChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get prescribeChange;

  /// No description provided for @prescribeAdviceToPatient.
  ///
  /// In en, this message translates to:
  /// **'Advice to the patient'**
  String get prescribeAdviceToPatient;

  /// No description provided for @prescribeDurationDays.
  ///
  /// In en, this message translates to:
  /// **'Duration (days)'**
  String get prescribeDurationDays;

  /// No description provided for @prescribeFollowUpConsultation.
  ///
  /// In en, this message translates to:
  /// **'Follow-up consultation'**
  String get prescribeFollowUpConsultation;

  /// No description provided for @prescribeInstructionsOptional.
  ///
  /// In en, this message translates to:
  /// **'Instructions (optional)'**
  String get prescribeInstructionsOptional;

  /// No description provided for @prescribeMedicines.
  ///
  /// In en, this message translates to:
  /// **'Medicines'**
  String get prescribeMedicines;

  /// No description provided for @prescribeNoMedicines.
  ///
  /// In en, this message translates to:
  /// **'No medicines added yet'**
  String get prescribeNoMedicines;

  /// No description provided for @prescribeIssued2.
  ///
  /// In en, this message translates to:
  /// **'Prescription issued'**
  String get prescribeIssued2;

  /// No description provided for @prescriptionsNoneYet.
  ///
  /// In en, this message translates to:
  /// **'No prescriptions yet'**
  String get prescriptionsNoneYet;

  /// No description provided for @prescriptionIssued.
  ///
  /// In en, this message translates to:
  /// **'Issued'**
  String get prescriptionIssued;

  /// No description provided for @prescriptionPatient.
  ///
  /// In en, this message translates to:
  /// **'Patient'**
  String get prescriptionPatient;

  /// No description provided for @prescriptionPharmacyVerification.
  ///
  /// In en, this message translates to:
  /// **'Pharmacy verification'**
  String get prescriptionPharmacyVerification;

  /// No description provided for @supportHelpAndSupport.
  ///
  /// In en, this message translates to:
  /// **'Help and support'**
  String get supportHelpAndSupport;

  /// No description provided for @supportHowCanWeHelp.
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get supportHowCanWeHelp;

  /// No description provided for @supportNoRequests.
  ///
  /// In en, this message translates to:
  /// **'No support requests'**
  String get supportNoRequests;

  /// No description provided for @supportRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent. We will be in touch.'**
  String get supportRequestSent;

  /// No description provided for @supportSendRequest.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get supportSendRequest;

  /// No description provided for @supportTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get supportTitleLabel;

  /// No description provided for @supportWhatHappened.
  ///
  /// In en, this message translates to:
  /// **'What happened?'**
  String get supportWhatHappened;

  /// No description provided for @providerNothingToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled today'**
  String get providerNothingToday;

  /// No description provided for @providerPrescribe.
  ///
  /// In en, this message translates to:
  /// **'Prescribe'**
  String get providerPrescribe;

  /// No description provided for @providerStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get providerStart;

  /// No description provided for @homeQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get homeQuickActions;

  /// No description provided for @medsTitle.
  ///
  /// In en, this message translates to:
  /// **'Medicines'**
  String get medsTitle;

  /// No description provided for @medsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get medsToday;

  /// No description provided for @medsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to take'**
  String get medsEmpty;

  /// No description provided for @medsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Medicines prescribed at your consultations appear here, with what to take and when.'**
  String get medsEmptyBody;

  /// No description provided for @medsProgress.
  ///
  /// In en, this message translates to:
  /// **'{taken} of {due} taken'**
  String medsProgress(int taken, int due);

  /// No description provided for @medsAllDone.
  ///
  /// In en, this message translates to:
  /// **'All done for today'**
  String get medsAllDone;

  /// No description provided for @medsSlotMorning.
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get medsSlotMorning;

  /// No description provided for @medsSlotAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Afternoon'**
  String get medsSlotAfternoon;

  /// No description provided for @medsSlotEvening.
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get medsSlotEvening;

  /// No description provided for @medsSlotNight.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get medsSlotNight;

  /// No description provided for @medsMarkTaken.
  ///
  /// In en, this message translates to:
  /// **'Taken'**
  String get medsMarkTaken;

  /// No description provided for @medsMarkSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get medsMarkSkipped;

  /// No description provided for @medsSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get medsSkip;

  /// No description provided for @medsUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get medsUndo;

  /// No description provided for @medsAsNeeded.
  ///
  /// In en, this message translates to:
  /// **'When you need it'**
  String get medsAsNeeded;

  /// No description provided for @medsUnscheduled.
  ///
  /// In en, this message translates to:
  /// **'Follow your doctor\'s instructions'**
  String get medsUnscheduled;

  /// No description provided for @medsUnscheduledBody.
  ///
  /// In en, this message translates to:
  /// **'No reminders are set for these. The app only schedules a dose when the instruction says exactly how many a day.'**
  String get medsUnscheduledBody;

  /// No description provided for @medsFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get medsFinished;

  /// No description provided for @medsFinishedOn.
  ///
  /// In en, this message translates to:
  /// **'Course ended {date}'**
  String medsFinishedOn(String date);

  /// No description provided for @medsDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Last day} =1{1 day left} other{{days} days left}}'**
  String medsDaysLeft(int days);

  /// No description provided for @medsPrescribedBy.
  ///
  /// In en, this message translates to:
  /// **'Prescribed by {name}'**
  String medsPrescribedBy(String name);

  /// No description provided for @medsAdherence.
  ///
  /// In en, this message translates to:
  /// **'{taken} of {due} doses ticked off'**
  String medsAdherence(int taken, int due);

  /// No description provided for @medsSelfReported.
  ///
  /// In en, this message translates to:
  /// **'This is what you have ticked off yourself. It is not a medical record and your doctor does not see it.'**
  String get medsSelfReported;

  /// No description provided for @medsTimesAreOurs.
  ///
  /// In en, this message translates to:
  /// **'Times are the app\'s suggestion. Your doctor set how many doses a day, not the hour.'**
  String get medsTimesAreOurs;

  /// No description provided for @medsPreviousDay.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get medsPreviousDay;

  /// No description provided for @medsNextDay.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get medsNextDay;

  /// No description provided for @homeQuickMedicines.
  ///
  /// In en, this message translates to:
  /// **'My medicines'**
  String get homeQuickMedicines;

  /// No description provided for @templatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved sets'**
  String get templatesTitle;

  /// No description provided for @templatesSave.
  ///
  /// In en, this message translates to:
  /// **'Save as set'**
  String get templatesSave;

  /// No description provided for @templatesSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get templatesSaved;

  /// No description provided for @templatesName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get templatesName;

  /// No description provided for @templatesNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Chest infection, adults'**
  String get templatesNameHint;

  /// No description provided for @templatesNone.
  ///
  /// In en, this message translates to:
  /// **'No saved sets yet'**
  String get templatesNone;

  /// No description provided for @templatesNoneBody.
  ///
  /// In en, this message translates to:
  /// **'Save the medicines you prescribe often, then add them in one tap next time.'**
  String get templatesNoneBody;

  /// No description provided for @templatesDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete set'**
  String get templatesDelete;

  /// No description provided for @templatesBlockedHere.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 medicine cannot be prescribed on this consultation} other{{count} medicines cannot be prescribed on this consultation}}'**
  String templatesBlockedHere(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
