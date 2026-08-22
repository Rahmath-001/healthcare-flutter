// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MiDoctor';

  @override
  String get navHome => 'Home';

  @override
  String get navAppointments => 'Appointments';

  @override
  String get navRecords => 'Records';

  @override
  String get navProfile => 'Profile';

  @override
  String get navToday => 'Today';

  @override
  String get navSchedule => 'Schedule';

  @override
  String get navPatients => 'Patients';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionSignOut => 'Sign out';

  @override
  String get actionBook => 'Book appointment';

  @override
  String get actionJoin => 'Join consultation';

  @override
  String get actionBack => 'Back';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionSend => 'Send';

  @override
  String get actionDone => 'Done';

  @override
  String get actionNext => 'Next';

  @override
  String get actionClose => 'Close';

  @override
  String get actionUpload => 'Upload';

  @override
  String get actionSubmit => 'Submit';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionSkip => 'Skip';

  @override
  String get actionNotNow => 'Not now';

  @override
  String get offline => 'You are offline';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsSettings => 'Notification settings';

  @override
  String get notificationsMarkAllRead => 'Mark all read';

  @override
  String get notificationsEmpty => 'Nothing yet';

  @override
  String get notificationsEmptyBody =>
      'Appointment reminders and updates will appear here.';

  @override
  String get notificationsWhatToSend => 'What to send';

  @override
  String get notificationsAlwaysOn => 'Always sent — you need to know';

  @override
  String get notificationsIgnoresQuietHours => 'Sent even during quiet hours';

  @override
  String get notificationsQuietHours => 'Quiet hours';

  @override
  String get notificationsQuietHoursBody =>
      'Nothing will be sent during these hours, except appointment changes and account alerts.';

  @override
  String get notificationsQuietFrom => 'From';

  @override
  String get notificationsQuietTo => 'Until';

  @override
  String get notificationKindReminder => 'Appointment reminders';

  @override
  String get notificationKindChanged => 'Appointment moved or cancelled';

  @override
  String get notificationKindPrescription => 'New prescriptions';

  @override
  String get notificationKindConsent => 'Requests to see your records';

  @override
  String get notificationKindRecord => 'Uploads finished checking';

  @override
  String get notificationKindRating => 'Rate a consultation';

  @override
  String get notificationKindAccount => 'Account and verification';

  @override
  String get notificationsEnable => 'Turn on notifications';

  @override
  String get notificationsEnabled => 'Notifications are on';

  @override
  String get notificationsDenied =>
      'Notifications are off. You can turn them on in your phone settings.';

  @override
  String get notificationsOnboardingBody =>
      'We will remind you before a consultation and tell you when a prescription is ready. No health details ever appear on your lock screen.';

  @override
  String get sessionTimedOut =>
      'Signed out after 15 minutes of inactivity, to keep your health information private.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorNetwork => 'No internet connection.';

  @override
  String get optional => 'Optional';

  @override
  String get authWelcomeBack => 'Welcome back';

  @override
  String get authSignInToContinue => 'Sign in to continue';

  @override
  String get authContinueWithPhone => 'Continue with phone';

  @override
  String get authContinueWithGoogle => 'Continue with Google';

  @override
  String get authContinueWithApple => 'Sign in with Apple';

  @override
  String get authNewHere => 'New here? ';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authAlreadyHaveAccount => 'Already have an account? ';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authSampleData => 'Explore with sample data';

  @override
  String get authSampleDataHint =>
      'Signs in as Priya Sharma, a patient with appointments, records and prescriptions already in place.';

  @override
  String get authExploreAsDoctor => 'Explore as an approved doctor';

  @override
  String get authExploreAsPendingDoctor =>
      'Explore as a doctor awaiting verification';

  @override
  String get authOr => 'or';

  @override
  String get authGoogleFailed => 'Google sign-in failed. Please try again.';

  @override
  String get authAppleFailed => 'Sign in with Apple failed. Please try again.';

  @override
  String get authRoleTitle => 'How will you use MiDoctor?';

  @override
  String get authRoleSubtitle =>
      'You can only change this by contacting support, so choose carefully.';

  @override
  String get authRolePatient => 'I am a patient';

  @override
  String get authRolePatientBody =>
      'Book appointments, keep your records, and consult a doctor.';

  @override
  String get authRoleProvider => 'I am a doctor';

  @override
  String get authRoleProviderBody =>
      'See patients, write prescriptions, and manage your hours. Your credentials are verified before you can practise.';

  @override
  String get phoneTitle => 'Your phone number';

  @override
  String get phoneIndiaOnly =>
      'India only · Airtel, Jio or Vi · internet calling numbers are not accepted';

  @override
  String get phoneSendCode => 'Send code';

  @override
  String get phoneSubtitle =>
      'We will send a one-time code to confirm it is you.';

  @override
  String get phoneLabel => 'Mobile number';

  @override
  String get phoneInvalid => 'Enter a valid 10-digit Indian mobile number.';

  @override
  String get phoneCheckingCarrier => 'Checking your number…';

  @override
  String get phoneVoipRejected =>
      'That looks like an internet calling number. Please use a mobile number.';

  @override
  String get otpTitle => 'Enter the code';

  @override
  String otpSentTo(String phone) {
    return 'We sent a 6-digit code to $phone.';
  }

  @override
  String get otpResend => 'Resend code';

  @override
  String otpResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get otpVerify => 'Verify';

  @override
  String get otpInvalid => 'That code is not right. Check it and try again.';

  @override
  String get onboardingWelcomeTitle => 'Welcome to MiDoctor';

  @override
  String get onboardingWelcomeBody =>
      'Consult a doctor, keep your records, and stay in control of who sees them.';

  @override
  String get onboardingHealthTitle => 'A little about your health';

  @override
  String get onboardingHealthBody => 'Help us personalise your experience.';

  @override
  String get onboardingDateOfBirth => 'Date of birth';

  @override
  String get onboardingDateOfBirthHelp =>
      'Used to check medicine doses are safe';

  @override
  String get onboardingBloodGroup => 'Blood group';

  @override
  String get onboardingNotSet => 'Not set';

  @override
  String get onboardingNotificationsTitle => 'Stay in the loop';

  @override
  String get onboardingNotificationsBody =>
      'Reminders for your appointments, so you never miss a consultation.';

  @override
  String get onboardingEnableNotifications => 'Enable notifications';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String homeGreeting(String name) {
    return 'Hello, $name';
  }

  @override
  String get homeGoodMorning => 'Good morning';

  @override
  String get homeGoodAfternoon => 'Good afternoon';

  @override
  String get homeGoodEvening => 'Good evening';

  @override
  String get homeFindDoctor => 'Find a doctor';

  @override
  String get homeNextAppointment => 'Your next appointment';

  @override
  String get homeNoUpcoming => 'Nothing booked yet';

  @override
  String get homeNoUpcomingBody =>
      'Search for a doctor to book your first consultation.';

  @override
  String get homeQuickRecords => 'My records';

  @override
  String get homeQuickPrescriptions => 'Prescriptions';

  @override
  String get homeQuickSharing => 'Who can see my records';

  @override
  String get homeQuickSupport => 'Get help';

  @override
  String get searchTitle => 'Find a doctor';

  @override
  String get searchHint => 'Name, speciality or hospital';

  @override
  String get searchFilters => 'Filters';

  @override
  String get searchClearFilters => 'Clear all';

  @override
  String get searchSpeciality => 'Speciality';

  @override
  String get searchCity => 'City';

  @override
  String get searchMaxFee => 'Maximum fee';

  @override
  String searchUpToFee(String fee) {
    return 'Up to $fee';
  }

  @override
  String get searchMinRating => 'Minimum rating';

  @override
  String get searchMode => 'Consultation type';

  @override
  String get searchApply => 'Show results';

  @override
  String get searchNoResults => 'No doctors match';

  @override
  String get searchNoResultsBody =>
      'Try removing a filter or searching for something broader.';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count doctors',
      one: '1 doctor',
      zero: 'No doctors',
    );
    return '$_temp0';
  }

  @override
  String doctorExperience(int years) {
    String _temp0 = intl.Intl.pluralLogic(
      years,
      locale: localeName,
      other: '$years years experience',
      one: '1 year experience',
    );
    return '$_temp0';
  }

  @override
  String doctorRegistration(String number) {
    return 'Registration $number';
  }

  @override
  String get doctorAbout => 'About';

  @override
  String get doctorLanguages => 'Speaks';

  @override
  String get doctorFees => 'Fees';

  @override
  String get doctorFeeVideo => 'Video consultation';

  @override
  String get doctorFeeInPerson => 'In person';

  @override
  String doctorRatingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ratings',
      one: '1 rating',
      zero: 'No ratings yet',
    );
    return '$_temp0';
  }

  @override
  String get bookingTitle => 'Book an appointment';

  @override
  String get bookingChooseDate => 'Choose a date';

  @override
  String get bookingChooseTime => 'Choose a time';

  @override
  String get bookingNoSlots => 'No times available';

  @override
  String get bookingNoSlotsBody =>
      'This doctor has no free slots that day. Try another date.';

  @override
  String get bookingReason => 'Reason for visit';

  @override
  String get bookingReasonHint => 'e.g. Fever for three days';

  @override
  String bookingHoldExpiresIn(String countdown) {
    return 'Slot held for $countdown';
  }

  @override
  String get bookingHoldExpired =>
      'That slot was released. Please pick another time.';

  @override
  String get bookingNoPaymentNow =>
      'No payment is taken now. Pay at the clinic or when you see the doctor.';

  @override
  String get bookingConfirm => 'Confirm booking';

  @override
  String get bookingConfirmedTitle => 'You are booked';

  @override
  String get bookingConfirmedBody => 'We have sent the details to your phone.';

  @override
  String bookingReference(String code) {
    return 'Reference $code';
  }

  @override
  String get bookingShareRecords => 'Share your records with this doctor';

  @override
  String get bookingShareRecordsBody =>
      'They can only see what you choose, and only until the date you set.';

  @override
  String get bookingViewAppointment => 'View appointment';

  @override
  String get appointmentsUpcoming => 'Upcoming';

  @override
  String get appointmentsCancelledTab => 'Cancelled';

  @override
  String get appointmentsNoUpcoming => 'No upcoming appointments';

  @override
  String get appointmentsNoUpcomingBody =>
      'Book a consultation and it will show up here.';

  @override
  String get appointmentsNoPast => 'No past appointments';

  @override
  String get appointmentsNoCancelled => 'No cancelled appointments';

  @override
  String get actionBookShort => 'Book';

  @override
  String get appointmentsPast => 'Past';

  @override
  String get appointmentsNone => 'No appointments';

  @override
  String get appointmentsNoneBody =>
      'When you book a consultation it will appear here.';

  @override
  String get appointmentDetailTitle => 'Appointment';

  @override
  String get appointmentReasonForVisit => 'Reason for visit';

  @override
  String get appointmentNoReasonGiven => 'No reason given';

  @override
  String get appointmentFee => 'Fee';

  @override
  String get appointmentCancelTitle => 'Cancel this appointment?';

  @override
  String get appointmentCancelBody =>
      'Let the doctor know why, so the slot can be offered to someone else.';

  @override
  String get appointmentCancelReason => 'Reason';

  @override
  String get appointmentCancelConfirm => 'Cancel appointment';

  @override
  String get rescheduleTitle => 'Move this appointment';

  @override
  String rescheduleCurrent(String when) {
    return 'Currently $when';
  }

  @override
  String get rescheduleConfirm => 'Confirm new time';

  @override
  String get rescheduleAction => 'Reschedule';

  @override
  String get rescheduleHoldNote =>
      'Your current time is only released once the new one is confirmed.';

  @override
  String get rescheduleNoSlots => 'No free times that day';

  @override
  String get rescheduleNoSlotsBody => 'Try another date.';

  @override
  String rescheduleCurrentSlot(String time) {
    return '$time · now';
  }

  @override
  String rescheduleDone(String when) {
    return 'Appointment moved to $when.';
  }

  @override
  String get appointmentKeepIt => 'Keep it';

  @override
  String get appointmentCancelled => 'Appointment cancelled.';

  @override
  String appointmentFreeCancellation(String when) {
    return 'Free to cancel until $when';
  }

  @override
  String get appointmentRate => 'Rate this consultation';

  @override
  String get appointmentViewPrescription => 'View prescription';

  @override
  String get recordsTitle => 'Health records';

  @override
  String get recordsFilterAll => 'All';

  @override
  String get recordsFilterFromDoctors => 'From doctors';

  @override
  String get recordsFilterMine => 'Uploaded by me';

  @override
  String get recordsEmpty => 'No records here yet';

  @override
  String get recordsEmptyBody => 'Upload a report or scan to keep it with you.';

  @override
  String get recordsUploadOne => 'Upload a record';

  @override
  String get recordsWhoCanSee => 'Who can see my records';

  @override
  String get recordsChecking => 'Checking file, available shortly';

  @override
  String get recordsCheckingShort => 'Checking';

  @override
  String get recordScanFailedShort => 'Check failed';

  @override
  String get recordDetailTitle => 'Record';

  @override
  String get recordType => 'Type';

  @override
  String get recordAddedBy => 'Added by';

  @override
  String get recordAddedByYou => 'You';

  @override
  String get recordAddedByDoctor => 'A doctor';

  @override
  String get recordTakenOn => 'Taken on';

  @override
  String get recordUploaded => 'Uploaded';

  @override
  String get recordSize => 'Size';

  @override
  String get recordPages => 'Pages';

  @override
  String get recordYourNotes => 'Your notes';

  @override
  String get recordOpenFile => 'Open file';

  @override
  String get recordDeleteTitle => 'Delete this record?';

  @override
  String recordDeleteBody(String title) {
    return '\"$title\" will be removed from your records, and any doctor you have shared it with will lose access to it.\n\nThis cannot be undone.';
  }

  @override
  String get recordKeepIt => 'Keep it';

  @override
  String get recordScanPending =>
      'This file is still being checked for viruses. It will open once the check finishes.';

  @override
  String get recordScanInfected =>
      'This file failed a virus check and cannot be opened or shared.';

  @override
  String get recordScanFailed =>
      'We could not check this file. Try uploading it again.';

  @override
  String get recordCannotDisplay => 'Cannot display this file';

  @override
  String get recordCannotDisplayBody =>
      'The file downloaded, but this device cannot render that format.';

  @override
  String get uploadTitle => 'Upload a record';

  @override
  String get uploadTakePhoto => 'Take a photo';

  @override
  String get uploadFromGallery => 'Choose from gallery';

  @override
  String get uploadPickDocument => 'Pick a document';

  @override
  String get uploadRecordTitle => 'Title';

  @override
  String get uploadRecordTitleHint => 'e.g. Complete Blood Count';

  @override
  String get uploadRecordType => 'Type';

  @override
  String get uploadDateOnReport => 'Date on the report';

  @override
  String get uploadNotes => 'Notes (optional)';

  @override
  String get uploadPrivacyNote =>
      'Your records are private to you. A doctor can only see one if you share it, and you can revoke that at any time. Files are checked for viruses before they become available.';

  @override
  String get uploadDone => 'Uploaded. It will be available once checked.';

  @override
  String get sharingTitle => 'Who can see my records';

  @override
  String get sharingTabAccess => 'Access';

  @override
  String get sharingTabRequests => 'Requests';

  @override
  String get sharingTabLog => 'Activity';

  @override
  String get sharingNobodyHasAccess => 'Nobody can see your records';

  @override
  String get sharingNobodyHasAccessBody =>
      'A doctor can only see a record if you share it with them.';

  @override
  String get sharingStopSharing => 'Stop sharing';

  @override
  String sharingEndsIn(String duration) {
    return 'Ends in $duration';
  }

  @override
  String sharingRevokeConfirm(String name) {
    return 'Stop sharing with $name? They will lose access immediately.';
  }

  @override
  String get sharingRevoked => 'Access revoked.';

  @override
  String get sharingNoRequests => 'No requests';

  @override
  String get sharingNoRequestsBody =>
      'When a doctor asks to see your records, it will appear here.';

  @override
  String get sharingApprove => 'Allow';

  @override
  String get sharingDeny => 'Decline';

  @override
  String get sharingNoActivity => 'No activity yet';

  @override
  String get sharingNoActivityBody =>
      'Every time someone opens one of your records, it is recorded here.';

  @override
  String get sharingExpiresLabel => 'Access ends';

  @override
  String get sharingPurpose => 'Purpose';

  @override
  String get sharingGranted => 'Access granted.';

  @override
  String get prescriptionsTitle => 'Prescriptions';

  @override
  String get prescriptionsEmpty => 'No prescriptions';

  @override
  String get prescriptionsEmptyBody =>
      'A prescription written during a consultation will appear here.';

  @override
  String get prescriptionTitle => 'Prescription';

  @override
  String get prescriptionShare => 'Share or save as PDF';

  @override
  String get prescriptionPrint => 'Print';

  @override
  String get prescriptionDiagnosis => 'Diagnosis';

  @override
  String get prescriptionAdvice => 'Advice';

  @override
  String get prescriptionMedicines => 'Medicines';

  @override
  String prescriptionFollowUp(String date) {
    return 'Follow up on $date';
  }

  @override
  String get prescriptionVerificationCode => 'Verification code';

  @override
  String get prescriptionVerificationBody =>
      'A pharmacy can use this to confirm the prescription is genuine.';

  @override
  String prescriptionRetainedUntil(String date) {
    return 'Kept until $date';
  }

  @override
  String get consultationTitle => 'Consultation';

  @override
  String get consentTelemedicineTitle => 'Before you begin';

  @override
  String get consentNotRecorded =>
      'This consultation is not recorded. No video or audio is saved.';

  @override
  String get consentRecordKept =>
      'Chat messages, the doctor\'s notes and any prescription are kept as part of your medical record.';

  @override
  String get consentRestrictedMedicines =>
      'Some medicines cannot be prescribed remotely. Your doctor may ask you to visit in person.';

  @override
  String get consentNotEmergency =>
      'Telemedicine is not for emergencies. If this is urgent, go to the nearest hospital.';

  @override
  String get consentAgree =>
      'I consent to this teleconsultation and confirm the information I give will be accurate.';

  @override
  String get consultationWaiting => 'Waiting for the doctor to join…';

  @override
  String get consultationConnecting => 'Connecting…';

  @override
  String get consultationEnd => 'End';

  @override
  String get consultationSwitchToAudio => 'Switch to audio';

  @override
  String get consultationPoorConnection =>
      'Your connection is poor. Switching to audio may help.';

  @override
  String get consultationChat => 'Chat';

  @override
  String get consultationChatHint => 'Type a message';

  @override
  String get consultationEnded => 'Consultation ended';

  @override
  String get consultationNotRecordedBadge => 'Not recorded';

  @override
  String get consultationCameraOff => 'Camera is off';

  @override
  String get consultationJoinFromPhone =>
      'Video consultations are only available in the MiDoctor app. Please join from your phone.';

  @override
  String get rateTitle => 'Rate your consultation';

  @override
  String rateWith(String name) {
    return 'How was your consultation with $name?';
  }

  @override
  String get rateComment => 'Tell others what it was like (optional)';

  @override
  String get rateModerationNote =>
      'Reviews are checked before they are published.';

  @override
  String get rateSubmit => 'Submit rating';

  @override
  String get rateThanks =>
      'Thank you. Your rating will appear once it is reviewed.';

  @override
  String rateEditWindow(String duration) {
    return 'You can change this for $duration';
  }

  @override
  String get supportTitle => 'Get help';

  @override
  String get supportNewTicket => 'New request';

  @override
  String get supportNoTickets => 'No requests yet';

  @override
  String get supportNoTicketsBody =>
      'If something is not working, tell us and we will look into it.';

  @override
  String get supportSubject => 'Subject';

  @override
  String get supportCategory => 'What is this about?';

  @override
  String get supportDescribe => 'Tell us what happened';

  @override
  String get supportDescribeHint =>
      'Please do not include medical details here.';

  @override
  String get supportReplyHint => 'Write a reply';

  @override
  String get supportCreated => 'Sent. We will get back to you.';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileBloodGroup => 'Blood group';

  @override
  String get profileAge => 'Age';

  @override
  String get profileEditProfile => 'Edit profile';

  @override
  String get profileSettings => 'Settings';

  @override
  String get profileHelp => 'Help and support';

  @override
  String get profileNotSet => '—';

  @override
  String get editProfileTitle => 'Edit profile';

  @override
  String get editProfileFullName => 'Full name';

  @override
  String get editProfileNameRequired => 'Please enter your name';

  @override
  String get editProfileDateOfBirth => 'Date of birth';

  @override
  String get editProfileGender => 'Gender';

  @override
  String get editProfileBloodGroup => 'Blood group';

  @override
  String get editProfileAllergies => 'Allergies';

  @override
  String get editProfileAllergiesHint => 'e.g. Penicillin, peanuts';

  @override
  String get editProfileAllergiesHelp => 'Shown to any doctor you consult';

  @override
  String get editProfileConditions => 'Ongoing conditions';

  @override
  String get editProfileConditionsHint => 'e.g. Type 2 diabetes, hypertension';

  @override
  String get editProfileEmergencyContact => 'Emergency contact';

  @override
  String get editProfileContactName => 'Name';

  @override
  String get editProfilePhone => 'Phone number';

  @override
  String get editProfileSaveChanges => 'Save changes';

  @override
  String get editProfileUpdated => 'Profile updated';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsPrivacy => 'Privacy and your rights';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsAbout => 'About';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsSignOutConfirm => 'Sign out of MiDoctor?';

  @override
  String get privacyTitle => 'Privacy and your rights';

  @override
  String get privacyYourRights => 'Your rights';

  @override
  String get privacyRightsBody =>
      'Under India\'s Digital Personal Data Protection Act, you can see what we hold about you, correct it, take a copy elsewhere, and ask us to delete it.';

  @override
  String get privacyDownloadData => 'Download my data';

  @override
  String get privacyDownloadDataBody =>
      'Profile, appointments, records and sharing history';

  @override
  String get privacyCorrect => 'Correct my information';

  @override
  String get privacyCorrectBody => 'Update your profile details';

  @override
  String get privacyRetentionTitle => 'How long we keep things';

  @override
  String get privacyRetentionClinical =>
      'Consultation notes and prescriptions: 3 years, as medical record rules require';

  @override
  String get privacyRetentionConsultations =>
      'Video and audio consultations: never recorded';

  @override
  String get privacyRetentionChat =>
      'Chat messages from a consultation: kept with your medical record';

  @override
  String get privacyRetentionAccessLog =>
      'Record access log: kept so you can always audit who looked at what';

  @override
  String get privacyGrievanceTitle => 'Questions or complaints';

  @override
  String get privacyGrievanceOfficer => 'Grievance Officer';

  @override
  String get privacyDangerZone => 'Danger zone';

  @override
  String get privacyDeleteAccount => 'Delete my account';

  @override
  String get privacyDeleteAccountBody => 'This cannot be undone';

  @override
  String get privacyDeleteTitle => 'Delete your account?';

  @override
  String get privacyDeleteWarning =>
      'Your profile, appointments and sharing permissions will be deleted, and every doctor will immediately lose access to your records.\n\nConsultation notes and prescriptions must be kept for 3 years under medical record rules, so those are retained and then deleted. They are not used for anything else.\n\nThis cannot be undone.';

  @override
  String get privacyKeepAccount => 'Keep my account';

  @override
  String privacyDeleted(String date) {
    return 'Your account is deleted. Consultation notes and prescriptions are kept until $date because medical record rules require it, and are then destroyed.';
  }

  @override
  String get privacyExportReady => 'Your data is ready to save.';

  @override
  String privacySignedInAs(String name) {
    return 'Signed in as $name';
  }

  @override
  String get blockedTitle => 'You cannot use MiDoctor right now';

  @override
  String get blockedSuspended =>
      'Your account is suspended. Contact support if you think this is a mistake.';

  @override
  String get blockedDeactivated => 'Your account has been deactivated.';

  @override
  String get blockedStaff =>
      'This account is for MiDoctor staff. Please use the operations console.';

  @override
  String get blockedContactSupport => 'Contact support';

  @override
  String get providerTodayTitle => 'Today';

  @override
  String get providerTodayNone => 'Nothing scheduled';

  @override
  String get providerTodayNoneBody =>
      'Your consultations for today will appear here.';

  @override
  String get providerCheckIn => 'Check in';

  @override
  String get providerStartConsultation => 'Start consultation';

  @override
  String get providerWritePrescription => 'Write prescription';

  @override
  String get providerRequestRecords => 'Request records';

  @override
  String get providerPatientsTitle => 'Patients';

  @override
  String get providerPatientsNone => 'No patients yet';

  @override
  String get providerPatientsNoneBody =>
      'Patients who share records with you will appear here.';

  @override
  String get availabilityTitle => 'Your hours';

  @override
  String get availabilityAddHours => 'Add hours';

  @override
  String get availabilityNone => 'No hours set';

  @override
  String get availabilityNoneBody =>
      'Add your working hours so patients can book with you.';

  @override
  String get availabilityDay => 'Day';

  @override
  String get availabilityFrom => 'From';

  @override
  String get availabilityTo => 'To';

  @override
  String get availabilityAppointmentLength => 'Appointment length';

  @override
  String availabilityMinutes(int minutes) {
    return '$minutes minutes';
  }

  @override
  String availabilitySlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slots',
      one: '1 slot',
    );
    return '$_temp0';
  }

  @override
  String get availabilityBlockDay => 'Block a day';

  @override
  String get availabilityBlockedDays => 'Blocked days';

  @override
  String get availabilityNoBlockedDays => 'No days blocked';

  @override
  String get availabilityBlockReason => 'Reason (optional)';

  @override
  String get availabilityPaused => 'Paused';

  @override
  String get verificationTitle => 'Verification';

  @override
  String get verificationSubmitDocuments => 'Submit documents';

  @override
  String get verificationResubmitDocuments => 'Resubmit documents';

  @override
  String get verificationDraftTitle => 'Complete your profile';

  @override
  String get verificationDraftBody =>
      'Upload your degree certificate, medical registration, identity proof and hospital affiliation to start seeing patients.';

  @override
  String get verificationInProgressTitle => 'Verification in progress';

  @override
  String get verificationInProgressBody =>
      'Our team is reviewing your documents. This usually takes 2–3 working days, and we will notify you as soon as it is done.';

  @override
  String get verificationRejectedTitle => 'Verification unsuccessful';

  @override
  String get verificationRejectedBody =>
      'We could not verify your documents. Check the reason sent to you and submit again.';

  @override
  String get verificationResubmitTitle => 'More information needed';

  @override
  String get verificationResubmitBody =>
      'Some of your documents need to be resubmitted. Please review the notes we sent and upload them again.';

  @override
  String get verificationSuspendedTitle => 'Account under review';

  @override
  String get verificationSuspendedBody =>
      'Your provider account is temporarily suspended pending a review. Please contact MiDoctor support.';

  @override
  String get verificationDeactivatedTitle => 'Account deactivated';

  @override
  String get verificationDeactivatedBody =>
      'Your provider account has been deactivated. Contact support if you would like to reactivate it.';

  @override
  String get verificationVerifiedTitle => 'Verified';

  @override
  String get verificationVerifiedBody => 'Your account is verified.';

  @override
  String get credentialsTitle => 'Your credentials';

  @override
  String credentialsProgress(int done, int total) {
    return '$done of $total steps done';
  }

  @override
  String get credentialsDocuments => 'Documents';

  @override
  String get credentialsRegistrationNumber => 'Council registration number';

  @override
  String get credentialsRegistrationHint => 'e.g. KMC-41902';

  @override
  String get credentialsMfa => 'Two-factor authentication';

  @override
  String get credentialsMfaBody =>
      'Required before you can see patients. Your account can read medical records, so it has to be hard to take over.';

  @override
  String get credentialsSetUpMfa => 'Set up';

  @override
  String get credentialsVerifyIdentity => 'Verify with DigiLocker';

  @override
  String get credentialsSubmitForReview => 'Submit for review';

  @override
  String get credentialsSubmitted =>
      'Submitted. We will be in touch within 2–3 working days.';

  @override
  String get mfaTitle => 'Two-factor authentication';

  @override
  String get mfaStep1 => 'Scan this with your authenticator app';

  @override
  String get mfaCantScan => 'Cannot scan? Enter this key instead';

  @override
  String get mfaStep2 => 'Enter the 6-digit code';

  @override
  String get mfaCodeLabel => 'Code';

  @override
  String get mfaConfirm => 'Confirm';

  @override
  String get mfaRecoveryTitle => 'Save your recovery codes';

  @override
  String get mfaRecoveryBody =>
      'Each code works once. Keep them somewhere safe — they are the only way back in if you lose your phone, and we cannot show them again.';

  @override
  String get mfaRecoveryCopied => 'Recovery codes copied.';

  @override
  String get mfaSavedThem => 'I have saved them';

  @override
  String get prescribeTitle => 'Write a prescription';

  @override
  String get prescribeSearchDrug => 'Search for a medicine';

  @override
  String get prescribeStrength => 'Strength';

  @override
  String get prescribeFrequency => 'Frequency';

  @override
  String get prescribeFrequencyHint => 'e.g. 1-0-1';

  @override
  String get prescribeDuration => 'Duration (days)';

  @override
  String get prescribeInstructions => 'Instructions';

  @override
  String get prescribeAdd => 'Add medicine';

  @override
  String get prescribeNoItems => 'No medicines added yet';

  @override
  String get prescribeDiagnosis => 'Diagnosis';

  @override
  String get prescribeAdvice => 'Advice';

  @override
  String get prescribeIssue => 'Issue prescription';

  @override
  String get prescribeIssued => 'Prescription issued.';

  @override
  String get prescribeFollowUpOnly => 'Follow-up only';

  @override
  String get prescribeNotAllowed => 'Not allowed remotely';

  @override
  String get prescribeOtc => 'Over the counter';

  @override
  String get sharingHeading => 'Record sharing';

  @override
  String get sharingCurrentlyShared => 'Currently shared';

  @override
  String get sharingRequestsWaiting => 'Requests waiting for you';

  @override
  String get sharingNothingToShow => 'Nothing to show yet';

  @override
  String get sharingAccessEnded => 'Access ended';

  @override
  String get sharingEnded => 'Ended';

  @override
  String get sharingKeepSharing => 'Keep sharing';

  @override
  String get sharingStopSharingQuestion => 'Stop sharing?';

  @override
  String get sharingHowLong => 'How long should access last?';

  @override
  String get sharingShare => 'Share';

  @override
  String get appointmentReference => 'Reference';

  @override
  String get appointmentWhen => 'When';

  @override
  String get appointmentType => 'Type';

  @override
  String get appointmentTellUsWhy => 'Tell us why';

  @override
  String get appointmentCancellationReason => 'Cancellation reason';

  @override
  String get appointmentCancelIt => 'Cancel it';

  @override
  String get searchAvailableToday => 'Available today';

  @override
  String get searchAvailableTodayBody => 'Only doctors with a free slot today';

  @override
  String get searchDoctorHint => 'Doctor, specialty or hospital';

  @override
  String get searchClearFiltersShort => 'Clear filters';

  @override
  String get searchNoMatch => 'No doctors match your search';

  @override
  String get doctorTitle => 'Doctor';

  @override
  String get doctorConsultationFees => 'Consultation fees';

  @override
  String get doctorPractisesAt => 'Practises at';

  @override
  String get doctorMedicalRegistration => 'Medical registration';

  @override
  String get bookingAvailableTimes => 'Available times';

  @override
  String get bookingSelectDate => 'Select a date';

  @override
  String get bookingNoSlotsOnDay => 'No slots on this day';

  @override
  String get bookingReasonOptional => 'Reason for visit (optional)';

  @override
  String get bookingSymptomsHint => 'Briefly describe your symptoms or concern';

  @override
  String get consultAgreeContinue => 'Agree and continue';

  @override
  String get consultEndQuestion => 'End consultation?';

  @override
  String get consultEitherCanEnd => 'Either of you can end the consultation.';

  @override
  String get consultStay => 'Stay';

  @override
  String get consultSwitch => 'Switch';

  @override
  String get consultNoMessages => 'No messages yet';

  @override
  String get consultKeptWithRecord => 'Kept as part of your medical record';

  @override
  String get privacyThisCannotBeUndone => 'This cannot be undone';

  @override
  String get privacyUpdateDetails => 'Update your profile details';

  @override
  String get credentialsStepDocuments => '1. Documents';

  @override
  String get credentialsStepRegistration => '2. Registration number';

  @override
  String get credentialsStepMfa => '3. Two-factor authentication';

  @override
  String get credentialsAuthenticatorApp => 'Authenticator app';

  @override
  String get credentialsPaperCertificate => 'Best for a paper certificate';

  @override
  String get credentialsChooseFile => 'Choose a file';

  @override
  String get credentialsCouncilRegistration => 'Council registration';

  @override
  String get credentialsRegistrationNumberLabel =>
      'Medical registration number';

  @override
  String get credentialsFileTypes => 'PDF, JPG, PNG or HEIC';

  @override
  String get credentialsGetVerified => 'Get verified';

  @override
  String get credentialsSubmittedForReview => 'Submitted for review';

  @override
  String get credentialsTakePhoto => 'Take a photo';

  @override
  String get availabilityMySchedule => 'My schedule';

  @override
  String get availabilityAddAvailability => 'Add availability';

  @override
  String get availabilityDaysOff => 'Days off';

  @override
  String get availabilityMarkDayOff => 'Mark a day off';

  @override
  String get availabilityConsultationType => 'Consultation type';

  @override
  String get mfaInstallApp => '1. Install an authenticator app';

  @override
  String get mfaAddKey => '2. Add this key';

  @override
  String get mfaEnterCode => '3. Enter the 6-digit code';

  @override
  String get mfaCopyKey => 'Copy key';

  @override
  String get mfaKeyCopied => 'Key copied';

  @override
  String get mfaClipboardCleared =>
      'Copied. The clipboard clears itself in a minute.';

  @override
  String get mfaCopyAllCodes => 'Copy all codes';

  @override
  String get mfaVerifyEnable => 'Verify and enable';

  @override
  String get mfaIsOn => 'Two-factor is on';

  @override
  String get prescribeWriteTitle => 'Write prescription';

  @override
  String get prescribeSearchMedicines => 'Search medicines';

  @override
  String get prescribeAddToPrescription => 'Add to prescription';

  @override
  String get prescribeChange => 'Change';

  @override
  String get prescribeAdviceToPatient => 'Advice to the patient';

  @override
  String get prescribeDurationDays => 'Duration (days)';

  @override
  String get prescribeFollowUpConsultation => 'Follow-up consultation';

  @override
  String get prescribeInstructionsOptional => 'Instructions (optional)';

  @override
  String get prescribeMedicines => 'Medicines';

  @override
  String get prescribeNoMedicines => 'No medicines added yet';

  @override
  String get prescribeIssued2 => 'Prescription issued';

  @override
  String get prescriptionsNoneYet => 'No prescriptions yet';

  @override
  String get prescriptionIssued => 'Issued';

  @override
  String get prescriptionPatient => 'Patient';

  @override
  String get prescriptionPharmacyVerification => 'Pharmacy verification';

  @override
  String get supportHelpAndSupport => 'Help and support';

  @override
  String get supportHowCanWeHelp => 'How can we help?';

  @override
  String get supportNoRequests => 'No support requests';

  @override
  String get supportRequestSent => 'Request sent. We will be in touch.';

  @override
  String get supportSendRequest => 'Send request';

  @override
  String get supportTitleLabel => 'Title';

  @override
  String get supportWhatHappened => 'What happened?';

  @override
  String get providerNothingToday => 'Nothing scheduled today';

  @override
  String get providerPrescribe => 'Prescribe';

  @override
  String get providerStart => 'Start';

  @override
  String get homeQuickActions => 'Quick actions';
}
