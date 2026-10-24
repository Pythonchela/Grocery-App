import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../widgets/cart_bar.dart';
import '../widgets/product_card.dart';
import '../widgets/product_grid.dart';
import 'product_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  /// Pre-fills and runs a search, for links that point at one.
  final String initialQuery;

  const SearchScreen({super.key, this.initialQuery = ''});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Product> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().length >= 2) {
      _controller.text = widget.initialQuery;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _search(widget.initialQuery));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _requestId++;
    _controller.dispose();
    super.dispose();
  }

  /// Debounced, so typing "headphones" is one request rather than ten — and,
  /// now that the API is rate limited, so a fast typist doesn't hit a 429.
  void _onChanged(String value) {
    _debounce?.cancel();
    _requestId++;
    setState(() {
      _error = null;
      _loading = value.trim().length >= 2;
    });
    if (value.trim().length < 2) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      _onChanged(query);
      return;
    }
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ApiClient.request('/products',
          query: {'search': query.trim(), 'per_page': '30'});
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = (data as List).map((p) => Product.fromJson(p)).toList();
        _loading = false;
        _searched = true;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _searched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      bottomNavigationBar: const CartBar(),
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: DsSpace.s4),
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: _search,
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: DsText.base, color: c.ink),
            decoration: InputDecoration(
              hintText: "Search the catalogue, e.g. 'silk saree'",
              hintStyle: TextStyle(color: c.inkSubtle, fontSize: DsText.base),
              prefixIcon: Icon(Icons.search, size: 18, color: c.inkSubtle),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.clear, size: 18, color: c.inkSubtle),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
              filled: true,
              fillColor: c.surfaceSunken,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: const OutlineInputBorder(
                borderRadius: DsRadius.pillAll,
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          if (_loading) {
            return GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(DsSpace.s4),
              mainAxisSpacing: DsSpace.s3,
              crossAxisSpacing: DsSpace.s3,
              childAspectRatio: 0.58,
              children: List.generate(
                4,
                (_) => const BxSkeleton(
                    height: double.infinity, radius: DsRadius.cardAll),
              ),
            );
          }

          if (_error != null) {
            return BxEmptyState(
              icon: Icons.wifi_off_outlined,
              title: 'Search failed',
              description: _error,
              action: BxButton(
                  label: 'Retry', onPressed: () => _search(_controller.text)),
            );
          }

          if (!_searched) {
            return const BxEmptyState(
              icon: Icons.search,
              title: 'What are you looking for?',
              description:
                  'Search is typo-tolerant — "anarkli" finds Anarkali.',
            );
          }

          if (_results.isEmpty) {
            return BxEmptyState(
              icon: Icons.search_off,
              title: 'No matches',
              description:
                  'Nothing matched "${_controller.text.trim()}". Try a broader term.',
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(DsSpace.s4),
            gridDelegate: productGridDelegate(context),
            itemCount: _results.length,
            itemBuilder: (context, i) => ProductCardTile(
              product: _results[i],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        ProductDetailScreen(productId: _results[i].id)),
              ),
            ),
          );
        },
      ),
    );
  }
}
