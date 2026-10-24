import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../document_picker.dart';
import '../seller_api.dart';
import '../seller_format.dart';
import '../seller_models.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/paged_loader.dart';
import '../widgets/seller_widgets.dart';
import 'product_form_screen.dart';
import 'bulk_import_screen.dart';

/// The seller's catalogue, every status (drafts are theirs to see).
class ProductsTab extends StatefulWidget {
  final SellerApi api;
  final DocumentPicker picker;

  /// Told after a product was added, edited or removed.
  final VoidCallback? onChanged;

  const ProductsTab({super.key, required this.api, required this.picker, this.onChanged});

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  static const _filters = [
    BxTab('', 'All'),
    BxTab('ACTIVE', 'Live'),
    BxTab('DRAFT', 'Drafts'),
    BxTab('OUT_OF_STOCK', 'Out of stock'),
    BxTab('DISCONTINUED', 'Discontinued'),
  ];

  String _filter = '';
  String _search = '';
  final _searchField = TextEditingController();
  late PagedLoader<SellerProduct> _loader;

  @override
  void initState() {
    super.initState();
    _loader = _make(_filter)..refresh();
  }

  @override
  void dispose() {
    _loader.dispose();
    _searchField.dispose();
    super.dispose();
  }

  PagedLoader<SellerProduct> _make(String status) =>
      PagedLoader((page) => widget.api.products(status: status, search: _search, page: page));

  void _applySearch() {
    final value = _searchField.text.trim();
    if (value == _search) return;
    final old = _loader;
    setState(() { _search = value; _loader = _make(_filter)..refresh(); });
    old.dispose();
  }

