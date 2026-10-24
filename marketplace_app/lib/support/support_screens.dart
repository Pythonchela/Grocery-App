import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import 'support_api.dart';

String _when(DateTime? d) {
  if (d == null) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day} ${months[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'pm' : 'am'}';
}

String _errorText(Object e) => e is ApiException ? (e.fieldError('order_id') ?? e.fieldError('body') ?? e.fieldError('rating') ?? e.message) : 'Could not reach the server. Try again.';

/// The help page: your requests, and a form to start a new one.
class SupportScreen extends StatefulWidget {
  final SupportApi api;

  /// Sellers ask about payouts and their shop; shoppers about orders and their account.
  final bool seller;

  /// Set when opened from an order, so the new request is about that order.
  final String? orderId;
  final String? orderNumber;

  const SupportScreen({super.key, required this.api, this.seller = false, this.orderId, this.orderNumber});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<SupportTicket>? _tickets;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.orderId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _compose());
    }
  }

  Future<void> _load() async {
    try {
      final tickets = await widget.api.tickets();
      if (mounted) setState(() { _tickets = tickets; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    }
  }

  Future<void> _compose() async {
    final created = await Navigator.of(context).push<SupportTicket>(MaterialPageRoute(
      builder: (_) => NewTicketScreen(api: widget.api, seller: widget.seller, orderId: widget.orderId, orderNumber: widget.orderNumber),
    ));
    if (created != null && mounted) {
      await _load();
      if (mounted) await _open(created);
    }
  }

  Future<void> _open(SupportTicket t) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TicketScreen(api: widget.api, ticket: t)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final tickets = _tickets;

    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-ticket'),
        onPressed: _compose,
        icon: const Icon(Icons.add),
        label: const Text('New request'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, 96), children: [
          Text('Tell us what went wrong. We reply here and send you a notification.', style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
          const SizedBox(height: DsSpace.s4),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: c.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
          if (tickets == null && _error == null) const Center(child: CircularProgressIndicator()),
          if (tickets != null && tickets.isEmpty)
            const BxEmptyState(icon: Icons.support_agent_outlined, title: 'No requests yet', description: 'When you ask for help it will show up here.'),
          for (final t in tickets ?? const <SupportTicket>[])
            Padding(
              padding: const EdgeInsets.only(bottom: DsSpace.s2),
              child: BxCard(
                onTap: () => _open(t),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(t.subject, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink))),
                    const SizedBox(width: DsSpace.s2),
                    BxBadge(supportStatusLabel(t.status), tone: t.resolved ? BxTone.neutral : t.status == 'WAITING_ON_REQUESTER' ? BxTone.warning : BxTone.info),
                  ]),
                  const SizedBox(height: DsSpace.s1),
                  Text('${t.number}${t.orderNumber != null ? ' · order ${t.orderNumber}' : ''} · ${_when(t.lastMessageAt)}',
                      style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class NewTicketScreen extends StatefulWidget {
  final SupportApi api;
  final bool seller;
  final String? orderId;
  final String? orderNumber;

  const NewTicketScreen({super.key, required this.api, this.seller = false, this.orderId, this.orderNumber});

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  late String _category = widget.orderId != null ? 'ORDER_ISSUE' : (widget.seller ? 'PAYOUT' : 'ORDER_ISSUE');
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Iterable<(String, String)> get _categories => supportCategories.where((c) =>
      widget.seller ? !shopperOnlyCategories.contains(c.$1) : !sellerOnlyCategories.contains(c.$1));

  Future<void> _send() async {
    if (_subject.text.trim().length < 3 || _message.text.trim().length < 3) {
      setState(() => _error = 'Add a short subject and tell us what happened.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final t = await widget.api.open(category: _category, subject: _subject.text.trim(), message: _message.text.trim(), orderId: widget.orderId);
      if (mounted) Navigator.pop(context, t);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(title: const Text('New request')),
      body: ListView(padding: const EdgeInsets.all(DsSpace.s4), children: [
        if (widget.orderNumber != null)
          Padding(
            padding: const EdgeInsets.only(bottom: DsSpace.s3),
            child: Text('About order ${widget.orderNumber}', style: TextStyle(fontWeight: DsWeight.bold, color: c.ink)),
          ),
        DropdownButtonFormField<String>(
          key: const Key('ticket-category'),
          isExpanded: true,
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'What is it about?'),
          items: [for (final (value, label) in _categories) DropdownMenuItem(value: value, child: Text(label))],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: DsSpace.s3),
        TextField(controller: _subject, maxLength: 160, decoration: const InputDecoration(labelText: 'In a few words')),
        TextField(controller: _message, minLines: 4, maxLines: 8, maxLength: 4000, decoration: const InputDecoration(labelText: 'What happened?')),
        if (_error != null) Text(_error!, style: TextStyle(color: c.danger, fontSize: DsText.sm)),
        const SizedBox(height: DsSpace.s3),
        BxButton(label: 'Send request', fullWidth: true, loading: _busy, onPressed: _busy ? null : _send),
      ]),
    );
  }
}

/// One conversation: read the replies, write back, close it, rate it.
class TicketScreen extends StatefulWidget {
  final SupportApi api;
  final SupportTicket ticket;

  const TicketScreen({super.key, required this.api, required this.ticket});

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  late SupportTicket _ticket = widget.ticket;
  final _reply = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final t = await widget.api.ticket(widget.ticket.id);
      if (mounted) setState(() => _ticket = t);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    }
  }

  Future<void> _do(Future<SupportTicket> Function() call, {bool clear = false}) async {
    setState(() { _busy = true; _error = null; });
    try {
      final t = await call();
      if (mounted) setState(() { _ticket = t; if (clear) _reply.clear(); });
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final t = _ticket;

    return Scaffold(
      appBar: AppBar(title: Text(t.number)),
      body: ListView(padding: const EdgeInsets.all(DsSpace.s4), children: [
        Text(t.subject, style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
        const SizedBox(height: DsSpace.s1),
        Text('${supportStatusLabel(t.status)}${t.orderNumber != null ? ' · order ${t.orderNumber}' : ''}',
            style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
        const SizedBox(height: DsSpace.s4),
        for (final m in t.messages)
          Align(
            alignment: m.fromTeam ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: DsSpace.s2),
              padding: const EdgeInsets.all(DsSpace.s3),
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
              decoration: BoxDecoration(color: m.fromTeam ? c.accentSoft : c.surfaceMuted, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.body, style: TextStyle(color: c.ink)),
                const SizedBox(height: 4),
                Text('${m.fromTeam ? 'Support team' : 'You'} · ${_when(m.at)}', style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
              ]),
            ),
          ),
        if (_error != null) Text(_error!, style: TextStyle(color: c.danger, fontSize: DsText.sm)),
        if (t.status != 'CLOSED') ...[
          const SizedBox(height: DsSpace.s3),
          TextField(
            key: const Key('ticket-reply'),
            controller: _reply,
            minLines: 2,
            maxLines: 6,
            maxLength: 4000,
            decoration: InputDecoration(labelText: t.resolved ? 'Not sorted? Reply to reopen it' : 'Your reply'),
          ),
          Row(children: [
            Expanded(
              child: BxButton(
                label: 'Send',
                loading: _busy,
                onPressed: _busy ? null : () {
                  if (_reply.text.trim().isEmpty) return;
                  _do(() => widget.api.reply(t.id, _reply.text.trim()), clear: true);
                },
              ),
            ),
            if (!t.resolved) ...[
              const SizedBox(width: DsSpace.s2),
              BxButton(
                label: "It's sorted",
                variant: BxButtonVariant.secondary,
                onPressed: _busy ? null : () => _do(() => widget.api.close(t.id)),
              ),
            ],
          ]),
        ],
        if (t.resolved && t.rating == null) ...[
          const SizedBox(height: DsSpace.s4),
          Text('How did we do?', style: TextStyle(fontWeight: DsWeight.bold, color: c.ink)),
          Wrap(spacing: DsSpace.s2, children: [
            for (var n = 1; n <= 5; n++)
              ActionChip(label: Text('$n★'), onPressed: _busy ? null : () => _do(() => widget.api.rate(t.id, n))),
          ]),
        ],
        if (t.rating != null) Padding(
          padding: const EdgeInsets.only(top: DsSpace.s3),
          child: Text('You rated this ${t.rating} out of 5. Thank you.', style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
        ),
      ]),
    );
  }
}
