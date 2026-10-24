import '../data/api_client.dart';

/// Help requests from shoppers and sellers.
///
/// This folder is shared by the shopper app and the seller area, so it may
/// import only the API client and the design system (see test/support/boundary_test.dart).

const supportCategories = [
  ('ORDER_ISSUE', 'A problem with an order'),
  ('DELIVERY', 'Delivery or tracking'),
  ('PAYMENT', 'Payment'),
  ('REFUND', 'Refund or return'),
  ('PRODUCT', 'A product'),
  ('ACCOUNT', 'My account'),
  ('PAYOUT', 'Payouts and earnings'),
  ('SHOP_SETUP', 'Setting up my shop'),
  ('OTHER', 'Something else'),
];

/// What a seller may ask about, and what a shopper may.
const sellerOnlyCategories = {'PAYOUT', 'SHOP_SETUP'};
const shopperOnlyCategories = {'ACCOUNT'};

String supportStatusLabel(String status) => switch (status) {
      'OPEN' => 'Waiting for us',
      'IN_PROGRESS' => 'We are on it',
      'WAITING_ON_REQUESTER' => 'Waiting for your reply',
      'RESOLVED' => 'Resolved',
      'CLOSED' => 'Closed',
      _ => status,
    };

class SupportMessage {
  final String id;
  final bool fromTeam;
  final String body;
  final DateTime? at;

  const SupportMessage({required this.id, required this.fromTeam, required this.body, this.at});

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        id: '${j['id']}',
        fromTeam: j['author'] == 'STAFF',
        body: '${j['body'] ?? ''}',
        at: DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal(),
      );
}

class SupportTicket {
  final String id;
  final String number;
  final String subject;
  final String status;
  final String? orderNumber;
  final DateTime? lastMessageAt;
  final int? rating;
  final List<SupportMessage> messages;

  const SupportTicket({
    required this.id,
    required this.number,
    required this.subject,
    required this.status,
    this.orderNumber,
    this.lastMessageAt,
    this.rating,
    this.messages = const [],
  });

  bool get resolved => status == 'RESOLVED' || status == 'CLOSED';

  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
        id: '${j['id']}',
        number: '${j['number'] ?? ''}',
        subject: '${j['subject'] ?? ''}',
        status: '${j['status'] ?? 'OPEN'}',
        orderNumber: j['order_number'] == null ? null : '${j['order_number']}',
        lastMessageAt: DateTime.tryParse('${j['last_message_at'] ?? ''}')?.toLocal(),
        rating: j['rating'] is num ? (j['rating'] as num).toInt() : null,
        messages: [
          for (final m in (j['messages'] as List? ?? const [])) SupportMessage.fromJson((m as Map).cast<String, dynamic>()),
        ],
      );
}

/// Everything the help screens need from the server, behind an interface so tests can fake it.
abstract class SupportApi {
  Future<List<SupportTicket>> tickets();
  Future<SupportTicket> ticket(String id);
  Future<SupportTicket> open({required String category, required String subject, required String message, String? orderId});
  Future<SupportTicket> reply(String id, String body);
  Future<SupportTicket> close(String id);
  Future<SupportTicket> rate(String id, int rating);
}

class HttpSupportApi implements SupportApi {
  /// Read fresh on every request, so a refreshed login is picked up.
  final String? Function() token;

  const HttpSupportApi(this.token);

  Future<dynamic> _call(String path, {String method = 'GET', Object? body}) =>
      ApiClient.request(path, method: method, body: body, token: token());

  SupportTicket _one(dynamic data) => SupportTicket.fromJson((data as Map).cast<String, dynamic>());

  @override
  Future<List<SupportTicket>> tickets() async =>
      [for (final t in (await _call('/support/tickets')) as List) SupportTicket.fromJson((t as Map).cast<String, dynamic>())];

  @override
  Future<SupportTicket> ticket(String id) async => _one(await _call('/support/tickets/$id'));

  @override
  Future<SupportTicket> open({required String category, required String subject, required String message, String? orderId}) async =>
      _one(await _call('/support/tickets', method: 'POST', body: {
        'category': category,
        'subject': subject,
        'message': message,
        if (orderId != null) 'order_id': orderId,
      }));

  @override
  Future<SupportTicket> reply(String id, String body) async =>
      _one(await _call('/support/tickets/$id/messages', method: 'POST', body: {'body': body}));

  @override
  Future<SupportTicket> close(String id) async => _one(await _call('/support/tickets/$id/close', method: 'POST'));

  @override
  Future<SupportTicket> rate(String id, int rating) async =>
      _one(await _call('/support/tickets/$id/rating', method: 'POST', body: {'rating': rating}));
}
