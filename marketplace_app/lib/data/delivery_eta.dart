import 'package:intl/intl.dart';

/// What to tell the shopper about when their order arrives.
class EtaSummary {
  /// The big line: "Arriving in 18 mins".
  final String headline;

  /// The smaller line beneath it, if there is anything useful to add.
  final String detail;

  const EtaSummary(this.headline, [this.detail = '']);
}

/// Words for where an order is, as a person would say it.
String statusHeadline(String status, {String? riderName}) {
  switch (status) {
    case 'PENDING':
      return 'Order received';
    case 'CONFIRMED':
      return 'Order confirmed';
    case 'PACKED':
      return 'Packed and ready to go';
    case 'SHIPPED':
      return riderName == null ? 'On its way' : '$riderName is on the way';
    case 'OUT_FOR_DELIVERY':
      return riderName == null ? 'Out for delivery' : '$riderName is nearby';
    case 'DELIVERED':
      return 'Delivered';
    case 'CANCELLED':
      return 'Order cancelled';
    default:
      return 'Order update';
  }
}

/// Works out the arrival line from the best information available, in order of
/// trust: the courier's live estimate, then the promise made at checkout.
EtaSummary describeEta({
  required String status,
  int? etaMinutes,
  DateTime? promisedBy,
  DateTime? now,
}) {
  if (status == 'CANCELLED') return const EtaSummary('Order cancelled');
  if (status == 'DELIVERED') return const EtaSummary('Delivered', 'Enjoy!');

  final clock = now ?? DateTime.now();

  String inMinutes(int minutes) {
    if (minutes <= 1) return 'Arriving now';
    if (minutes < 90) return 'Arriving in $minutes mins';
    final hours = (minutes / 60).round();
    return 'Arriving in $hours ${hours == 1 ? 'hr' : 'hrs'}';
  }

  if (etaMinutes != null && etaMinutes >= 0) {
    return EtaSummary(inMinutes(etaMinutes), 'Live estimate from your delivery partner');
  }

  if (promisedBy != null) {
    final minutes = promisedBy.difference(clock).inMinutes;
    if (minutes <= 0) {
      return const EtaSummary(
          'Running a little late', 'Your delivery partner is on it');
    }
    if (minutes < 90) return EtaSummary(inMinutes(minutes), 'As promised at checkout');
    final local = promisedBy.toLocal();
    final sameDay = local.year == clock.year &&
        local.month == clock.month &&
        local.day == clock.day;
    return EtaSummary(
      sameDay
          ? 'Arriving by ${DateFormat.jm().format(local)}'
          : 'Arriving by ${DateFormat('EEE, d MMM').format(local)}',
      'As promised at checkout',
    );
  }

  return const EtaSummary('Preparing your order', "We'll tell you when it is on the way");
}