  Future<void> _openForm([SellerProduct? product]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(api: widget.api, picker: widget.picker, product: product)),
    );
    if (changed == true && mounted) {
      widget.onChanged?.call();
      await _loader.refresh();
    }
  }

  Future<void> _quickStock(SellerProduct product) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _StockDialog(api: widget.api, product: product),
    );
    if (changed == true && mounted) {
      widget.onChanged?.call();
      await _loader.refresh();
    }
  }

  /// One item on or off for a while, without touching its stock.
  Future<void> _availability(SellerProduct product) async {
    final live = product.status == 'ACTIVE';
    DateTime? until;
    var available = true;

    if (live) {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final choice = await showModalBottomSheet<DateTime?>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('Switch off until…')),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('2 hours'),
              onTap: () => Navigator.pop(sheet, DateTime.now().add(const Duration(hours: 2))),
            ),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Tomorrow 9 am'),
              onTap: () => Navigator.pop(sheet, DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9)),
            ),
            ListTile(
              leading: const Icon(Icons.toggle_off_outlined),
              title: const Text('Until I switch it on'),
              onTap: () => Navigator.pop(sheet, DateTime.fromMillisecondsSinceEpoch(0)),
            ),
          ]),
        ),
      );
      if (choice == null || !mounted) return;
      available = false;
      until = choice.millisecondsSinceEpoch == 0 ? null : choice;
    }

    try {
      await widget.api.setAvailability(product.id, available: available, until: until);
      widget.onChanged?.call();
      await _loader.refresh();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not reach the server. Try again.')));
    }
  }

  Future<void> _bulkImport() async {
    final count = await Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => BulkImportScreen(api: widget.api),
    ));
    if (count != null && mounted) {
      widget.onChanged?.call();
      await _loader.refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count products imported.')));
    }
  }

  void _select(String status) {
    if (status == _filter) return;
    final old = _loader;
    setState(() {
      _filter = status;
      _loader = _make(status)..refresh();
    });
    old.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PagedListView<SellerProduct>(
          loader: _loader,
          header: [
            Transform.translate(
              offset: const Offset(-DsSpace.s4, 0),
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width,
                child: BxTabs(tabs: _filters, value: _filter, onChanged: _select),
              ),
            ),
            const SizedBox(height: DsSpace.s4),
            TextField(controller: _searchField, textInputAction: TextInputAction.search,
              onSubmitted: (_) => _applySearch(),
              decoration: InputDecoration(labelText: 'Find a product', hintText: 'Name or SKU',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(tooltip: 'Search products', icon: const Icon(Icons.arrow_forward), onPressed: _applySearch))),
            const SizedBox(height: DsSpace.s2),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(
              onPressed: _bulkImport, icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Bulk import'),
            )),
          ],
          empty: BxEmptyState(
            icon: Icons.storefront_outlined,
            title: _filter.isEmpty ? 'No products yet' : 'No products here',
            description: _filter.isEmpty
                ? 'Add your first product and it can be live in the store in minutes.'
                : 'Nothing with this status.',
            action: _filter.isEmpty
                ? BxButton(label: 'Add a product', leadingIcon: Icons.add, onPressed: () => _openForm())
                : null,
          ),
          itemBuilder: (context, p) => _ProductCard(
            product: p,
            onTap: () => _openForm(p),
            onStock: () => _quickStock(p),
            onAvailability: () => _availability(p),
          ),
        ),
        Positioned(
          right: DsSpace.s4,
          bottom: DsSpace.s4,
          child: FloatingActionButton.extended(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('Add product'),
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  final SellerProduct product;
  final VoidCallback onTap;
  final VoidCallback onStock;
  final VoidCallback onAvailability;

  const _ProductCard({required this.product, required this.onTap, required this.onStock, required this.onAvailability});

  BxTone get _tone => switch (product.status) {
        'ACTIVE' => BxTone.success,
        'DRAFT' => BxTone.neutral,
        'OUT_OF_STOCK' => BxTone.warning,
        _ => BxTone.danger,
      };

  String get _statusLabel => switch (product.status) {
        'ACTIVE' => 'Live',
        'DRAFT' => 'Draft',
        'OUT_OF_STOCK' => 'Out of stock',
        'DISCONTINUED' => 'Discontinued',
        _ => product.status,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return BxCard(onTap: onTap,
      child: Column(children: [Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SellerThumb(url: product.image, size: 64),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink),
                ),
                if (product.category.isNotEmpty)
                  Text(product.category, style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
                const SizedBox(height: DsSpace.s2),
                // Wrap, not Row: beside a wide status badge on a small phone the
                // two would not fit on one line.
                Wrap(
                  spacing: DsSpace.s3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      SellerFormat.money(product.price),
                      style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.black, color: c.ink),
                    ),
                    Text('${product.stock} in stock', style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
                  ],
                ),
              ],
            ),
          ),
          BxBadge(_statusLabel, tone: _tone),
        ],
      ),
      const SizedBox(height: DsSpace.s2),
      Wrap(alignment: WrapAlignment.end, children: [
        if (product.status == 'ACTIVE' || product.status == 'OUT_OF_STOCK')
          TextButton.icon(
            onPressed: onAvailability,
            icon: Icon(product.status == 'ACTIVE' ? Icons.toggle_on_outlined : Icons.toggle_off_outlined, size: 17),
            label: Text(product.status == 'ACTIVE' ? 'Switch off' : 'Switch on'),
          ),
        TextButton.icon(onPressed: onStock, icon: const Icon(Icons.inventory_2_outlined, size: 17), label: const Text('Stock')),
        TextButton.icon(onPressed: onTap, icon: const Icon(Icons.edit_outlined, size: 17), label: Text(product.status == 'DRAFT' ? 'Continue' : 'Edit')),
      ]),
      ]),
    );
  }
}

class _StockDialog extends StatefulWidget {
  final SellerApi api;
  final SellerProduct product;
  const _StockDialog({required this.api, required this.product});

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  late final Map<String, TextEditingController> _fields = {
    for (final v in widget.product.variants)
      if (v.id != null) v.id!: TextEditingController(text: '${v.stock}'),
  };
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final field in _fields.values) { field.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    final values = <String, int>{};
    for (final entry in _fields.entries) {
      final stock = int.tryParse(entry.value.text.trim());
      if (stock == null || stock < 0 || stock > 1000000) {
        setState(() => _error = 'Enter a whole stock number from 0 to 1,000,000.');
        return;
      }
      values[entry.key] = stock;
    }
    if (values.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.api.updateStock(values);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Stock · ${widget.product.title}'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      for (final v in widget.product.variants)
        if (v.id != null) Padding(
          padding: const EdgeInsets.only(bottom: DsSpace.s3),
          child: TextField(
            controller: _fields[v.id],
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: [v.color, v.size].where((s) => s.isNotEmpty).join(' / ').isEmpty
                ? 'Default variant' : [v.color, v.size].where((s) => s.isNotEmpty).join(' / ')),
          ),
        ),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ])),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(onPressed: _busy || _fields.isEmpty ? null : _save, child: Text(_busy ? 'Saving…' : 'Save stock')),
    ],
  );
}
