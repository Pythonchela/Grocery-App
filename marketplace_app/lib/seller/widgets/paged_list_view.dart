import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import 'paged_loader.dart';
import 'seller_widgets.dart';

/// A pull-to-refresh list that loads more as you near the end.
///
/// [header] scrolls with the list (filters, a balance card); [empty] is shown
/// when the list has loaded and there is nothing in it.
class PagedListView<T> extends StatefulWidget {
  final PagedLoader<T> loader;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final List<Widget> header;
  final Widget empty;

  const PagedListView({
    super.key,
    required this.loader,
    required this.itemBuilder,
    required this.empty,
    this.header = const [],
  });

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 320) {
      widget.loader.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return AnimatedBuilder(
      animation: widget.loader,
      builder: (context, _) {
        final l = widget.loader;
        final first = l.loading && l.items.isEmpty;

        return RefreshIndicator(
          onRefresh: l.refresh,
          color: c.accent,
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(DsSpace.s4),
            children: [
              ...widget.header,
              if (first)
                const SellerListSkeleton()
              else if (l.error != null && l.items.isEmpty)
                SellerLoadError(message: l.error!, onRetry: l.refresh)
              else if (l.isEmpty)
                widget.empty
              else ...[
                for (final item in l.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DsSpace.s3),
                    child: widget.itemBuilder(context, item),
                  ),
                if (l.error != null)
                  BxAlert(l.error!, tone: BxTone.danger)
                else if (l.loadingMore)
                  const Padding(
                    padding: EdgeInsets.all(DsSpace.s4),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (l.hasMore)
                  Center(
                    child: BxButton(
                      label: 'Load more',
                      variant: BxButtonVariant.secondary,
                      size: BxButtonSize.sm,
                      onPressed: l.loadMore,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
