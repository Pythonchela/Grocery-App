import 'package:flutter/material.dart';

import '../seller_api.dart';

/// Paste catalog rows, check the parser's guesses, and import only reviewed rows.
class BulkImportScreen extends StatefulWidget {
  final SellerApi api;
  const BulkImportScreen({super.key, required this.api});

  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  final _raw = TextEditingController();
  List<Map<String, dynamic>>? _rows;
  List<Map<String, dynamic>> _categories = [];
  String _status = 'DRAFT';
  bool _busy = false;
  String? _error;

  bool _ready(Map<String, dynamic> row) {
    final price = double.tryParse('${row['price'] ?? ''}');
    final mrp = double.tryParse('${row['mrp'] ?? ''}');
    return (row['title']?.toString().trim().isNotEmpty ?? false) &&
        price != null && price >= 0 && mrp != null && mrp >= price &&
        _categories.any((c) => c['id'] == row['category_id']);
  }

  @override
  void dispose() { _raw.dispose(); super.dispose(); }

  Future<void> _preview() async {
    if (_raw.text.trim().isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await widget.api.previewImport(_raw.text);
      if (!mounted) return;
      setState(() {
        _categories = (result['categories'] as List? ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();
        _rows = (result['rows'] as List? ?? []).map((e) => {
          ...(e as Map).cast<String, dynamic>(),
          'include': e['importable'] == true,
        }).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _edit(int index) async {
    final row = _rows![index];
    final title = TextEditingController(text: row['title']?.toString() ?? '');
    final price = TextEditingController(text: row['price']?.toString() ?? '');
    final mrp = TextEditingController(text: row['mrp']?.toString() ?? '');
    String? categoryId = row['category_id']?.toString();
    if (!_categories.any((c) => c['id'] == categoryId)) categoryId = null;
    try {
      final saved = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: const Text('Review product'),
        content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, maxLength: 255, decoration: const InputDecoration(labelText: 'Product name')),
          TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling price (₹)')),
          TextField(controller: mrp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'MRP (₹)')),
          DropdownButtonFormField<String>(initialValue: categoryId, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in _categories) DropdownMenuItem(value: c['id']?.toString(), child: Text(c['name']?.toString() ?? ''))],
            onChanged: (v) => update(() => categoryId = v)),
          if (row['issues'] is List && (row['issues'] as List).isNotEmpty)
            ...[(row['issues'] as List).join('\n')].map((s) => Padding(padding: const EdgeInsets.only(top: 8), child: Text(s))),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Use row'))],
      )));
      if (saved != true) return;
      final p = double.tryParse(price.text.trim());
      final m = double.tryParse(mrp.text.trim());
      if (title.text.trim().isEmpty || p == null || p < 0 || m == null || m < p || categoryId == null) {
        setState(() => _error = 'Complete the name, category and valid prices before using this row.');
        return;
      }
      setState(() {
        _rows![index] = {...row, 'title': title.text.trim(), 'price': p, 'mrp': m,
          'category_id': categoryId, 'include': true};
        _error = null;
      });
    } finally { title.dispose(); price.dispose(); mrp.dispose(); }
  }

  Future<void> _commit() async {
    final selected = _rows!.where((r) => r['include'] == true && _ready(r)).toList();
    if (selected.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final count = await widget.api.commitImport([for (final r in selected) {
        'title': r['title'], 'price': r['price'], 'mrp': r['mrp'], 'category_id': r['category_id'],
        if (r['description'] != null) 'description': r['description'],
        if (r['brand'] != null) 'brand': r['brand'],
        if (r['images'] is List) 'images': r['images'],
        if (r['tags'] is List) 'tags': r['tags'],
        if (r['variants'] is List) 'variants': r['variants'],
      }], _status);
      if (mounted) Navigator.pop(context, count);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _rows?.where((r) => r['include'] == true && _ready(r)).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk import')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Paste CSV, spreadsheet rows, JSON, or product descriptions. Review each product before saving.'),
        const SizedBox(height: 12),
        if (_rows == null) ...[
          TextField(controller: _raw, maxLines: 12, maxLength: 500000,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Title, Price, MRP, Category\nCotton kurta, 1299, 2199, Clothing')),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _preview, child: Text(_busy ? 'Reading…' : 'Preview products')),
        ] else ...[
          Text('${_rows!.length} rows found · $selected selected', style: Theme.of(context).textTheme.titleMedium),
          for (var i = 0; i < _rows!.length; i++) Card(child: ListTile(
            leading: Checkbox(value: _rows![i]['include'] == true && _ready(_rows![i]), onChanged: _busy || !_ready(_rows![i]) ? null : (v) => setState(() => _rows![i]['include'] = v == true)),
            title: Text(_rows![i]['title']?.toString().isNotEmpty == true ? '${_rows![i]['title']}' : 'Unnamed product'),
            subtitle: Text('₹${_rows![i]['price'] ?? '—'} · ${_categories.where((c) => c['id'] == _rows![i]['category_id']).map((c) => c['name']).firstOrNull ?? 'Choose category'}'),
            trailing: const Icon(Icons.edit_outlined), onTap: () => _edit(i),
          )),
          DropdownButtonFormField<String>(initialValue: _status,
            decoration: const InputDecoration(labelText: 'Create products as'),
            items: const [DropdownMenuItem(value: 'DRAFT', child: Text('Drafts — review later')),
              DropdownMenuItem(value: 'ACTIVE', child: Text('Live products'))],
            onChanged: _busy ? null : (v) => setState(() => _status = v ?? 'DRAFT')),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy || selected == 0 ? null : _commit,
            child: Text(_busy ? 'Importing…' : 'Import $selected product${selected == 1 ? '' : 's'}')),
          TextButton(onPressed: _busy ? null : () => setState(() => _rows = null), child: const Text('Change pasted data')),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}
