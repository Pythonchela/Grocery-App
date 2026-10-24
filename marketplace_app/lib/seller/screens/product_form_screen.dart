import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../document_picker.dart';
import '../product_validation.dart';
import '../seller_format.dart';
import '../seller_api.dart';
import '../seller_models.dart';
import '../widgets/seller_widgets.dart';
import '../widgets/spec_table_editor.dart';
import 'variant_row.dart';

/// The steps of adding a product, in the order a seller thinks of them.
enum ProductStep { basics, photos, price, delivery, details, review }

const _stepTitles = {
  ProductStep.basics: 'Basics',
  ProductStep.photos: 'Photos',
  ProductStep.price: 'Price & stock',
  ProductStep.delivery: 'Delivery',
  ProductStep.details: 'Details',
  ProductStep.review: 'Review',
};

const _deliveryChoices = [
  ('', 'Let the marketplace decide'),
  ('instant', 'Quick: made or kept ready nearby'),
  ('parcel', 'Courier parcel'),
  ('heavy', 'Heavy or bulky'),
];

/// Add a product one step at a time, or edit one of the seller's own.
///
/// Only four things are needed to keep a draft: a name, a category, the MRP
/// and the selling price. Everything else helps shoppers trust and find the
/// product, and can be filled in later. A new product, or one still a draft, is
/// saved to the server as a draft whenever the seller moves on or taps "Save
/// draft", so nothing typed is lost; it goes live only from the last step.
///
/// Pops with `true` when something was saved, so the list behind it reloads.
class ProductFormScreen extends StatefulWidget {
  final SellerApi api;
  final DocumentPicker picker;

  /// Null to create; a product to edit.
  final SellerProduct? product;

