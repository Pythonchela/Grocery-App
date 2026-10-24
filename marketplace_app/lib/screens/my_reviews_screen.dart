import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import 'post_purchase_sheets.dart';

/// Reviews the shopper has written, plus delivered items still waiting for one.
class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _pending = [];
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
      final token = AppState.instance.token;
      final results = await Future.wait([
        ApiClient.request('/reviews/mine', token: token),
        ApiClient.request('/reviews/reviewable', token: token),
      ]);
      if (!mounted) return;
      setState(() {
        _mine = (results[0] as List).cast<Map<String, dynamic>>();
        _pending = (results[1] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _write(Map<String, dynamic> item) async {
    final product = item['product'];
    final done = await showWriteReviewSheet(
      context: context,
      productId: item['product_id'].toString(),
      productTitle: product is Map ? '${product['title']}' : 'this product',
      orderId: item['order_id'].toString(),
    );
    if (done == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks — your review is in moderation.')));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(title: const Text('My reviews')),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(DsSpace.s4),
              child: BxSkeleton(height: 120, radius: DsRadius.cardAll),
            )
          : _error != null
              ? BxEmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load reviews',
                  description: _error,
                  action: BxButton(label: 'Try again', onPressed: _load),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: c.accent,
                  child: ListView(
                    padding: const EdgeInsets.all(DsSpace.s4),
                    children: [
                      if (_pending.isNotEmpty) ...[
                        Text('Waiting for your review',
                            style: TextStyle(
                                fontSize: DsText.lg,
                                fontWeight: DsWeight.black,
                                color: c.ink)),
                        const SizedBox(height: DsSpace.s3),
                        ..._pending.map((item) {
                          final product = item['product'];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: DsSpace.s3),
                            child: BxCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            product is Map
                                                ? '${product['title']}'
                                                : 'Product',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontWeight: DsWeight.bold,
                                                color: c.ink)),
                                        Text('Order ${item['order_number']}',
                                            style: TextStyle(
                                                fontSize: DsText.xs,
                                                color: c.inkSubtle)),
                                      ],
                                    ),
                                  ),
                                  BxButton(
                                    label: 'Review',
                                    size: BxButtonSize.sm,
                                    leadingIcon: Icons.star_outline_rounded,
                                    onPressed: () => _write(item),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: DsSpace.s4),
                      ],
                      Text('Your reviews',
                          style: TextStyle(
                              fontSize: DsText.lg,
                              fontWeight: DsWeight.black,
                              color: c.ink)),
                      const SizedBox(height: DsSpace.s3),
                      if (_mine.isEmpty)
                        const BxEmptyState(
                          icon: Icons.rate_review_outlined,
                          title: 'No reviews yet',
                          description:
                              'Once an order is delivered you can review the products here.',
                        )
                      else
                        ..._mine.map((r) {
                          final product = r['product'];
                          final rating = (r['rating'] as num?)?.toInt() ?? 0;
                          final status = r['status']?.toString() ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: DsSpace.s3),
                            child: BxCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                            product is Map
                                                ? '${product['title']}'
                                                : 'Product',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontWeight: DsWeight.bold,
                                                color: c.ink)),
                                      ),
                                      if (status != 'APPROVED')
                                        BxBadge(
                                            status == 'REJECTED'
                                                ? 'Rejected'
                                                : 'In moderation',
                                            tone: status == 'REJECTED'
                                                ? BxTone.danger
                                                : BxTone.warning),
                                    ],
                                  ),
                                  const SizedBox(height: DsSpace.s1),
                                  Row(
                                    children: List.generate(
                                      5,
                                      (i) => Icon(
                                        i < rating
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        size: 18,
                                        color: c.rating,
                                      ),
                                    ),
                                  ),
                                  if ((r['title'] ?? '').toString().isNotEmpty)
                                    Text('${r['title']}',
                                        style: TextStyle(
                                            fontWeight: DsWeight.bold,
                                            color: c.ink)),
                                  if ((r['body'] ?? '').toString().isNotEmpty)
                                    Text('${r['body']}',
                                        style: TextStyle(
                                            fontSize: DsText.base,
                                            color: c.inkMuted)),
                                  const SizedBox(height: DsSpace.s1),
                                  Text(formatDate(r['created_at']?.toString()),
                                      style: TextStyle(
                                          fontSize: DsText.xs,
                                          color: c.inkSubtle)),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}
