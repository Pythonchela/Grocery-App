import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/tokens.g.dart';
import '../widgets/wishlist_heart.dart';
import 'product_detail_screen.dart';

/// Shoppable short-video feed, the mobile twin of the web `/reels` page.
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _Reel {
  final Product product;
  final String videoUrl;
  final String caption;
  _Reel(this.product, this.videoUrl, this.caption);
}

class _ReelsScreenState extends State<ReelsScreen> {
  final _pages = PageController();
  List<_Reel> _reels = [];
  bool _loading = true;
  String? _error;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.request('/reels', query: {'per_page': '30'});
      final reels = <_Reel>[];
      for (final raw in (data as List)) {
        final json = raw as Map<String, dynamic>;
        final url = json['reel_video_url']?.toString() ?? '';
        if (url.isEmpty) continue;
        reels.add(_Reel(Product.fromJson(json), url,
            json['reel_caption']?.toString() ?? ''));
      }
      if (!mounted) return;
      setState(() {
        _reels = reels;
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

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = BxEmptyState(
        icon: Icons.error_outline,
        title: 'Could not load reels',
        description: _error,
        action: BxButton(label: 'Try again', onPressed: _load),
      );
    } else if (_reels.isEmpty) {
      body = const BxEmptyState(
        icon: Icons.play_circle_outline,
        title: 'No reels yet',
        description:
            'Short product videos will appear here as sellers add them.',
      );
    } else {
      body = PageView.builder(
        controller: _pages,
        scrollDirection: Axis.vertical,
        itemCount: _reels.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) =>
            _ReelPage(reel: _reels[i], active: i == _current),
      );
    }

    final immersive = _reels.isNotEmpty;
    return Scaffold(
      extendBodyBehindAppBar: immersive,
      appBar: AppBar(
        title: const Text('Reels'),
        backgroundColor: immersive ? Colors.transparent : null,
        foregroundColor: immersive ? Colors.white : null,
        elevation: 0,
      ),
      backgroundColor: immersive ? Colors.black : null,
      body: body,
    );
  }
}

class _ReelPage extends StatefulWidget {
  final _Reel reel;
  final bool active;

  const _ReelPage({required this.reel, required this.active});

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _video;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.reel.videoUrl));
    _video = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (widget.active) await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    final v = _video;
    if (v == null || !v.value.isInitialized) return;
    if (widget.active && !old.active) {
      v.play();
    } else if (!widget.active && old.active) {
      v.pause();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final v = _video;
    if (v == null || !v.value.isInitialized) return;
    setState(() => v.value.isPlaying ? v.pause() : v.play());
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.reel.product;
    final v = _video;
    final ready = v != null && v.value.isInitialized;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: _failed
                ? const Text('This video could not be played',
                    style: TextStyle(color: Colors.white70))
                : ready
                    ? FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: v.value.size.width,
                          height: v.value.size.height,
                          child: VideoPlayer(v),
                        ),
                      )
                    : const CircularProgressIndicator(),
          ),
        ),
        if (ready && !v.value.isPlaying)
          const IgnorePointer(
            child: Center(
                child: Icon(Icons.play_arrow_rounded,
                    size: 72, color: Colors.white70)),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(DsSpace.s4),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: DsText.lg,
                          fontWeight: DsWeight.black)),
                  if (widget.reel.caption.isNotEmpty) ...[
                    const SizedBox(height: DsSpace.s1),
                    Text(widget.reel.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70)),
                  ],
                  const SizedBox(height: DsSpace.s2),
                  Text(formatMoney(p.price),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: DsText.md,
                          fontWeight: DsWeight.bold)),
                  const SizedBox(height: DsSpace.s3),
                  Row(
                    children: [
                      Expanded(
                        child: BxButton(
                          label: 'View product',
                          variant: BxButtonVariant.highlight,
                          fullWidth: true,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    ProductDetailScreen(productId: p.id)),
                          ),
                        ),
                      ),
                      const SizedBox(width: DsSpace.s2),
                      WishlistHeart(product: p, overlay: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