  const ProductFormScreen(
      {super.key, required this.api, required this.picker, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  static const _maxPhotos = 8;
  static const _maxFeatures = 8;

  late final _title = TextEditingController(text: widget.product?.title ?? '');
  late final _description =
      TextEditingController(text: widget.product?.description ?? '');
  late final _brand = TextEditingController(text: widget.product?.brand ?? '');
  late final _mrp = TextEditingController(text: _plain(widget.product?.mrp));
  late final _price =
      TextEditingController(text: _plain(widget.product?.price));

  // Packed weight (grams) and size (cm): what couriers charge on.
  late final _weight = TextEditingController(text: widget.product?.weightGrams?.toString() ?? '');
  late final _length = TextEditingController(text: widget.product?.lengthCm?.toString() ?? '');
  late final _width = TextEditingController(text: widget.product?.widthCm?.toString() ?? '');
  late final _height = TextEditingController(text: widget.product?.heightCm?.toString() ?? '');
  late final _prep = TextEditingController(text: widget.product?.prepMinutes?.toString() ?? '');

  late final _specs =
      SpecTableController(widget.product?.specifications ?? const []);
  late final Map<String, TextEditingController> _manufacturer = {
    for (final key in sellerManufacturerFields.keys)
      key: TextEditingController(text: widget.product?.manufacturer[key] ?? ''),
  };
  late final List<TextEditingController> _features = [
    for (final f in widget.product?.features ?? const <String>[]) TextEditingController(text: f),
  ];

  late String? _categoryId = widget.product?.categoryId.isEmpty == false
      ? widget.product!.categoryId
      : null;
  late String _status = widget.product?.status.isNotEmpty == true
      ? widget.product!.status
      : 'DRAFT';
  late String _delivery = widget.product?.deliveryProfile ?? '';
  late bool _cod = widget.product?.codAvailable ?? true;
  late final List<String> _photos = [...?widget.product?.images];
  late final List<VariantRow> _variants =
      (widget.product?.variants.isNotEmpty == true)
          ? widget.product!.variants.map(VariantRow.fromVariant).toList()
          : [VariantRow(color: 'Standard', size: 'Free Size', stock: '')];

  /// Whether the product comes in several sizes or colours. A single plain item
  /// has one hidden variant and just a stock figure.
  late bool _hasVariants = _variants.length > 1 ||
      (_variants.length == 1 &&
          (_variants.first.color.text.trim().isNotEmpty &&
                  _variants.first.color.text.trim() != 'Standard' ||
              _variants.first.size.text.trim().isNotEmpty &&
                  _variants.first.size.text.trim() != 'Free Size'));

  List<ProductCategory> _categories = [];
  bool _loadingCategories = true;
  String? _categoriesError;

  /// Set once the product exists on the server (a saved draft, or an edit).
  late String? _productId = widget.product?.id;
  bool _everSaved = false;
  late String _snapshot;

  ProductStep _step = ProductStep.basics;
  final _scroll = ScrollController();

  bool _saving = false;
  int _uploading = 0;
  String? _error;
  String _errorTitle = 'Could not save';
  String? _notice;
  Map<String, String> _errors = {};

  bool get _isEdit => widget.product != null;
  bool get _busy => _saving || _uploading > 0;

  /// New, or still a draft: saved as a draft on the way, published at the end.
  /// A product already on sale is only changed when the seller says "Save changes".
  bool get _draftMode => !_isEdit || widget.product!.status == 'DRAFT';

  static String _plain(double? v) {
    if (v == null || v == 0) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _snapshot = _signature();
    if (_isEdit) _step = _firstIncomplete();
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _description,
      _brand,
      _mrp,
      _price,
      _weight,
      _length,
      _width,
      _height,
      _prep,
      ..._features,
      ..._manufacturer.values
    ]) {
      c.dispose();
    }
    _specs.dispose();
    _scroll.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoriesError = null;
    });
    try {
      final list = await widget.api.categories();
      if (!mounted) return;
      setState(() {
        _categories = list;
        _loadingCategories = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _categoriesError = e.message;
          _loadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _categoriesError = 'Could not load categories.';
          _loadingCategories = false;
        });
      }
    }
  }

  String? get _categoryName {
    for (final c in _categories) {
      if (c.id == _categoryId) return c.name;
    }
    return widget.product?.category;
  }

  // ── What has been typed ───────────────────────────────────────────────────

  ProductInput _input(String status) => ProductInput(
        title: _title.text.trim(),
        description: _description.text.trim(),
        brand: _brand.text.trim(),
        categoryId: _categoryId ?? '',
        // A draft may be saved before it has a price; going live is checked
        // separately, and the server refuses a live product priced at zero.
        mrp: parseMoney(_mrp.text) ?? 0,
        price: parseMoney(_price.text) ?? 0,
        status: status,
        images: List.of(_photos),
        variants: [for (final v in _variants) v.toVariant()],
        weightGrams: int.tryParse(_weight.text.trim()),
        lengthCm: int.tryParse(_length.text.trim()),
        widthCm: int.tryParse(_width.text.trim()),
        heightCm: int.tryParse(_height.text.trim()),
        deliveryProfile: _delivery,
        prepMinutes: int.tryParse(_prep.text.trim()),
        codAvailable: _cod,
        features: [
          for (final f in _features)
            if (f.text.trim().isNotEmpty) f.text.trim(),
        ],
        specifications: _specs.toJson(),
        manufacturer: {
          for (final e in _manufacturer.entries) e.key: e.value.text.trim(),
        },
      );

  String _signature() => jsonEncode(_input(_status).toJson());

  bool get _dirty => _signature() != _snapshot;

  bool get _hasAnything =>
      _title.text.trim().isNotEmpty || _photos.isNotEmpty || _categoryId != null;

  // ── Checking each step ────────────────────────────────────────────────────

  Map<String, String> _basicsErrors() {
    final errors = <String, String>{};
    final title = _title.text.trim();
    if (title.isEmpty) {
      errors['title'] = 'Enter a product name.';
    } else if (title.length > 255) {
      errors['title'] = 'That name is too long (255 characters at most).';
    }
    if (_categoryId == null || _categoryId!.isEmpty) {
      errors['category_id'] = 'Choose a category.';
    }
    return errors;
  }

  /// Everything the product form can be wrong about, as the API keys it.
  Map<String, String> _allErrors(String status) {
    final errors = ProductValidation.validate(
      title: _title.text,
      categoryId: _categoryId,
      mrp: _mrp.text,
      price: _price.text,
      status: status,
      photoCount: _photos.length,
      variants: [
        for (final v in _variants)
          VariantDraft(
              stock: v.stock.text,
              sku: v.sku.text,
              price: v.price.text,
              mrp: v.mrp.text),
      ],
    );
    errors.addAll(_packingErrors());
    return errors;
  }

  static const _stepOfKey = {
    'title': ProductStep.basics,
    'category_id': ProductStep.basics,
    'brand': ProductStep.basics,
    'description': ProductStep.basics,
    'photos': ProductStep.photos,
    'images': ProductStep.photos,
    'mrp': ProductStep.price,
    'price': ProductStep.price,
    'variants': ProductStep.price,
    'weight_grams': ProductStep.delivery,
    'length_cm': ProductStep.delivery,
    'width_cm': ProductStep.delivery,
    'height_cm': ProductStep.delivery,
    'prep_minutes': ProductStep.delivery,
    'delivery_profile': ProductStep.delivery,
    'specifications': ProductStep.details,
    'manufacturer': ProductStep.details,
    'features': ProductStep.details,
  };

  ProductStep _stepFor(String key) {
    final root = key.split('.').first;
    return _stepOfKey[root] ?? ProductStep.review;
  }

  Map<String, String> _errorsFor(ProductStep step) {
    final all = _allErrors(_status == 'DRAFT' ? 'DRAFT' : _status);
    switch (step) {
      case ProductStep.basics:
        return _basicsErrors();
      case ProductStep.price:
      case ProductStep.delivery:
        return {
          for (final e in all.entries)
            if (_stepFor(e.key) == step) e.key: e.value,
          if (step == ProductStep.delivery) ..._prepErrors(),
        };
      case ProductStep.photos:
      case ProductStep.details:
      case ProductStep.review:
        return {};
    }
  }

  Map<String, String> _prepErrors() {
    final text = _prep.text.trim();
    if (text.isEmpty) return {};
    final n = int.tryParse(text);
    return n == null || n < 0 || n > 1440
        ? {'prep_minutes': 'Enter whole minutes, 0 to 1440.'}
        : {};
  }

  /// Weight and size must be whole numbers within what a courier can carry;
  /// all of them may be left empty.
  Map<String, String> _packingErrors() {
    final errors = <String, String>{};

    String? check(TextEditingController c, int max) {
      final text = c.text.trim();
      if (text.isEmpty) return null;
      final n = int.tryParse(text);
      return n == null || n < 1 || n > max ? 'Enter a whole number from 1 to $max.' : null;
    }

    final weight = check(_weight, 200000);
    if (weight != null) errors['weight_grams'] = weight;
    final length = check(_length, 500);
    if (length != null) errors['length_cm'] = length;
    final width = check(_width, 500);
    if (width != null) errors['width_cm'] = width;
    final height = check(_height, 500);
    if (height != null) errors['height_cm'] = height;
    errors.addAll(_prepErrors());
    return errors;
  }

  bool _isDone(ProductStep step) => switch (step) {
        ProductStep.basics => _basicsErrors().isEmpty,
        ProductStep.photos => _photos.isNotEmpty,
        ProductStep.price => (parseMoney(_price.text) ?? 0) > 0 &&
            (parseMoney(_mrp.text) ?? 0) > 0 &&
            _errorsFor(ProductStep.price).isEmpty &&
            _variants.every((v) => v.stock.text.trim().isNotEmpty),
        ProductStep.delivery => _weight.text.trim().isNotEmpty,
        ProductStep.details => _description.text.trim().isNotEmpty ||
            _features.any((f) => f.text.trim().isNotEmpty) ||
            !_specs.isEmpty ||
            _manufacturer.values.any((c) => c.text.trim().isNotEmpty),
        ProductStep.review => false,
      };

  ProductStep _firstIncomplete() {
    for (final s in [ProductStep.basics, ProductStep.price, ProductStep.photos]) {
      if (!_isDone(s)) return s;
    }
    return ProductStep.review;
  }

  // ── Moving between steps ──────────────────────────────────────────────────

  int get _stepIndex => ProductStep.values.indexOf(_step);

  void _show(ProductStep step) {
    setState(() {
      _step = step;
      _notice = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _next() async {
    final errors = _errorsFor(_step);
    if (errors.isNotEmpty) {
      setState(() {
        _errors = {..._errors, ...errors};
        _errorTitle = 'Check this step';
        _error = 'Fix the highlighted fields to continue.';
      });
      _scrollTop();
      return;
    }
    setState(() {
      _error = null;
      for (final k in errors.keys) {
        _errors.remove(k);
      }
    });

    // Moving on keeps what was typed: a draft is saved quietly in the background.
    if (_draftMode && _basicsErrors().isEmpty && !_busy) {
      unawaited(_save('DRAFT', quiet: true));
    }
    _show(ProductStep.values[_stepIndex + 1]);
  }

  void _scrollTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _back() {
    if (_stepIndex > 0) _show(ProductStep.values[_stepIndex - 1]);
  }

  // ── Photos ────────────────────────────────────────────────────────────────

  Future<void> _addPhoto() async {
    if (_photos.length + _uploading >= _maxPhotos) {
      setState(() => _errors = {
            ..._errors,
            'photos': 'You can add up to $_maxPhotos photos.'
          });
      return;
    }

    final PickedDocument? file;
    try {
      file = await widget.picker.pick(extensions: PhotoRules.allowedExtensions);
    } catch (_) {
      if (mounted) {
        setState(() => _errors = {
              ..._errors,
              'photos': 'Could not open the photo picker.'
            });
      }
      return;
    }
    if (file == null || !mounted) return;

    final problem = PhotoRules.problemWith(file);
    if (problem != null) {
      setState(() => _errors = {..._errors, 'photos': problem});
      return;
    }

    setState(() {
      _uploading++;
      _errors = {..._errors}..remove('photos');
    });
    try {
      final url = await widget.api.uploadImage(file);
      if (mounted) setState(() => _photos.add(url));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _errors = {
              ..._errors,
              'photos': e.fieldError('file') ?? e.message
            });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errors = {
              ..._errors,
              'photos': 'Upload failed. Check your connection and try again.'
            });
      }
    } finally {
      if (mounted) setState(() => _uploading--);
    }
  }

  // ── Category ──────────────────────────────────────────────────────────────

  Future<void> _pickCategory() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in _categories)
              ListTile(
                title: Text(c.name),
                trailing: c.id == _categoryId ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, c.id),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      setState(() {
        _categoryId = chosen;
        _errors = {..._errors}..remove('category_id');
      });
    }
  }

  Future<void> _requestCategory() async {
    final name = TextEditingController();
    final reason = TextEditingController();
    try {
      final existing = await widget.api.categoryRequests();
      if (!mounted) return;
      final submit = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Request a category'),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Use an existing category if one fits. New categories need admin approval.'),
          TextField(controller: name, maxLength: 120, decoration: const InputDecoration(labelText: 'Category name')),
          TextField(controller: reason, maxLength: 1000, maxLines: 2, decoration: const InputDecoration(labelText: 'What will you sell?')),
          if (existing.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final row in existing.take(5)) Align(alignment: Alignment.centerLeft,
              child: Text('${row['name']} · ${row['status']}')),
          ],
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send request')),
        ],
      ));
      if (submit != true || name.text.trim().length < 2) return;
      await widget.api.requestCategory(name.text.trim(), reason.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category request sent to admin.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      name.dispose(); reason.dispose();
    }
  }

  // ── Saving ────────────────────────────────────────────────────────────────

  /// After a save the server has given every variant an id. Adopting them means
  /// the next save edits those rows instead of adding the same ones again.
  void _adoptVariants(List<SellerVariant> saved) {
    if (saved.isEmpty) return;
    final old = List.of(_variants);
    setState(() {
      _variants
        ..clear()
        ..addAll(saved.map(VariantRow.fromVariant));
    });
    for (final v in old) {
      v.dispose();
    }
  }

  /// Saves the product with [status]. A `DRAFT` save needs only a name and a
  /// category; anything else is checked in full first. [quiet] is the background
  /// save when moving on: it never blocks, and only mentions a failure.
  Future<bool> _save(String status, {bool quiet = false}) async {
    if (_saving) return false;

    final errors = status == 'DRAFT' ? {..._basicsErrors(), ..._packingErrors()} : _allErrors(status);

    if (errors.isNotEmpty) {
      if (quiet) return false;
      setState(() {
        _errors = errors;
        _errorTitle = 'Could not save';
        _error = 'Fix the highlighted fields and try again.';
        _step = _stepFor(errors.keys.first);
      });
      _scrollTop();
      return false;
    }

    setState(() {
      _saving = true;
      if (!quiet) _error = null;
    });
    try {
      final input = _input(status);
      final saved = _productId == null
          ? await widget.api.createProduct(input)
          : await widget.api.updateProduct(_productId!, input);
      if (!mounted) return true;
      _productId = saved.id;
      _everSaved = true;
      _status = status;
      _adoptVariants(saved.variants);
      setState(() {
        _saving = false;
        _snapshot = _signature();
        _errors = {};
        _error = null;
        _notice = quiet ? 'Draft saved' : (status == 'DRAFT' ? 'Draft saved. Come back to it any time from Products.' : null);
      });
      if (!quiet) _scrollTop();
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      final fieldErrors = {
        for (final f in (e.errors ?? {}).entries) f.key: f.value.first
      };
      setState(() {
        _saving = false;
        if (quiet) {
          _notice = 'Could not save the draft yet. What you typed is kept here.';
        } else {
          _errors = fieldErrors;
          _errorTitle = 'Could not save';
          _error = e.errors == null ? e.message : 'Fix the highlighted fields and try again.';
          if (fieldErrors.isNotEmpty) _step = _stepFor(fieldErrors.keys.first);
        }
      });
      if (!quiet) _scrollTop();
      return false;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        if (quiet) {
          _notice = 'Could not save the draft yet. What you typed is kept here.';
        } else {
          _error = 'Could not reach the server. Check your connection and try again.';
        }
      });
      return false;
    }
  }

  Future<void> _saveDraft() => _save('DRAFT');

  Future<void> _publish() async {
    if (await _save('ACTIVE') && mounted) Navigator.pop(context, true);
  }

  Future<void> _saveChanges() async {
    if (await _save(_status) && mounted) Navigator.pop(context, true);
  }

  /// Leaving with unsaved changes asks first; a draft offers to keep them.
  Future<void> _leave() async {
    if (_busy) return;

    if (!_dirty || !_hasAnything) {
      Navigator.pop(context, _everSaved);
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_draftMode ? 'Save this as a draft?' : 'Discard your changes?'),
        content: Text(_draftMode
            ? 'You can finish it later from the Drafts filter in Products.'
            : 'The changes you made to this product have not been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(_draftMode ? 'Discard' : 'Discard changes')),
          if (_draftMode) FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save draft')),
        ],
      ),
    );
    if (!mounted) return;

    if (choice == 'discard') {
      Navigator.pop(context, _everSaved);
    } else if (choice == 'save') {
      if (await _save('DRAFT') && mounted) Navigator.pop(context, true);
    }
  }

  // ── Removing ──────────────────────────────────────────────────────────────

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this product?'),
        content: const Text(
            'It will be removed from your shop for good. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.api.deleteProduct(_productId!);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);

      // A product someone has bought cannot be deleted (their order history
      // points at it). Offer the thing that is actually meant: taking it off sale.
      if (e.status == 422) {
        final discontinue = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('This product has been ordered'),
            content: Text(
                '${e.message}\n\nDiscontinue it instead? It will be hidden from shoppers.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Discontinue')),
            ],
          ),
        );
        if (discontinue == true && mounted) await _discontinue();
      } else {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Could not reach the server. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _discontinue() async {
    setState(() => _saving = true);
    try {
      await widget.api.setProductStatus(_productId!, 'DISCONTINUED');
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not reach the server. Try again.';
        });
      }
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  Map<String, String> _variantErrors(int i) => {
        for (final f in ['stock', 'sku', 'price', 'mrp'])
          if (_errors['variants.$i.$f'] != null) f: _errors['variants.$i.$f']!,
      };

  Widget _gap([double h = DsSpace.s4]) => SizedBox(height: h);

  Widget _optional(String text) => Padding(
        padding: const EdgeInsets.only(bottom: DsSpace.s3),
        child: Text(text, style: TextStyle(fontSize: DsText.sm, color: context.ds.inkMuted)),
      );

  List<Widget> _basicsStep() => [
        const SellerSectionTitle('Basics',
            subtitle: 'Only the name and category are needed to start. You can save a draft at any step.'),
        BxField(label: 'Product name', controller: _title, error: _errors['title'], enabled: !_busy),
        _gap(),
        _CategoryField(
          name: _categoryName,
          loading: _loadingCategories,
          loadError: _categoriesError,
          error: _errors['category_id'],
          enabled: !_busy && _categories.isNotEmpty,
          onTap: _pickCategory,
          onRetry: _loadCategories,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _requestCategory,
            icon: const Icon(Icons.add),
            label: const Text('Request a new category'),
          ),
        ),
        _gap(),
        BxField(label: 'Brand (optional)', controller: _brand, error: _errors['brand'], enabled: !_busy),
        _gap(),
        BxField(
          label: 'Description (optional)',
          controller: _description,
          maxLines: 4,
          error: _errors['description'],
          helper: widget.product?.hasFormattedDescription == true
              ? 'This description has formatting (bold, lists). Changing it here replaces that with plain text.'
              : 'What it is, what it is made of, what makes it good.',
          enabled: !_busy,
        ),
      ];

  List<Widget> _photosStep() {
    final c = context.ds;
    return [
      const SellerSectionTitle('Photos',
          subtitle: 'The first photo is the cover. JPG, PNG or WebP, up to 10 MB. You need at least one to go live.'),
      SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < _photos.length; i++)
              _PhotoTile(
                url: _photos[i],
                isCover: i == 0,
                onRemove: _busy ? null : () => setState(() => _photos.removeAt(i)),
              ),
            for (var i = 0; i < _uploading; i++) const _UploadingTile(),
            _AddPhotoTile(onTap: _busy ? null : _addPhoto),
          ],
        ),
      ),
      if (_errors['photos'] != null) ...[
        const SizedBox(height: DsSpace.s2),
        Text(_errors['photos']!, style: TextStyle(fontSize: DsText.xs, color: c.danger)),
      ],
      _gap(),
      _optional('Clear, well-lit photos on a plain background sell best. Show the item from the front, the back and close up.'),
    ];
  }

  List<Widget> _priceStep() {
    final price = parseMoney(_price.text);
    final mrp = parseMoney(_mrp.text);
    final off = (price != null && mrp != null && mrp > 0 && price > 0 && price <= mrp)
        ? ((mrp - price) * 100 / mrp).round()
        : null;

    return [
      const SellerSectionTitle('Price & stock', subtitle: 'What shoppers pay, and the printed price it is discounted from.'),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: BxField(
              label: 'MRP (₹)',
              controller: _mrp,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              error: _errors['mrp'],
              onChanged: (_) => setState(() {}),
              enabled: !_busy,
            ),
          ),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: BxField(
              label: 'Selling price (₹)',
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              error: _errors['price'],
              onChanged: (_) => setState(() {}),
              enabled: !_busy,
            ),
          ),
        ],
      ),
      if (off != null && off > 0)
        Padding(
          padding: const EdgeInsets.only(top: DsSpace.s2),
          child: BxBadge('$off% off', tone: BxTone.success),
        ),
      _gap(DsSpace.s5),
      SwitchListTile(
        key: const Key('has-variants'),
        contentPadding: EdgeInsets.zero,
        title: const Text('It comes in sizes or colours'),
        subtitle: Text(_variants.length > 1
            ? 'Remove the extra variants to switch this off.'
            : 'Off: one item, one stock figure. On: each size or colour gets its own stock.'),
        value: _hasVariants,
        onChanged: _busy || _variants.length > 1
            ? null
            : (on) => setState(() {
                  _hasVariants = on;
                  if (!on && _variants.length == 1) {
                    final v = _variants.first;
                    if (v.color.text.trim().isEmpty) v.color.text = 'Standard';
                    if (v.size.text.trim().isEmpty) v.size.text = 'Free Size';
                  }
                }),
      ),
      _gap(DsSpace.s3),
      if (_errors['variants'] != null) ...[
        BxAlert(_errors['variants']!, tone: BxTone.danger),
        const SizedBox(height: DsSpace.s3),
      ],
      if (!_hasVariants) ...[
        BxField(
          label: 'How many do you have?',
          controller: _variants.first.stock,
          keyboardType: TextInputType.number,
          error: _errors['variants.0.stock'],
          enabled: !_busy,
        ),
        _gap(DsSpace.s3),
        BxField(
          label: 'SKU (optional)',
          helper: 'Your own code for this item.',
          controller: _variants.first.sku,
          error: _errors['variants.0.sku'],
          enabled: !_busy,
        ),
      ] else ...[
        for (var i = 0; i < _variants.length; i++) ...[
          VariantCard(
            key: ObjectKey(_variants[i]),
            index: i,
            row: _variants[i],
            errors: _variantErrors(i),
            enabled: !_busy,
            onRemove: _variants.length > 1
                ? () => setState(() => _variants.removeAt(i).dispose())
                : null,
          ),
          const SizedBox(height: DsSpace.s3),
        ],
        BxButton(
          label: 'Add a variant',
          leadingIcon: Icons.add,
          variant: BxButtonVariant.secondary,
          size: BxButtonSize.sm,
          onPressed: _busy ? null : () => setState(() => _variants.add(VariantRow(stock: ''))),
        ),
      ],
    ];
  }

  List<Widget> _deliveryStep() => [
        const SellerSectionTitle('Delivery',
            subtitle: 'Couriers charge by weight and size. Without a weight we assume 500 g, which can make delivery prices wrong.'),
        BxField(
          label: 'Weight (grams)',
          hint: 'e.g. 500',
          controller: _weight,
          keyboardType: TextInputType.number,
          error: _errors['weight_grams'],
          onChanged: (_) => setState(() {}),
          enabled: !_busy,
        ),
        _gap(DsSpace.s3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BxField(label: 'Length (cm)', controller: _length, keyboardType: TextInputType.number, error: _errors['length_cm'], enabled: !_busy),
            ),
            const SizedBox(width: DsSpace.s2),
            Expanded(
              child: BxField(label: 'Width (cm)', controller: _width, keyboardType: TextInputType.number, error: _errors['width_cm'], enabled: !_busy),
            ),
            const SizedBox(width: DsSpace.s2),
            Expanded(
              child: BxField(label: 'Height (cm)', controller: _height, keyboardType: TextInputType.number, error: _errors['height_cm'], enabled: !_busy),
            ),
          ],
        ),
        _gap(DsSpace.s5),
        BxField(
          label: 'Time to get it ready (minutes, optional)',
          helper: 'Shown to shoppers as the preparation time. Leave empty to use the category\'s.',
          controller: _prep,
          keyboardType: TextInputType.number,
          error: _errors['prep_minutes'],
          enabled: !_busy,
        ),
        _gap(DsSpace.s4),
        Text('How is it delivered?', style: TextStyle(fontSize: DsText.sm, fontWeight: DsWeight.bold, color: context.ds.ink)),
        const SizedBox(height: DsSpace.s2),
        Wrap(
          spacing: DsSpace.s2,
          runSpacing: DsSpace.s2,
          children: [
            for (final (value, label) in _deliveryChoices)
              ChoiceChip(
                label: Text(label),
                selected: _delivery == value,
                onSelected: _busy ? null : (_) => setState(() => _delivery = value),
              ),
          ],
        ),
        _gap(DsSpace.s3),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow cash on delivery'),
          subtitle: const Text('Turn off for items you only want to sell prepaid.'),
          value: _cod,
          onChanged: _busy ? null : (on) => setState(() => _cod = on),
        ),
      ];

  List<Widget> _detailsStep() => [
        const SellerSectionTitle('Details',
            subtitle: 'All optional. This is what shoppers read before they buy.'),
        Text('Highlights', style: TextStyle(fontSize: DsText.sm, fontWeight: DsWeight.bold, color: context.ds.ink)),
        const SizedBox(height: DsSpace.s1),
        _optional('Short lines shown under the price, like "Pure brass" or "Free gift box".'),
        for (var i = 0; i < _features.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: DsSpace.s2),
            child: Row(children: [
              Expanded(child: BxField(label: 'Highlight ${i + 1}', controller: _features[i], enabled: !_busy)),
              IconButton(
                tooltip: 'Remove highlight',
                onPressed: _busy ? null : () => setState(() => _features.removeAt(i).dispose()),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
        if (_features.length < _maxFeatures)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => setState(() => _features.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: const Text('Add a highlight'),
            ),
          ),
        _gap(DsSpace.s4),
        const SellerSectionTitle('Specifications', subtitle: 'Shown to shoppers under "All details".'),
        SpecTableEditor(controller: _specs, enabled: !_busy),
        _gap(DsSpace.s5),
        const SellerSectionTitle('Manufacturer info', subtitle: 'Who made and packed it. Leave out what does not apply.'),
        for (final e in sellerManufacturerFields.entries) ...[
          BxField(
            label: e.value,
            controller: _manufacturer[e.key],
            maxLines: e.key.endsWith('address') ? 2 : 1,
            enabled: !_busy,
          ),
          const SizedBox(height: DsSpace.s3),
        ],
        _gap(DsSpace.s2),
        const BxAlert(
          'Customisable choices (portions, add-ons), 360° views and SEO text are set from the web dashboard.',
          tone: BxTone.info,
        ),
      ];

  /// What would stop this going live, and what is only a suggestion.
  List<(ProductStep, String, bool)> _checklist() {
    final blocking = _allErrors('ACTIVE');
    return [
      (ProductStep.basics, 'Name and category', _basicsErrors().isEmpty),
      (ProductStep.photos, 'At least one photo', _photos.isNotEmpty),
      (
        ProductStep.price,
        'Price and MRP',
        !blocking.keys.any((k) => k == 'mrp' || k == 'price')
      ),
      (
        ProductStep.price,
        'Stock for every variant',
        !blocking.keys.any((k) => k == 'variants' || k.startsWith('variants.'))
      ),
    ];
  }

  List<Widget> _reviewStep() {
    final c = context.ds;
    final items = _checklist();
    final ready = items.every((i) => i.$3);
    final price = parseMoney(_price.text);
    final mrp = parseMoney(_mrp.text);
    final stock = _variants.fold<int>(0, (s, v) => s + (int.tryParse(v.stock.text.trim()) ?? 0));
    final statuses = [
      ('ACTIVE', 'Live'),
      ('OUT_OF_STOCK', 'Out of stock'),
      ('DISCONTINUED', 'Discontinued'),
    ];

    return [
      const SellerSectionTitle('Review'),
      BxCard(
        child: Row(children: [
          SellerThumb(url: _photos.isEmpty ? null : _photos.first, size: 64),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title.text.trim().isEmpty ? 'Untitled product' : _title.text.trim(),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink)),
              Text(_categoryName ?? 'No category yet', style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
              const SizedBox(height: DsSpace.s1),
              Text(
                price == null || price <= 0
                    ? 'No price yet'
                    : '${SellerFormat.money(price)}${mrp != null && mrp > price ? ' (MRP ${SellerFormat.money(mrp)})' : ''} · $stock in stock',
                style: TextStyle(fontSize: DsText.sm, color: c.ink),
              ),
            ]),
          ),
        ]),
      ),
      _gap(DsSpace.s4),
      Text(ready ? 'Ready to go live' : 'Still needed to go live',
          style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: ready ? c.success : c.ink)),
      const SizedBox(height: DsSpace.s2),
      for (final (step, label, ok) in items)
        ListTile(
          key: Key('check-${label.replaceAll(' ', '-')}'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(ok ? Icons.check_circle : Icons.error_outline, color: ok ? c.success : c.warning),
          title: Text(label),
          trailing: ok ? null : const Icon(Icons.chevron_right),
          onTap: ok ? null : () => _show(step),
        ),
      if (stock == 0)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(Icons.info_outline, color: c.inkMuted),
          title: const Text('You have 0 in stock, so shoppers will see it as sold out'),
          subtitle: const Text('Suggested, not required'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _show(ProductStep.price),
        ),
      if (_weight.text.trim().isEmpty)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(Icons.info_outline, color: c.inkMuted),
          title: const Text('Add a weight so delivery prices are right'),
          subtitle: const Text('Suggested, not required'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _show(ProductStep.delivery),
        ),
      if (!_draftMode) ...[
        _gap(DsSpace.s4),
        const SellerSectionTitle('Status', subtitle: 'Live products appear in the store.'),
        Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
          for (final (value, label) in statuses)
            ChoiceChip(
              label: Text(label),
              selected: _status == value,
              onSelected: _busy ? null : (_) => setState(() => _status = value),
            ),
        ]),
        if (_errors['status'] != null)
          Padding(
            padding: const EdgeInsets.only(top: DsSpace.s2),
            child: Text(_errors['status']!, style: TextStyle(fontSize: DsText.xs, color: c.danger)),
          ),
      ],
      if (_productId != null) ...[
        _gap(DsSpace.s6),
        Center(
          child: BxButton(
            label: 'Delete product',
            leadingIcon: Icons.delete_outline,
            variant: BxButtonVariant.dangerSoft,
            size: BxButtonSize.sm,
            onPressed: _busy ? null : _delete,
          ),
        ),
      ],
    ];
  }

  Widget _stepHeader() {
    final c = context.ds;
    final total = ProductStep.values.length;

    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s3, DsSpace.s4, DsSpace.s2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Step ${_stepIndex + 1} of $total · ${_stepTitles[_step]}',
            style: TextStyle(fontSize: DsText.xs, fontWeight: DsWeight.bold, color: c.inkMuted)),
        const SizedBox(height: DsSpace.s2),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: (_stepIndex + 1) / total, minHeight: 4, color: c.accent, backgroundColor: c.line),
        ),
        const SizedBox(height: DsSpace.s2),
        // Six chips, so a plain scrolling row: every one is built and reachable.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.1,
            child: Row(
            children: [
              for (final s in ProductStep.values)
                Padding(
                  padding: const EdgeInsets.only(right: DsSpace.s2),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    key: Key('step-${s.name}'),
                    avatar: _isDone(s) && s != _step ? Icon(Icons.check, size: 16, color: c.success) : null,
                    label: Text(_stepTitles[s]!),
                    selected: s == _step,
                    onSelected: _busy ? null : (_) => _show(s),
                  ),
                ),
            ],
          ),
          ),
        ),
      ]),
    );
  }

  Widget _bottomBar() {
    final c = context.ds;
    final last = _step == ProductStep.review;

    // The main action: Next on the way through; on the last step, publish (new
    // and drafts) or save (a product already on sale).
    final (String primaryLabel, VoidCallback primary) = last
        ? (_draftMode ? ('Publish product', _publish) : ('Save changes', _saveChanges))
        : ('Next', _next);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3, vertical: DsSpace.s2),
        decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
        child: Row(children: [
          if (_stepIndex > 0) ...[
            BxButton(
              key: const Key('step-back'),
              label: 'Back',
              size: BxButtonSize.sm,
              variant: BxButtonVariant.ghost,
              onPressed: _busy ? null : _back,
            ),
            const SizedBox(width: DsSpace.s2),
          ],
          if (_draftMode) ...[
            Expanded(
              child: BxButton(
                key: const Key('save-draft'),
                label: 'Save draft',
                size: BxButtonSize.sm,
                variant: BxButtonVariant.secondary,
                onPressed: _busy ? null : _saveDraft,
              ),
            ),
            const SizedBox(width: DsSpace.s2),
          ],
          Expanded(
            child: BxButton(
              key: const Key('step-primary'),
              label: primaryLabel,
              size: BxButtonSize.sm,
              loading: _saving && last,
              onPressed: _busy ? null : primary,
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    final body = switch (_step) {
      ProductStep.basics => _basicsStep(),
      ProductStep.photos => _photosStep(),
      ProductStep.price => _priceStep(),
      ProductStep.delivery => _deliveryStep(),
      ProductStep.details => _detailsStep(),
      ProductStep.review => _reviewStep(),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit product' : 'Add product'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: _leave),
        ),
        body: Column(
          children: [
            _stepHeader(),
            Divider(height: 1, color: c.line),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(DsSpace.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_notice != null) ...[
                      BxAlert(_notice!, tone: BxTone.success),
                      const SizedBox(height: DsSpace.s3),
                    ],
                    if (_error != null) ...[
                      BxAlert(_error!, title: _errorTitle, tone: BxTone.danger),
                      const SizedBox(height: DsSpace.s4),
                    ],
                    ...body,
                    const SizedBox(height: DsSpace.s6),
                  ],
                ),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }
}

class _CategoryField extends StatelessWidget {
  final String? name;
  final bool loading;
  final String? loadError;
  final String? error;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  const _CategoryField({
    required this.name,
    required this.loading,
    required this.loadError,
    required this.error,
    required this.enabled,
    required this.onTap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category',
            style: TextStyle(
                fontSize: DsText.xs,
                fontWeight: DsWeight.bold,
                color: c.inkMuted)),
        const SizedBox(height: DsSpace.s1 + 2),
        InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: DsRadius.controlAll,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: DsSpace.s4, vertical: DsSpace.s4),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: DsRadius.controlAll,
              border:
                  Border.all(color: error != null ? c.danger : c.lineStrong),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    loading ? 'Loading…' : (name ?? 'Choose a category'),
                    style: TextStyle(
                        fontSize: DsText.base,
                        color: name == null ? c.inkSubtle : c.ink),
                  ),
                ),
                Icon(Icons.expand_more, color: c.inkSubtle),
              ],
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: DsSpace.s1),
          Text(error!, style: TextStyle(fontSize: DsText.xs, color: c.danger)),
        ],
        if (loadError != null) ...[
          const SizedBox(height: DsSpace.s1),
          Row(
            children: [
              Expanded(
                  child: Text(loadError!,
                      style: TextStyle(fontSize: DsText.xs, color: c.danger))),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ],
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String url;
  final bool isCover;
  final VoidCallback? onRemove;

  const _PhotoTile(
      {required this.url, required this.isCover, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Padding(
      padding: const EdgeInsets.only(right: DsSpace.s2),
      child: Stack(
        children: [
          SellerThumb(url: url, size: 84),
          if (isCover)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: c.inverse.withValues(alpha: 0.75),
                    borderRadius: DsRadius.chipAll),
                child: Text('Cover',
                    style: TextStyle(
                        fontSize: DsText.x2xs,
                        color: c.inkInverse,
                        fontWeight: DsWeight.bold)),
              ),
            ),
          Positioned(
            top: 0,
            right: 0,
            child: Semantics(
              button: true,
              label: 'Remove photo',
              child: InkWell(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                      color: c.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.line)),
                  child: Icon(Icons.close, size: 14, color: c.ink),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadingTile extends StatelessWidget {
  const _UploadingTile();

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.only(right: DsSpace.s2),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
            color: c.surfaceSunken, borderRadius: DsRadius.controlAll),
        child: const Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  final VoidCallback? onTap;

  const _AddPhotoTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Semantics(
      button: true,
      label: 'Add photo',
      child: InkWell(
        onTap: onTap,
        borderRadius: DsRadius.controlAll,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            borderRadius: DsRadius.controlAll,
            border: Border.all(color: c.lineStrong),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, color: c.inkMuted),
              const SizedBox(height: 2),
              Text('Add',
                  style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
