import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../support/support_api.dart';
import '../../support/support_screens.dart';
import '../seller_host.dart';

/// Shop operations that do not fit in the packing or product form screens.
class OperationsTab extends StatefulWidget {
  final SellerHost host;

  /// Asks for a section to be shown (the dashboard's menu uses it).
  final ValueNotifier<String?>? sectionRequest;

  const OperationsTab({super.key, required this.host, this.sectionRequest});

  @override
  State<OperationsTab> createState() => _OperationsTabState();
}

class _OperationsTabState extends State<OperationsTab> {
  String _section = 'Insights';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _insights = {};
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _questions = [];

  Future<dynamic> _call(String path, {String method = 'GET', Object? body}) =>
      ApiClient.request(path, method: method, body: body, token: widget.host.token());

  List<Map<String, dynamic>> _list(dynamic value) =>
      (value as List).map((e) => (e as Map).cast<String, dynamic>()).toList();

  static const _sections = ['Insights', 'Reviews & Q&A', 'Returns', 'Offers'];

  void _onSectionRequest() {
    final wanted = widget.sectionRequest?.value;
    if (wanted == null || !_sections.contains(wanted) || wanted == _section) return;
    setState(() => _section = wanted);
    _load();
  }

  @override
  void initState() {
    super.initState();
    // A tab built because of a request (not yet listening) still honours it.
    final first = widget.sectionRequest?.value;
    if (first != null && _sections.contains(first)) _section = first;
    widget.sectionRequest?.addListener(_onSectionRequest);
    _load();
  }

