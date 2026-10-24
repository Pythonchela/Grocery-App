import 'package:flutter/material.dart';

import '../data/google_auth.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';

/// "Continue with Google", used from both sign-in and sign-up.
///
/// One widget rather than two copies because the flow is identical — the server
/// decides whether the verified Google identity is a new account or an existing
/// one, so the client has no reason to care which it is.
class GoogleSignInButton extends StatefulWidget {
  final String? referralCode;
  final VoidCallback? onSignedIn;

  const GoogleSignInButton({super.key, this.referralCode, this.onSignedIn});

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final idToken = await GoogleAuth.signIn();

      // Null means the account chooser was dismissed. That is a decision, not
      // a failure — say nothing and leave the form as it was.
      if (idToken == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      await AppState.instance.signInWithGoogleIdToken(
        idToken,
        referralCode: widget.referralCode,
      );

      if (mounted) widget.onSignedIn?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is StateError ? e.message : e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_error != null) ...[
          BxAlert(_error!, tone: BxTone.danger),
          const SizedBox(height: DsSpace.s3),
        ],
        BxButton(
          variant: BxButtonVariant.secondary,
          size: BxButtonSize.lg,
          fullWidth: true,
          loading: _busy,
          onPressed: _busy ? null : _signIn,
          leadingIcon: null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _GoogleMark(),
              const SizedBox(width: DsSpace.s3),
              Text(
                'Continue with Google',
                style: TextStyle(
                  fontFamily: DsFont.sans,
                  fontSize: DsText.base,
                  fontWeight: DsWeight.bold,
                  color: context.ds.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Google's mark, drawn rather than shipped as an asset.
///
/// Its four brand colours are deliberately hardcoded and deliberately NOT
/// tokens: they belong to Google, not to us, and Google's brand guidelines
/// require them exactly. Re-theming them — including inverting them in dark
/// mode — would be a trademark problem, not a design improvement.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  // ignore: avoid-hardcoded-colors — Google brand palette, fixed by their guidelines.
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final centre = Offset(r, r);
    final stroke = size.width * 0.26;

    final rect = Rect.fromCircle(center: centre, radius: r - stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Four arcs approximating the mark at button scale, where the exact
    // letterform is not legible anyway.
    canvas.drawArc(rect, -0.35, 1.15, false, paint..color = _blue);
    canvas.drawArc(rect, 0.85, 1.4, false, paint..color = _green);
    canvas.drawArc(rect, 2.3, 1.4, false, paint..color = _yellow);
    canvas.drawArc(rect, 3.75, 1.6, false, paint..color = _red);

    // The horizontal bar of the G.
    canvas.drawLine(
      Offset(r, r),
      Offset(size.width - stroke / 2, r),
      Paint()
        ..color = _blue
        ..strokeWidth = stroke * 0.85,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
