import 'package:flutter/foundation.dart';

/// What a payment is for (FR-PAY-001).
///
/// All three purposes the spec lists are modelled from day one, even though no
/// provider is integrated yet, so that enabling payments is a policy change
/// rather than a schema migration.
enum PaymentPurpose {
  consultationFee,
  procedureFee,
  providerSubscription;

  String get label => switch (this) {
        PaymentPurpose.consultationFee => 'Consultation fee',
        PaymentPurpose.procedureFee => 'Procedure fee',
        PaymentPurpose.providerSubscription => 'Doctor subscription',
      };

  /// Who pays. Subscriptions are billed to the doctor, not the patient — a
  /// distinction the spec lists but never draws.
  bool get isPaidByPatient => this != PaymentPurpose.providerSubscription;
}

/// A procedure billed separately from the consultation, e.g. a dressing or an
/// in-clinic test. Priced by the provider, listed against an appointment.
@immutable
class ProcedureCharge {
  const ProcedureCharge({
    required this.id,
    required this.name,
    required this.amountInr,
    this.description,
  });

  final String id;
  final String name;
  final int amountInr;
  final String? description;
}

/// Doctor subscription tiers.
///
/// FR-PAY-001 names "Doctor Subscription Fees" without defining a single plan,
/// price or billing period. These are placeholders with no pricing authority —
/// the business owns the real numbers.
enum SubscriptionTier {
  free,
  professional,
  clinic;

  String get label => switch (this) {
        SubscriptionTier.free => 'Free',
        SubscriptionTier.professional => 'Professional',
        SubscriptionTier.clinic => 'Clinic',
      };

  String get description => switch (this) {
        SubscriptionTier.free =>
          'Up to 20 consultations a month. MiDoctor commission applies.',
        SubscriptionTier.professional =>
          'Unlimited consultations, priority listing and analytics.',
        SubscriptionTier.clinic =>
          'Everything in Professional, for multiple doctors at one clinic.',
      };
}

/// The abstract payment gateway.
///
/// The only implementation is [ManualPaymentGateway]. No payment SDK is in the
/// dependency tree, deliberately: the provider choice (Razorpay/Cashfree vs the
/// spec's Stripe) is still open, and Stripe is a poor fit for INR domestic
/// collection.
abstract class PaymentGateway {
  String get key;

  Future<PaymentIntent> createIntent({
    required PaymentPurpose purpose,
    required int amountInr,
    required String idempotencyKey,
    String? appointmentId,
  });

  Future<void> refund(String intentId, {String? reason});
}

@immutable
class PaymentIntent {
  const PaymentIntent({
    required this.id,
    required this.purpose,
    required this.amountInr,
    required this.status,
    required this.providerKey,
  });

  final String id;
  final PaymentPurpose purpose;
  final int amountInr;
  final String status;

  /// Which gateway handled it, so historical payments stay attributable after
  /// a provider switch.
  final String providerKey;
}

/// Records the intent without moving money.
///
/// Lets the booking flow, fee display and refund paths all exist and be tested
/// before a gateway is chosen. Every call is a no-op that returns a
/// `NOT_REQUIRED` intent.
class ManualPaymentGateway implements PaymentGateway {
  const ManualPaymentGateway();

  @override
  String get key => 'manual';

  @override
  Future<PaymentIntent> createIntent({
    required PaymentPurpose purpose,
    required int amountInr,
    required String idempotencyKey,
    String? appointmentId,
  }) async {
    return PaymentIntent(
      id: 'manual-$idempotencyKey',
      purpose: purpose,
      amountInr: amountInr,
      status: 'NOT_REQUIRED',
      providerKey: key,
    );
  }

  @override
  Future<void> refund(String intentId, {String? reason}) async {
    // Nothing was captured, so there is nothing to return.
  }
}
