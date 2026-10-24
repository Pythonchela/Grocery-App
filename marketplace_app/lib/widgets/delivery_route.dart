import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/mobile.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// How far along its journey an order is, from 0 (just placed) to 1 (at the
/// door). Worked out from the order's status and, once it is on the road, how
/// much of the promised time has elapsed - never from a pretend GPS position.
class DeliveryProgress {
  const DeliveryProgress._();

  static const _byStatus = {
    'PENDING': 0.0,
    'CONFIRMED': 0.06,
    'PACKED': 0.22,
    'SHIPPED': 0.42,
    'OUT_FOR_DELIVERY': 0.55,
    'DELIVERED': 1.0,
    'CANCELLED': 0.0,
  };

  static double of(
    String status, {
    DateTime? placedAt,
    DateTime? promisedBy,
    DateTime? now,
  }) {
    final base = _byStatus[status] ?? 0.0;
    if (status == 'DELIVERED') return 1;

    final onTheRoad = status == 'SHIPPED' || status == 'OUT_FOR_DELIVERY';
    if (!onTheRoad || placedAt == null || promisedBy == null) return base;

    final total = promisedBy.difference(placedAt).inSeconds;
    if (total <= 0) return base;

    final elapsed = (now ?? DateTime.now()).difference(placedAt).inSeconds;
    final byTime = (elapsed / total).clamp(0.0, 1.0);

    // Moves forward with the clock but never backwards past the status, and never
    // claims arrival: only the DELIVERED status can say that.
    return byTime.clamp(base, 0.95);
  }
}

/// A stylised route from the store to the door with the delivery partner moving
/// along it.
///
/// This is deliberately not a street map. Real tiles need a mapping provider's
/// key and a destination coordinate the API does not hold yet; until then this
/// shows progress honestly, and says so ("Live" only when the carrier is sending
/// a real position).
class DeliveryRouteMap extends StatefulWidget {
  /// 0..1 along the route.
  final double progress;

  /// True when the carrier is reporting a real GPS position.
  final bool live;
  final bool delivered;
  final bool cancelled;

  /// How much of the panel stays visible above a sheet that slides over it. The
  /// route and the status chip are laid out inside this area so they are never
  /// hidden, while the background keeps filling the whole panel behind the sheet.
  final double? visibleHeight;

  const DeliveryRouteMap({
    super.key,
    required this.progress,
    this.live = false,
    this.delivered = false,
    this.cancelled = false,
    this.visibleHeight,
  });

  @override
  State<DeliveryRouteMap> createState() => _DeliveryRouteMapState();
}

class _DeliveryRouteMapState extends State<DeliveryRouteMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour "remove animations": a static marker instead of a pulsing one.
    if (MediaQuery.disableAnimationsOf(context) || widget.delivered || widget.cancelled) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final t = widget.delivered ? 1.0 : widget.progress.clamp(0.0, 1.0);

    return Semantics(
      label: widget.cancelled
          ? 'Order cancelled'
          : widget.delivered
              ? 'Delivered'
              : 'Delivery ${(t * 100).round()} percent of the way',
      child: LayoutBuilder(
        builder: (context, box) {
          final area = (widget.visibleHeight ?? box.maxHeight)
              .clamp(0.0, box.maxHeight);
          final size = Size(box.maxWidth, area);
          final route = _Route(size);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [c.accentSoft, c.surfaceSunken],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _RoutePainter(
                    route: route,
                    progress: t,
                    grid: c.line.withValues(alpha: 0.6),
                    ahead: c.lineStrong,
                    travelled: widget.cancelled ? c.inkSubtle : c.accent,
                  ),
                ),
              ),
              _marker(route.start, Icons.storefront_outlined, c.inverse, c.inkInverse),
              _marker(route.end, Icons.home_rounded, c.success, c.surface,
                  size: 40),
              if (!widget.cancelled && !widget.delivered)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final at = route.at(t);
                    final ring = _pulse.value;
                    return Positioned(
                      left: at.dx - 36,
                      top: at.dy - 36,
                      width: 72,
                      height: 72,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 28 + 40 * ring,
                            height: 28 + 40 * ring,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: c.accent.withValues(alpha: 0.25 * (1 - ring)),
                            ),
                          ),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.surface, width: 3),
                            ),
                            child: Icon(Icons.electric_moped,
                                size: 20, color: c.onAccent),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              Positioned(
                left: DsSpace.s4,
                top: area - 52,
                child: _Chip(
                  icon: widget.live ? Icons.sensors : Icons.timeline,
                  label: widget.cancelled
                      ? 'Cancelled'
                      : widget.delivered
                          ? 'Delivered'
                          : widget.live
                              ? 'Live'
                              : 'Estimated progress',
                  highlight: widget.live,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _marker(Offset at, IconData icon, Color bg, Color fg, {double size = 36}) {
    return Positioned(
      left: at.dx - size / 2,
      top: at.dy - size / 2,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: context.ds.surface, width: 3),
        ),
        child: Icon(icon, size: size * 0.5, color: fg),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;

  const _Chip({required this.icon, required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.92),
        borderRadius: DsRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: highlight ? c.success : c.inkMuted),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                fontSize: DsText.xs,
                fontWeight: DsWeight.bold,
                color: highlight ? c.success : c.inkMuted,
              )),
        ],
      ),
    );
  }
}

