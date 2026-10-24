import 'razorpay_payment.dart';

export 'razorpay_payment.dart' show PaymentCancelled, PaymentFailed;

/// Collecting payment for a server-issued intent, whichever gateway issued it.
///
/// The API names the gateway (`intent['provider']`) and hands over that
/// gateway's public settings (`intent['client']`). The app's only job is to run
/// the matching SDK and return whatever it produces as the `payment` object the
/// checkout call carries — the server verifies it with the same gateway.
///
/// To support another gateway: add a case here and a small wrapper beside
/// [RazorpayPayment]. Nothing else in the app changes.
class Payments {
  /// Providers with nothing to collect: the sandbox, and orders that cost ₹0.
  static const _noCollection = {'mock', 'none'};

  /// Returns the evidence to send as `payment`, or null when there is nothing
  /// to collect. Throws [PaymentCancelled] if the shopper backs out and
  /// [PaymentFailed] if the payment does not go through.
  static Future<Map<String, dynamic>?> collect(
    Map<String, dynamic> intent, {
    String? description,
    String? contact,
    String? email,
  }) async {
    final provider = intent['provider'] as String?;
    if (provider == null || _noCollection.contains(provider)) return null;

    final client = (intent['client'] as Map?)?.cast<String, dynamic>() ?? const {};

    switch (provider) {
      case 'razorpay':
        final proof = await RazorpayPayment.collect(
          keyId: client['key_id'] as String,
          orderId: intent['provider_intent_id'] as String,
          amountPaise: (intent['amount_paise'] as num).toInt(),
          description: description,
          contact: contact,
          email: email,
        );
        return {'payment_id': proof.paymentId, 'signature': proof.signature};
      default:
        throw PaymentFailed(
          'This payment method is not supported in this version of the app. '
          'Please update the app and try again.',
        );
    }
  }
}
