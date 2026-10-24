import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

import '../design/theme.dart';
import '../design/tokens.g.dart';

/// Draws a product description written in the admin's rich-text editor.
///
/// The server reduces that text to a small set of tags before it is stored, and
/// this draws exactly that set: paragraphs, large and small headings, bold,
/// italic, underline, strike-through, bulleted and numbered lists, quotes,
/// rules and links. Anything else is shown as plain words, never as markup.
class RichTextView extends StatefulWidget {
  final String html;

  /// The base text style; defaults to the body size and muted ink.
  final TextStyle? style;

  const RichTextView({super.key, required this.html, this.style});

  @override
  State<RichTextView> createState() => _RichTextViewState();
}

class _RichTextViewState extends State<RichTextView> {
  // A tap recogniser for every link on screen; they must be disposed, and are
  // rebuilt whenever the widget is.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null || !{'http', 'https', 'mailto', 'tel'}.contains(uri.scheme)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final c = context.ds;
    final base = widget.style ??
        TextStyle(fontSize: DsText.base, height: DsText.baseHeight, color: c.inkMuted);

    final fragment = html_parser.parseFragment(widget.html);
    final blocks = _blocks(fragment.nodes, base, c);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: DsSpace.s3),
          blocks[i],
        ],
      ],
    );
  }

  static const _blockTags = {'p', 'h2', 'h3', 'h4', 'ul', 'ol', 'blockquote', 'hr', 'div'};

  /// Block-level widgets for a run of nodes. Loose text and inline tags between
  /// blocks are gathered into a paragraph of their own.
  List<Widget> _blocks(List<dom.Node> nodes, TextStyle base, DsColors c) {
    final out = <Widget>[];
    var loose = <dom.Node>[];

    void flush() {
      if (loose.isEmpty) return;
      final spans = _inline(loose, base, c);
      loose = [];
      if (_isBlank(spans)) return;
      out.add(Text.rich(TextSpan(children: spans), style: base));
    }

    for (final node in nodes) {
      if (node is dom.Element && _blockTags.contains(node.localName)) {
        flush();
        final block = _block(node, base, c);
        if (block != null) out.add(block);
      } else {
        loose.add(node);
      }
    }
    flush();
    return out;
  }

  bool _isBlank(List<InlineSpan> spans) =>
      spans.every((s) => s is TextSpan && (s.text ?? '').trim().isEmpty && (s.children ?? const []).isEmpty);

  Widget? _block(dom.Element el, TextStyle base, DsColors c) {
    switch (el.localName) {
      case 'p':
      case 'div':
        final spans = _inline(el.nodes, base, c);
        if (_isBlank(spans)) return null;
        return Text.rich(TextSpan(children: spans), style: base);
      case 'h2':
      case 'h3':
      case 'h4':
        final size = el.localName == 'h2' ? DsText.lg : DsText.md;
        final style = base.copyWith(
            fontSize: size, fontWeight: DsWeight.bold, color: c.ink, height: 1.3);
        final spans = _inline(el.nodes, style, c);
        if (_isBlank(spans)) return null;
        return Padding(
          padding: const EdgeInsets.only(top: DsSpace.s1),
          child: Text.rich(TextSpan(children: spans), style: style),
        );
      case 'ul':
      case 'ol':
        return _list(el, base, c);
      case 'blockquote':
        final inner = _blocks(el.nodes, base.copyWith(fontStyle: FontStyle.italic), c);
        if (inner.isEmpty) return null;
        return Container(
          padding: const EdgeInsets.only(left: DsSpace.s3),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: c.lineStrong, width: 3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: inner),
        );
      case 'hr':
        return Divider(height: 1, color: c.line);
    }
    return null;
  }

  Widget _list(dom.Element list, TextStyle base, DsColors c) {
    final ordered = list.localName == 'ol';
    final items = list.children.where((e) => e.localName == 'li').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : DsSpace.s1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(ordered ? '${i + 1}.' : '•', style: base),
                ),
                Expanded(child: _item(items[i], base, c)),
              ],
            ),
          ),
      ],
    );
  }

  /// A list item: its own text, then any lists nested inside it.
  Widget _item(dom.Element li, TextStyle base, DsColors c) {
    final nested = li.children.where((e) => e.localName == 'ul' || e.localName == 'ol').toList();
    final own = li.nodes.where((n) => !nested.contains(n)).toList();
    final spans = _inline(own, base, c);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_isBlank(spans)) Text.rich(TextSpan(children: spans), style: base),
        for (final n in nested)
          Padding(padding: const EdgeInsets.only(top: DsSpace.s1), child: _list(n, base, c)),
      ],
    );
  }

  List<InlineSpan> _inline(List<dom.Node> nodes, TextStyle base, DsColors c) {
    final spans = <InlineSpan>[];

    for (final node in nodes) {
      if (node is dom.Text) {
        // Whitespace between tags in the source is not a real space.
        final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
        if (text.isNotEmpty) spans.add(TextSpan(text: text));
        continue;
      }
      if (node is! dom.Element) continue;

      switch (node.localName) {
        case 'br':
          spans.add(const TextSpan(text: '\n'));
        case 'strong':
        case 'b':
          spans.add(TextSpan(
              style: const TextStyle(fontWeight: FontWeight.w700),
              children: _inline(node.nodes, base, c)));
        case 'em':
        case 'i':
          spans.add(TextSpan(
              style: const TextStyle(fontStyle: FontStyle.italic),
              children: _inline(node.nodes, base, c)));
        case 'u':
          spans.add(TextSpan(
              style: const TextStyle(decoration: TextDecoration.underline),
              children: _inline(node.nodes, base, c)));
        case 's':
          spans.add(TextSpan(
              style: const TextStyle(decoration: TextDecoration.lineThrough),
              children: _inline(node.nodes, base, c)));
        case 'a':
          final href = node.attributes['href'] ?? '';
          final recognizer = TapGestureRecognizer()..onTap = () => _open(href);
          _recognizers.add(recognizer);
          spans.add(TextSpan(
              style: TextStyle(color: c.accent, decoration: TextDecoration.underline),
              recognizer: recognizer,
              children: _inline(node.nodes, base, c)));
        default:
          // A tag this view does not draw: keep its words.
          spans.addAll(_inline(node.nodes, base, c));
      }
    }
    return spans;
  }
}
