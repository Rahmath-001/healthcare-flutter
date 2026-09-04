/// The seven roles from the RBAC matrix.
///
/// All seven exist here even though this app only ships the patient and
/// provider experiences, so that a token issued for a staff account is
/// represented faithfully rather than silently mis-mapped. Staff roles route to
/// an "unsupported on mobile" screen.
enum UserRole {
  patient,
  provider,
  hospital,
  supervisor,
  supportL1,
  supportL2,
  admin,

  /// Signed in to Firebase, but the API has not yet assigned a role.
  unassigned;

  static UserRole fromWire(String? raw) => switch (raw?.toUpperCase()) {
        'PATIENT' => UserRole.patient,
        'PROVIDER' => UserRole.provider,
        'HOSPITAL' => UserRole.hospital,
        'SUPERVISOR' => UserRole.supervisor,
        'SUPPORT_L1' => UserRole.supportL1,
        'SUPPORT_L2' => UserRole.supportL2,
        'ADMIN' => UserRole.admin,
        _ => UserRole.unassigned,
      };

  /// Whether the patient/provider app has a UI for the role at all.
  ///
  /// The complement is not "no UI" but "a different one" — supervisor, support
  /// and admin are served by the operator console, which is a separate entry
  /// point (`lib/admin/`), not a hidden tab in this binary.
  bool get isSupportedOnMobile =>
      this == UserRole.patient ||
      this == UserRole.provider ||
      this == UserRole.hospital;

  String get wire => switch (this) {
        UserRole.patient => 'PATIENT',
        UserRole.provider => 'PROVIDER',
        UserRole.hospital => 'HOSPITAL',
        UserRole.supervisor => 'SUPERVISOR',
        UserRole.supportL1 => 'SUPPORT_L1',
        UserRole.supportL2 => 'SUPPORT_L2',
        UserRole.admin => 'ADMIN',
        UserRole.unassigned => 'UNASSIGNED',
      };

  String get label => switch (this) {
        UserRole.patient => 'Patient',
        UserRole.provider => 'Doctor',
        UserRole.hospital => 'Hospital',
        UserRole.supervisor => 'Supervisor',
        UserRole.supportL1 => 'Support (L1)',
        UserRole.supportL2 => 'Support (L2)',
        UserRole.admin => 'Admin',
        UserRole.unassigned => 'Unassigned',
      };
}

/// Provider verification state.
///
/// Modelled as a *status* on a single PROVIDER role rather than as two separate
/// roles. The spec's matrix lists "Provider (Unverified)" and
/// "Provider (Approved)" as distinct roles, which duplicates every permission
/// row; the issued token still carries both `role` and `status` exactly as the
/// spec's JWT shape requires.
enum ProviderStatus {
  draft,
  submitted,
  underReview,
  approved,
  rejected,
  resubmitRequested,
  suspended,
  deactivated,

  /// Not a provider.
  notApplicable;

  static ProviderStatus fromWire(String? raw) => switch (raw?.toUpperCase()) {
        'DRAFT' => ProviderStatus.draft,
        'SUBMITTED' => ProviderStatus.submitted,
        'UNDER_REVIEW' => ProviderStatus.underReview,
        'APPROVED' => ProviderStatus.approved,
        'REJECTED' => ProviderStatus.rejected,
        'RESUBMIT_REQUESTED' => ProviderStatus.resubmitRequested,
        'SUSPENDED' => ProviderStatus.suspended,
        'DEACTIVATED' => ProviderStatus.deactivated,
        _ => ProviderStatus.notApplicable,
      };

  /// Only an approved provider gets the full provider experience. Everyone else
  /// sees the verification status screen — which mirrors the RBAC matrix, where
  /// an unverified provider may do nothing but read their own profile and
  /// submit credentials.
  bool get hasFullProviderAccess => this == ProviderStatus.approved;

  String get wire => switch (this) {
        ProviderStatus.draft => 'DRAFT',
        ProviderStatus.submitted => 'SUBMITTED',
        ProviderStatus.underReview => 'UNDER_REVIEW',
        ProviderStatus.approved => 'APPROVED',
        ProviderStatus.rejected => 'REJECTED',
        ProviderStatus.resubmitRequested => 'RESUBMIT_REQUESTED',
        ProviderStatus.suspended => 'SUSPENDED',
        ProviderStatus.deactivated => 'DEACTIVATED',
        ProviderStatus.notApplicable => 'NOT_APPLICABLE',
      };

  String get label => switch (this) {
        ProviderStatus.draft => 'Draft',
        ProviderStatus.submitted => 'Awaiting review',
        ProviderStatus.underReview => 'Under review',
        ProviderStatus.approved => 'Approved',
        ProviderStatus.rejected => 'Rejected',
        ProviderStatus.resubmitRequested => 'Resubmission requested',
        ProviderStatus.suspended => 'Suspended',
        ProviderStatus.deactivated => 'Deactivated',
        ProviderStatus.notApplicable => 'Not a provider',
      };
}

/// Account-level status, independent of role.
enum AccountStatus {
  active,
  pending,
  suspended,
  deactivated;

  static AccountStatus fromWire(String? raw) => switch (raw?.toUpperCase()) {
        'SUSPENDED' => AccountStatus.suspended,
        'DEACTIVATED' => AccountStatus.deactivated,
        'PENDING' => AccountStatus.pending,
        _ => AccountStatus.active,
      };

  String get wire => switch (this) {
        AccountStatus.active => 'ACTIVE',
        AccountStatus.pending => 'PENDING',
        AccountStatus.suspended => 'SUSPENDED',
        AccountStatus.deactivated => 'DEACTIVATED',
      };

  String get label => switch (this) {
        AccountStatus.active => 'Active',
        AccountStatus.pending => 'Pending',
        AccountStatus.suspended => 'Suspended',
        AccountStatus.deactivated => 'Deactivated',
      };
}
