import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../state/app_state.dart';
import 'api_client.dart';
import 'models.dart';

/// What delivering the current cart would look like: to which address, how fast,
/// for how much. Powers the "Delivery in 25 mins" strip on the cart, the way a
/// quick-commerce app tells you the time before you commit to anything.
///
/// Display only. The checkout re-quotes with the shopper's final choices and the
/// server prices the order again on its own.
class CartDelivery extends ChangeNotifier {
  Address? address;
  List<DeliveryOption> options = const [];
  bool loading = false;
  String? error;

  /// Why delivery can't be offered, in the server's words (for example, hot
  /// food and a courier parcel in one basket).
  String? message;

  /// How many parcels the cart ships as: one per seller pickup point. Two
  /// sellers' goods leave from two places, so they travel (and are priced) apart.
  int parcels = 1;

  /// True once a quote attempt has finished, whatever its outcome - so the
  /// screen can tell "still working" from "nothing to show".
  bool settled = false;

  String _signature = '';
  int _generation = 0;

  bool get hasAddress => address != null;
  bool get serviceable => options.isNotEmpty;

  /// The soonest option. The headline promise.
  DeliveryOption? get fastest => options.isEmpty
      ? null
      : options.reduce((a, b) => a.etaMinutes <= b.etaMinutes ? a : b);

  /// The cheapest option, which is what checkout pre-selects (the fastest is an
  /// upsell, and pre-selecting it would charge for a choice nobody made).
  DeliveryOption? get cheapest => options.isEmpty
      ? null
      : options.reduce((a, b) => a.price <= b.price ? a : b);

  /// Re-quotes only when the address or the contents of the cart changed.
  Future<void> refresh({bool force = false}) async {
    final state = AppState.instance;
    final token = state.token;

    if (token == null || state.cart.isEmpty) {
      _reset();
      return;
    }

    final signature = [
      address?.id ?? '',
      state.cartNetSubtotal.toStringAsFixed(2),
      for (final l in state.cart) '${l.key}x${l.quantity}',
    ].join('|');
    if (!force && signature == _signature && settled) return;
    _signature = signature;

    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();

    try {
      address ??= await _defaultAddress(token);
      final current = address;

      if (current == null) {
        options = const [];
      } else {
        final data = await ApiClient.request(
          '/delivery/quote',
          method: 'POST',
          body: {
            'pincode': current.pincode,
            'cod': false,
            'order_value': state.cartNetSubtotal,
            'items': state.cart
                .map((l) => {'product_id': l.product.id, 'quantity': l.quantity})
                .toList(),
          },
        ) as Map<String, dynamic>;

        if (generation != _generation) return;
        options = ((data['options'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(DeliveryOption.fromJson)
            .toList();
        message = data['message'] as String?;
        parcels = ((data['parcels'] as List?)?.length ?? 1).clamp(1, 99);
      }
    } catch (e) {
      if (generation != _generation) return;
      options = const [];
      error = e.toString();
    }

    if (generation != _generation) return;
    loading = false;
    settled = true;
    notifyListeners();
  }

  /// The shopper picked a different address (or added their first).
  Future<void> setAddress(Address? next) async {
    address = next;
    await refresh(force: true);
  }

  Future<Address?> _defaultAddress(String token) async {
    final data = await ApiClient.request('/addresses', token: token) as List;
    final all = data.whereType<Map<String, dynamic>>().map(Address.fromJson).toList();
    return all.where((a) => a.isDefault).firstOrNull ??
        (all.isEmpty ? null : all.first);
  }

  void _reset() {
    _generation++;
    address = null;
    options = const [];
    loading = false;
    error = null;
    settled = false;
    _signature = '';
    notifyListeners();
  }
}

/// "25 mins", "1 hr 30 mins", "3 hrs" - or the server's own wording for a day or more.
String etaHeadline(DeliveryOption option) {
  final m = option.etaMinutes;
  if (m > 0 && m < 90) return '$m mins';
  if (m >= 90 && m < 60 * 24) return _hoursAndMinutes(m);
  return option.etaLabel;
}

String _hoursAndMinutes(int minutes) {
  final h = minutes ~/ 60;
  final r = minutes % 60;
  String hrs(int n) => n == 1 ? '1 hr' : '$n hrs';
  if (r < 10) return hrs(h);
  if (r >= 50) return hrs(h + 1);
  return '${hrs(h)} $r mins';
}

/// What to say about when it arrives, so it reads right at every speed:
/// "Delivery in 25 mins", "Delivery in 3 hrs", "Delivery tomorrow",
/// "Delivery by Mon, 12 Oct". A day or more becomes a date, not "in 2 days"
/// - the shopper plans around dates.
String etaPhrase(DeliveryOption option, {DateTime? now}) {
  final m = option.etaMinutes;
  if (m <= 0) return 'Delivery ${option.etaLabel}';
  if (m < 60 * 24) return 'Delivery in ${etaHeadline(option)}';

  final clock = now ?? DateTime.now();
  final arrives = clock.add(Duration(minutes: m));
  final tomorrow = DateTime(clock.year, clock.month, clock.day + 1);
  if (arrives.year == tomorrow.year &&
      arrives.month == tomorrow.month &&
      arrives.day == tomorrow.day) {
    return 'Delivery tomorrow';
  }
  return 'Delivery by ${DateFormat('EEE, d MMM').format(arrives)}';
}
