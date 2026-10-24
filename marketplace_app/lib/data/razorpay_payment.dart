import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../design/brand.g.dart';

/// What Razorpay hands back after a successful payment. The server re-checks
/// the signature and asks Razorpay whether the payment really captured, so
/// this is a claim, not evidence.
class PaymentProof {
  final String paymentId;
  final String signature;

  const PaymentProof(this.paymentId, this.signature);
}

/// The shopper closed the payment sheet. A normal outcome, not a failure —
/// callers should return to the screen quietly rather than show a red banner.
class PaymentCancelled implements Exception {
  @override
  String toString() => 'Payment cancelled.';
}

class PaymentFailed implements Exception {
  final String message;

  PaymentFailed(this.message);

  @override
  String toString() => message;
}

/// Opens Razorpay's native payment sheet for an order the server created via
/// `POST /payments/intent`.
class RazorpayPayment {
  /// The native sheet exists on Android and iOS only.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<PaymentProof> collect({
    required String keyId,
    required String orderId,
    required int amountPaise,
    String? description,
    String? contact,
    String? email,
  }) {
    if (!isSupported) {
      throw PaymentFailed(
        'Online payment is available in the Android and iOS apps. '
        'Choose Cash on delivery here, or open the app on your phone.',
      );
    }

    final razorpay = Razorpay();
    final done = Completer<PaymentProof>();

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      final paymentId = r.paymentId;
      final signature = r.signature;
      if (done.isCompleted) return;

      if (paymentId == null || signature == null) {
        done.completeError(PaymentFailed(
          'The payment finished but could not be confirmed. If money was '
          'deducted it will be refunded automatically.',
        ));
      } else {
        done.complete(PaymentProof(paymentId, signature));
      }
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      if (done.isCompleted) return;

      done.completeError(
        r.code == Razorpay.PAYMENT_CANCELLED
            ? PaymentCancelled()
            : PaymentFailed(r.message ?? 'The payment failed. You have not been charged.'),
      );
    });

    // Wallet apps (Paytm, etc.) complete the payment outside this sheet, so we
    // never get a signature back for them. Say so instead of hanging forever.
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      if (done.isCompleted) return;

      done.completeError(PaymentFailed(
        'That wallet is not supported. Please pay with UPI, card or netbanking.',
      ));
    });

    razorpay.open({
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': DsBrand.name,
      if (description != null) 'description': description,
      'prefill': {
        if (contact != null) 'contact': contact,
        if (email != null) 'email': email,
      },
      'retry': {'enabled': true, 'max_count': 2},
    });

    // Always release the native listeners, whichever way it ends.
    return done.future.whenComplete(razorpay.clear);
  }
}