/// The curve the delivery partner follows, in the panel's own coordinates.
class _Route {
  final Offset start;
  final Offset control1;
  final Offset control2;
  final Offset end;

  _Route(Size size)
      : start = Offset(size.width * 0.14, size.height * 0.62),
        control1 = Offset(size.width * 0.36, size.height * 0.08),
        control2 = Offset(size.width * 0.58, size.height * 0.95),
        end = Offset(size.width * 0.86, size.height * 0.36);

  /// The point [t] of the way along the route (cubic Bézier).
  Offset at(double t) {
    final u = 1 - t;
    return start * (u * u * u) +
        control1 * (3 * u * u * t) +
        control2 * (3 * u * t * t) +
        end * (t * t * t);
  }

  Path path({double upTo = 1}) {
    final p = Path()..moveTo(start.dx, start.dy);
    const steps = 48;
    for (var i = 1; i <= steps; i++) {
      final point = at(upTo * i / steps);
      p.lineTo(point.dx, point.dy);
    }
    return p;
  }
}

class _RoutePainter extends CustomPainter {
  final _Route route;
  final double progress;
  final Color grid;
  final Color ahead;
  final Color travelled;

  _RoutePainter({
    required this.route,
    required this.progress,
    required this.grid,
    required this.ahead,
    required this.travelled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // City-block grid, so the panel reads as a map rather than a gradient.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 36) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // The road ahead: dashed.
    final aheadPaint = Paint()
      ..color = ahead
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    _dashed(canvas, route.path(), aheadPaint);

    // The road behind: solid.
    if (progress > 0) {
      final done = Paint()
        ..color = travelled
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(route.path(upTo: progress), done);
    }
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 10, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 18;
      }
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.progress != progress ||
      old.travelled != travelled ||
      old.ahead != ahead ||
      old.grid != grid;
}

/// Four-step status strip: Confirmed, Packed, On the way, Delivered.
class DeliveryStages extends StatelessWidget {
  final String status;
  const DeliveryStages({super.key, required this.status});

  static const _stages = [
    ('Confirmed', Icons.check_circle_outline, ['PENDING', 'CONFIRMED']),
    ('Packed', Icons.inventory_2_outlined, ['PACKED']),
    ('On the way', Icons.electric_moped_outlined, ['SHIPPED', 'OUT_FOR_DELIVERY']),
    ('Delivered', Icons.home_outlined, ['DELIVERED']),
  ];

  int get _current {
    for (var i = 0; i < _stages.length; i++) {
      if (_stages[i].$3.contains(status)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final current = _current;

    return Row(
      children: [
        for (var i = 0; i < _stages.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                AnimatedContainer(
                  duration: DsMobileMotion.of(context, DsMobileMotion.standard),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: i <= current ? c.success : c.surfaceSunken,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    i < current ? Icons.check : _stages[i].$2,
                    size: 20,
                    color: i <= current ? c.onPrimary : c.inkSubtle,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _stages[i].$1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: DsText.xs,
                    fontWeight: i == current ? DsWeight.black : DsWeight.medium,
                    color: i <= current ? c.ink : c.inkSubtle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
