import 'package:intl/intl.dart';

/// Display formatting for the seller area. Its own copy rather than the shopper
/// app's helpers, so the folder stays movable.
class SellerFormat {
  static final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _inrWhole = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _date = DateFormat('d MMM yyyy');
  static final _dateTime = DateFormat('d MMM, h:mm a');

  static String money(num v) => _inr.format(v);

  /// No paise, for headline figures.
  static String moneyWhole(num v) => _inrWhole.format(v);

  static String date(DateTime? d) => d == null ? '' : _date.format(d);
  static String dateTime(DateTime? d) => d == null ? '' : _dateTime.format(d);

  static String businessType(String v) => switch (v) {
        'INDIVIDUAL' => 'Individual',
        'PROPRIETORSHIP' => 'Sole proprietorship',
        'PARTNERSHIP' => 'Partnership',
        'LLP' => 'LLP',
        'PRIVATE_LIMITED' => 'Private limited company',
        _ => v,
      };

  static String documentKind(String v) => switch (v) {
        'PAN_CARD' => 'PAN card',
        'GST_CERTIFICATE' => 'GST certificate',
        'CANCELLED_CHEQUE' => 'Cancelled cheque',
        'ADDRESS_PROOF' => 'Address proof',
        'INCORPORATION_CERT' => 'Certificate of incorporation',
        _ => v,
      };

  static String documentHint(String v) => switch (v) {
        'PAN_CARD' => 'A clear photo or scan of the PAN card.',
        'GST_CERTIFICATE' => 'Your GST registration certificate.',
        'CANCELLED_CHEQUE' => 'A cancelled cheque or bank statement page showing your name and account.',
        'ADDRESS_PROOF' => 'Optional. A utility bill or rental agreement.',
        'INCORPORATION_CERT' => 'The certificate issued when the company or firm was registered.',
        _ => '',
      };

  /// Names for the fields the API reports as missing.
  static String field(String v) => switch (v) {
        'business_type' => 'Business type',
        'legal_name' => 'Legal name',
        'pan' => 'PAN',
        'registered_line1' => 'Address line 1',
        'registered_city' => 'City',
        'registered_state' => 'State',
        'registered_pincode' => 'PIN code',
        'bank_account_holder' => 'Account holder name',
        'bank_account_number' => 'Bank account number',
        'bank_ifsc' => 'IFSC code',
        _ => v.replaceAll('_', ' '),
      };

  static String size(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }
}
