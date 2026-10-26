import 'package:flutter/material.dart';

const kAppName = 'NAAK HMS';
const kAppTagline = 'Hospital Management System';

/// Brand colours, also used for the launcher icons (`tool/`).
const kNaakLight = Color(0xFF26A69A);
const kNaakTeal = Color(0xFF00897B);
const kNaakDeep = Color(0xFF004D40);

/// The NAAK HMS mark: a white medical cross on a teal tile, with a
/// heartbeat line running through it.
///
/// The same painter draws the mark in the app and renders every launcher
/// icon (`flutter test tool/generate_icons_test.dart`), so they always
/// match.
class NaakMarkPainter extends CustomPainter {
  const NaakMarkPainter({
    this.cornerRadius = 0.22,
    this.inset = 0,
    this.contentScale = 1,
  });

  /// Tile corner radius as a fraction of its side; 0 for a full square
  /// (platforms that apply their own mask, such as iOS).
  final double cornerRadius;

  /// Transparent margin around the tile, as a fraction of the side (macOS
  /// icons sit inside the canvas).
  final double inset;

  /// Shrinks the cross, keeping it inside the safe zone of maskable icons.
  final double contentScale;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);

    final tile = (Offset.zero & Size.square(side)).deflate(side * inset);
    final t = tile.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(tile, Radius.circular(t * cornerRadius)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kNaakLight, kNaakTeal, kNaakDeep],
          stops: [0, 0.45, 1],
        ).createShader(tile),
    );

    // Everything else is drawn on a 100 × 100 grid centred on the tile.
    canvas.translate(tile.center.dx, tile.center.dy);
    canvas.scale(t * contentScale / 100);

    const arm = 12.5; // half the arm width
    const reach = 31.0; // centre to arm end
    const round = Radius.circular(5);
    final cross = Path.combine(
      PathOperation.union,
      Path()..addRRect(RRect.fromLTRBR(-reach, -arm, reach, arm, round)),
      Path()..addRRect(RRect.fromLTRBR(-arm, -reach, arm, reach, round)),
    );

    canvas.drawPath(
      cross.shift(const Offset(0, 1.6)),
      Paint()
        ..color = const Color(0x40002620)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawPath(cross, Paint()..color = Colors.white);

    // The heartbeat, cut out of the cross in the tile colour. Its peaks
    // stay within the vertical arm so none are clipped away.
    final pulse = Path()
      ..moveTo(-reach, 0)
      ..lineTo(-13, 0)
      ..lineTo(-8.5, -8)
      ..lineTo(-2.5, 12)
      ..lineTo(4.5, -19)
      ..lineTo(9.5, 0)
      ..lineTo(reach, 0);
    canvas.save();
    canvas.clipPath(cross);
    canvas.drawPath(
      pulse,
      Paint()
        ..color = kNaakTeal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(NaakMarkPainter old) =>
      old.cornerRadius != cornerRadius ||
      old.inset != inset ||
      old.contentScale != contentScale;
}

class NaakMark extends StatelessWidget {
  const NaakMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: kAppName,
    child: CustomPaint(
      size: Size.square(size),
      painter: const NaakMarkPainter(),
    ),
  );
}

/// The mark with "NAAK HMS" beside it, and the tagline under the name if
/// [tagline].
class NaakLogo extends StatelessWidget {
  const NaakLogo({super.key, this.size = 48, this.tagline = false});

  /// Height of the mark; the text scales with it.
  final double size;
  final bool tagline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NaakMark(size: size),
        SizedBox(width: size * 0.28),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'NAAK',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: dark ? Colors.white : kNaakDeep,
                    ),
                  ),
                  TextSpan(
                    text: ' HMS',
                    style: TextStyle(
                      fontWeight: FontWeight.w300,
                      color: dark ? kNaakLight : kNaakTeal,
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: size * 0.62,
                height: 1,
                letterSpacing: size * 0.02,
              ),
            ),
            if (tagline)
              Padding(
                padding: EdgeInsets.only(top: size * 0.08),
                child: Text(
                  kAppTagline,
                  style: TextStyle(
                    fontSize: size * 0.22,
                    color: scheme.outline,
                    letterSpacing: size * 0.01,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
