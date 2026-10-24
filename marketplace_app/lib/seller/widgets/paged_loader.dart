import 'package:flutter/foundation.dart';

import '../../data/api_client.dart';
import '../seller_models.dart';

/// Loads a paginated list one page at a time, for the orders, products and
/// earnings tabs — three lists that would otherwise each carry their own copy of
/// the same "refresh, load more, remember the error" logic.
class PagedLoader<T> extends ChangeNotifier {
  PagedLoader(this._fetch);

  final Future<ListPage<T>> Function(int page) _fetch;

  final List<T> items = [];
  ListPage<T>? _last;
  bool loading = false;
  bool loadingMore = false;
  String? error;

  /// The most recent page, for endpoints that add extra top-level values
  /// (the ledger's running balance).
  ListPage<T>? get lastPage => _last;

  bool get hasMore => _last?.hasMore ?? false;
  int get total => _last?.total ?? items.length;
  bool get isEmpty => !loading && error == null && items.isEmpty;

  /// Throw away what is shown and start again from page 1.
  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final page = await _fetch(1);
      items
        ..clear()
        ..addAll(page.items);
      _last = page;
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not load this list. Check your connection and try again.';
    }

    loading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore) return;

    loadingMore = true;
    notifyListeners();

    try {
      final page = await _fetch((_last?.page ?? 1) + 1);
      items.addAll(page.items);
      _last = page;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load more. Check your connection and try again.';
    }

    loadingMore = false;
    notifyListeners();
  }
}
