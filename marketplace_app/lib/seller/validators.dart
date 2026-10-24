/// Client-side checks that mirror the API's rules, so a seller hears about a typo
/// before a round trip. The server still re-validates everything and its answer
/// wins; these only make the common mistakes cheaper.
///
/// Each returns an error message, or null when the value is acceptable.
class SellerValidators {
  static final _pan = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  static final _gstin = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$');
  static final _ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final _account = RegExp(r'^[0-9]{9,18}$');
  static final _pincode = RegExp(r'^[1-9][0-9]{5}$');
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phone = RegExp(r'^[0-9+\-\s]{7,20}$');

  /// Upper-cased and trimmed, because a PAN typed in lower case is still a PAN.
  static String normalise(String v) => v.trim().toUpperCase();

  static String? required(String v, String what) => v.trim().isEmpty ? 'Enter $what.' : null;

  static String? pan(String v) =>
      _pan.hasMatch(normalise(v)) ? null : 'That does not look like a PAN (for example ABCDE1234F).';

  static String? gstin(String v) => v.trim().isEmpty || _gstin.hasMatch(normalise(v))
      ? null
      : 'That does not look like a GSTIN (15 characters, for example 29ABCDE1234F1Z5).';

  static String? ifsc(String v) => _ifsc.hasMatch(normalise(v))
      ? null
      : 'That does not look like an IFSC code (for example HDFC0001234).';

  static String? accountNumber(String v) =>
      _account.hasMatch(v.trim()) ? null : 'An account number is 9 to 18 digits.';

  static String? pincode(String v) =>
      _pincode.hasMatch(v.trim()) ? null : 'A PIN code is 6 digits and cannot start with 0.';

  /// Optional: blank is fine, a malformed address is not.
  static String? optionalEmail(String v) =>
      v.trim().isEmpty || _email.hasMatch(v.trim()) ? null : 'Enter a valid email address.';

  static String? optionalPhone(String v) =>
      v.trim().isEmpty || _phone.hasMatch(v.trim()) ? null : 'Enter a valid phone number.';
}
