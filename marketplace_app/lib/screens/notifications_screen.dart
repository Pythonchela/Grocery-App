import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import 'order_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ApiClient.request('/notifications', token: AppState.instance.token);
      final list = data is Map ? (data['notifications'] ?? data['data'] ?? []) : data;

      if (!mounted) return;
      setState(() {
        _items = (list as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
      AppState.instance
          .setUnread(_items.where((i) => i['is_read'] != true).length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    try {
      await ApiClient.request(
        '/notifications/read-all',
        method: 'PUT',
        token: AppState.instance.token,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    if (item['is_read'] != true) {
      // Fire and forget — the read receipt failing shouldn't block navigation.
      ApiClient.request(
        '/notifications/${item['id']}/read',
        method: 'PUT',
        token: AppState.instance.token,
      ).catchError((_) => null);
    }

    final orderId = (item['data'] as Map?)?['order_id'];
    if (orderId != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId.toString())),
      );
    }

    if (mounted) _load();
  }

  IconData _iconFor(String type) => switch (type) {
        'ORDER_UPDATE' => Icons.local_shipping_outlined,
        'REFUND' => Icons.currency_rupee,
        'PROMO' => Icons.local_offer_outlined,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final unread = _items.where((i) => i['is_read'] != true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                'Mark all read',
                style: TextStyle(color: c.accent, fontWeight: DsWeight.bold),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(DsSpace.s4),
              child: Column(
                children: [
                  BxSkeleton(height: 72, radius: DsRadius.cardAll),
                  SizedBox(height: DsSpace.s3),
                  BxSkeleton(height: 72, radius: DsRadius.cardAll),
                ],
              ),
            )
          : _error != null
              ? BxEmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Could not load notifications',
                  description: _error,
                  action: BxButton(label: 'Retry', onPressed: _load),
                )
              : _items.isEmpty
                  ? const BxEmptyState(
                      icon: Icons.notifications_none,
                      title: 'Nothing yet',
                      description: 'Order updates and price-drop alerts will appear here.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: c.accent,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(DsSpace.s4),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: DsSpace.s2),
                        itemBuilder: (context, i) {
                          final item = _items[i];
                          final isUnread = item['is_read'] != true;

                          return BxCard(
                            onTap: () => _open(item),
                            padding: const EdgeInsets.all(DsSpace.s4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: isUnread ? c.accentSoft : c.surfaceSunken,
                                    borderRadius: DsRadius.pillAll,
                                  ),
                                  child: Icon(
                                    _iconFor(item['type']?.toString() ?? ''),
                                    size: 17,
                                    color: isUnread ? c.accent : c.inkSubtle,
                                  ),
                                ),
                                const SizedBox(width: DsSpace.s3),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['title']?.toString() ?? '',
                                        style: TextStyle(
                                          fontSize: DsText.base,
                                          fontWeight:
                                              isUnread ? DsWeight.black : DsWeight.semibold,
                                          color: c.ink,
                                        ),
                                      ),
                                      if (item['body'] != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          item['body'].toString(),
                                          style: TextStyle(
                                            fontSize: DsText.base,
                                            height: DsText.baseHeight,
                                            color: c.inkMuted,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: DsSpace.s1),
                                      Text(
                                        formatDate(item['created_at']?.toString()),
                                        style: TextStyle(
                                          fontSize: DsText.x2xs,
                                          color: c.inkSubtle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isUnread)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(top: 4),
                                    decoration: BoxDecoration(
                                      color: c.accent,
                                      borderRadius: DsRadius.pillAll,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