  @override
  void dispose() {
    widget.sectionRequest?.removeListener(_onSectionRequest);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      switch (_section) {
        case 'Insights':
          _insights = (await _call('/seller/overview') as Map).cast<String, dynamic>();
        case 'Reviews & Q&A':
          _rows = _list(await _call('/seller/reviews?per_page=100'));
          _questions = _list(await _call('/seller/questions?per_page=100'));
        case 'Returns':
          _rows = _list(await _call('/seller/returns?per_page=100'));
        case 'Offers':
          _rows = _list(await _call('/seller/coupons'));
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _respond(String path, String field, String initial) async {
    final controller = TextEditingController(text: initial);
    final content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(field == 'reply' ? 'Reply to review' : 'Answer question'),
        content: TextField(controller: controller, maxLines: 4, maxLength: 2000,
          decoration: const InputDecoration(hintText: 'Write a helpful, public response')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Post')),
        ],
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty) return;
    try {
      await _call(path, method: field == 'reply' ? 'PUT' : 'POST', body: {field: content});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  String _title(Map<String, dynamic> row) =>
      (row['product'] is Map ? row['product']['title'] : null)?.toString() ?? 'Product';

  Future<void> _editOffer([Map<String, dynamic>? offer]) async {
    final code = TextEditingController(text: offer?['code']?.toString() ?? '');
    final value = TextEditingController(text: offer?['value']?.toString() ?? '');
    final minimum = TextEditingController(text: offer?['min_order']?.toString() ?? '0');
    String type = offer?['type']?.toString() ?? 'PERCENT';
    try {
      final save = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: Text(offer == null ? 'Create shop offer' : 'Edit shop offer'),
        content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: code, maxLength: 40, decoration: const InputDecoration(labelText: 'Code')),
          DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Discount'),
            items: const [DropdownMenuItem(value: 'PERCENT', child: Text('Percent off')),
              DropdownMenuItem(value: 'FLAT', child: Text('Amount off'))],
            onChanged: (v) => update(() => type = v ?? type)),
          TextField(controller: value, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: type == 'PERCENT' ? 'Percent' : 'Amount (₹)')),
          TextField(controller: minimum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum shop spend (₹)')),
          const SizedBox(height: 8),
          const Text('This code discounts only items from your shop.'),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))],
      )));
      final amount = double.tryParse(value.text.trim());
      if (save != true) return;
      if (code.text.trim().isEmpty || amount == null || amount <= 0 ||
          (type == 'PERCENT' && amount > 100)) {
        throw Exception('Enter a code and a valid discount (1–100% for percentages).');
      }
      await _call(offer == null ? '/seller/coupons' : '/seller/coupons/${offer['id']}',
        method: offer == null ? 'POST' : 'PUT', body: {
          'code': code.text.trim().toUpperCase(), 'type': type, 'value': amount,
          'min_order': double.tryParse(minimum.text.trim()) ?? 0,
          if (offer == null) 'is_active': true,
        });
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      code.dispose(); value.dispose(); minimum.dispose();
    }
  }

  Future<void> _toggleOffer(Map<String, dynamic> offer) async {
    try {
      await _call('/seller/coupons/${offer['id']}', method: 'PUT', body: {'is_active': offer['is_active'] != true});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _reviewReturn(Map<String, dynamic> row) async {
    final note = TextEditingController(text: row['seller_note']?.toString() ?? '');
    String recommendation = row['seller_recommendation']?.toString() ?? 'NEEDS_REVIEW';
    try {
      final save = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: Text('Review ${row['rma_number']}'),
        content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Your recommendation helps the marketplace team decide pickup and refund.'),
          DropdownButtonFormField<String>(initialValue: recommendation, items: const [
            DropdownMenuItem(value: 'NEEDS_REVIEW', child: Text('Needs review')),
            DropdownMenuItem(value: 'ACCEPT', child: Text('Recommend accept')),
            DropdownMenuItem(value: 'REJECT', child: Text('Recommend reject')),
          ], onChanged: (v) => update(() => recommendation = v ?? recommendation)),
          TextField(controller: note, maxLength: 2000, maxLines: 3,
            decoration: const InputDecoration(labelText: 'What did you check?')),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send review'))],
      )));
      if (save != true) return;
      if (note.text.trim().length < 3) throw Exception('Write a short review note.');
      await _call('/seller/returns/${row['id']}/review', method: 'PUT', body: {
        'seller_recommendation': recommendation, 'seller_note': note.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally { note.dispose(); }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Column(children: [
        ListTile(
          key: const Key('manage-account'),
          leading: const Icon(Icons.storefront_outlined),
          title: Text(widget.host.marketplaceName),
          subtitle: const Text('You are signed in to your shop'),
        ),
        if (widget.host.onSwitchToShopping != null) ...[
          const Divider(height: 1),
          ListTile(
            key: const Key('switch-to-shopping'),
            leading: const Icon(Icons.shopping_bag_outlined),
            title: const Text('Shop as a customer'),
            subtitle: const Text('Browse and buy. Your dashboard is one tap away in Account.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.host.onSwitchToShopping,
          ),
        ],
        const Divider(height: 1),
        ListTile(
          key: const Key('seller-sign-out'),
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: widget.host.onSignOut,
        ),
      ])),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final section in _sections)
          ChoiceChip(label: Text(section), selected: _section == section,
            onSelected: (_) { setState(() => _section = section); _load(); }),
        ActionChip(
          key: const Key('seller-help'),
          avatar: const Icon(Icons.support_agent_outlined, size: 18),
          label: const Text('Help & support'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SupportScreen(api: HttpSupportApi(widget.host.token), seller: true),
          )),
        ),
      ]),
      const SizedBox(height: 16),
      if (_loading) const Center(child: CircularProgressIndicator()),
      if (_error != null) ...[
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(onPressed: _load, child: const Text('Try again')),
      ],
      if (!_loading && _error == null && _section == 'Insights') ...[
        for (final entry in [
          ('New orders to answer', _insights['new_orders']),
          ('Past the time you promised', _insights['late_to_pack']),
          ('Orders accepted, last 30 days', _insights['acceptance_rate_30d'] == null ? '—' : '${_insights['acceptance_rate_30d']}%'),
          ('Declined or missed, last 30 days', _insights['turned_down_30d']),
          ('To pack', _insights['to_pack']),
          ('Ready to ship', _insights['packed']),
          ('Orders, last 30 days', _insights['orders_30d']),
          ('Earned, last 30 days', '₹${_insights['sold_30d'] ?? 0}'),
          ('Products low on stock', _insights['low_stock']),
          ('Questions to answer', _insights['questions_open']),
          ('Open returns', _insights['returns_open']),
        ])
          Card(child: ListTile(title: Text(entry.$1), trailing: Text('${entry.$2 ?? 0}',
            style: Theme.of(context).textTheme.titleMedium))),
      ],
      if (!_loading && _error == null && _section == 'Reviews & Q&A') ...[
        Text('Reviews', style: Theme.of(context).textTheme.titleMedium),
        if (_rows.isEmpty) const ListTile(title: Text('No reviews yet')),
        for (final review in _rows)
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_title(review)} · ${review['rating']}/5', style: Theme.of(context).textTheme.titleSmall),
              Text('${review['body'] ?? review['title'] ?? ''}'),
              if (review['status'] == 'APPROVED') ...[
                if (review['admin_reply'] != null) Text('Shop reply: ${review['admin_reply']}'),
                TextButton(onPressed: () => _respond('/seller/reviews/${review['id']}/reply', 'reply',
                  '${review['admin_reply'] ?? ''}'), child: Text(review['admin_reply'] == null ? 'Reply' : 'Edit reply')),
              ] else Text('${review['status']}'),
            ],
          ))),
        const SizedBox(height: 12),
        Text('Product questions', style: Theme.of(context).textTheme.titleMedium),
        if (_questions.isEmpty) const ListTile(title: Text('No approved questions yet')),
        for (final question in _questions)
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title(question), style: Theme.of(context).textTheme.titleSmall),
              Text('${question['body'] ?? ''}'),
              for (final answer in (question['answers'] as List? ?? []))
                if (answer is Map && answer['is_official'] == true)
                  Text('Shop answer: ${answer['body']}'),
              TextButton(onPressed: () => _respond('/questions/${question['id']}/answer', 'body', ''),
                child: const Text('Answer')),
            ],
          ))),
      ],
      if (!_loading && _error == null && _section == 'Returns') ...[
        const Text('The marketplace team approves pickups and refunds.'),
        if (_rows.isEmpty) const ListTile(title: Text('No returns for your products')),
        for (final row in _rows)
          Card(child: Column(children: [ListTile(
            title: Text((row['order_item'] is Map && row['order_item']['product'] is Map)
                ? '${row['order_item']['product']['title']}' : 'Product return'),
            subtitle: Text('${row['rma_number']} · ${row['kind']} · ${row['status']}\n${row['reason']}'),
          ),
          if (row['seller_recommendation'] != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Your review: ${row['seller_recommendation']} · ${row['seller_note']}')),
          if (['REQUESTED', 'PICKUP_SCHEDULED', 'PICKED_UP'].contains(row['status']))
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _reviewReturn(row),
              child: const Text('Review return'))),
          ])),
      ],
      if (!_loading && _error == null && _section == 'Offers') ...[
        const Text('Shop codes only discount your own items. Share a code with shoppers to promote your shop.'),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: () => _editOffer(), icon: const Icon(Icons.add), label: const Text('Create offer')),
        if (_rows.isEmpty) const ListTile(title: Text('No offers yet')),
        for (final offer in _rows) Card(child: ListTile(
          title: Text('${offer['code']} · ${offer['type'] == 'PERCENT' ? '${offer['value']}%' : '₹${offer['value']}'} off'),
          subtitle: Text('Minimum ₹${offer['min_order']} · ${offer['is_active'] == true ? 'Active' : 'Paused'}'),
          trailing: PopupMenuButton<String>(onSelected: (action) {
            if (action == 'edit') _editOffer(offer);
            if (action == 'toggle') _toggleOffer(offer);
          }, itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'toggle', child: Text(offer['is_active'] == true ? 'Pause' : 'Activate')),
          ]),
        )),
      ],
    ]),
  );
}
