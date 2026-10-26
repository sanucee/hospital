// Renders the NAAK HMS launcher icons and logo files from NaakMarkPainter.
//
// Run from the project root after changing the logo:
//   flutter test tool/generate_icons_test.dart \
//     --dart-define=FONT_DIR=<flutter>/bin/cache/artifacts/material_fonts
//
// FONT_DIR (Flutter's bundled Roboto) is only needed for the wordmark logos;
// without it they are skipped.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/widgets/naak_logo.dart';

const _fontDir = String.fromEnvironment('FONT_DIR');

Future<ui.Image> _render(
  int width,
  int height,
  void Function(Canvas c, Size s) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  draw(canvas, Size(width.toDouble(), height.toDouble()));
  return recorder.endRecording().toImage(width, height);
}

Future<Uint8List> _mark(
  int px, {
  double corner = 0.22,
  double inset = 0,
  double scale = 1,
}) async {
  final img = await _render(
    px,
    px,
    (c, s) => NaakMarkPainter(
      cornerRadius: corner,
      inset: inset,
      contentScale: scale,
    ).paint(c, s),
  );
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
}

/// iOS rejects app icons with an alpha channel, so these are written as
/// RGB PNGs.
Future<Uint8List> _opaqueMark(int px) async {
  final img = await _render(
    px,
    px,
    (c, s) => NaakMarkPainter(cornerRadius: 0).paint(c, s),
  );
  final rgba = (await img.toByteData())!.buffer.asUint8List();
  return _rgbPng(px, px, rgba);
}

Uint8List _rgbPng(int w, int h, Uint8List rgba) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0); // no filter
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      raw.add([rgba[i], rgba[i + 1], rgba[i + 2]]);
    }
  }
  final out = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    out
      ..add(_u32(data.length))
      ..add(body)
      ..add(_u32(_crc32(body)));
  }

  chunk('IHDR', [..._u32(w), ..._u32(h), 8, 2, 0, 0, 0]);
  chunk('IDAT', ZLibCodec(level: 9).encode(raw.toBytes()));
  chunk('IEND', []);
  return out.toBytes();
}

List<int> _u32(int v) => [v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255];

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// A Windows .ico holding PNG images of each size.
Uint8List _ico(Map<int, Uint8List> pngs) {
  List<int> u16(int v) => [v & 255, v >> 8 & 255];
  List<int> u32le(int v) => [v & 255, v >> 8 & 255, v >> 16 & 255, v >> 24];
  final out = BytesBuilder()..add([...u16(0), ...u16(1), ...u16(pngs.length)]);
  var offset = 6 + 16 * pngs.length;
  for (final MapEntry(key: px, value: png) in pngs.entries) {
    out.add([
      px >= 256 ? 0 : px,
      px >= 256 ? 0 : px,
      0,
      0,
      ...u16(1),
      ...u16(32),
      ...u32le(png.length),
      ...u32le(offset),
    ]);
    offset += png.length;
  }
  for (final png in pngs.values) {
    out.add(png);
  }
  return out.toBytes();
}

void _write(String path, List<int> bytes) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

Future<void> _loadFont(String family, String file) async {
  final bytes = File('$_fontDir/$file').readAsBytesSync();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

/// Horizontal logo: mark, "NAAK HMS" and the tagline.
Future<Uint8List> _wordmark({required bool onDark}) async {
  const h = 360.0, w = 1500.0, mark = 300.0;
  final name = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      style: const TextStyle(fontSize: 190, height: 1, letterSpacing: 6),
      children: [
        TextSpan(
          text: 'NAAK',
          style: TextStyle(
            fontFamily: 'NaakBlack',
            color: onDark ? Colors.white : kNaakDeep,
          ),
        ),
        TextSpan(
          text: ' HMS',
          style: TextStyle(
            fontFamily: 'NaakLight',
            color: onDark ? kNaakLight : kNaakTeal,
          ),
        ),
      ],
    ),
  )..layout();
  final tag = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: kAppTagline.toUpperCase(),
      style: TextStyle(
        fontFamily: 'NaakRegular',
        fontSize: 50,
        letterSpacing: 7.5,
        color: onDark ? const Color(0xFFB2DFDB) : const Color(0xFF5F7774),
      ),
    ),
  )..layout();
  final img = await _render(w.toInt(), h.toInt(), (c, s) {
    c.save();
    c.translate(30, (h - mark) / 2);
    const NaakMarkPainter().paint(c, const Size.square(mark));
    c.restore();
    const x = 30 + mark + 70;
    final top = (h - name.height - 22 - tag.height) / 2;
    name.paint(c, Offset(x, top));
    tag.paint(c, Offset(x + 6, top + name.height + 22));
  });
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate launcher icons', () async {
    // Web
    _write('web/favicon.png', await _mark(32, corner: 0.2));
    _write('web/icons/Icon-192.png', await _mark(192));
    _write('web/icons/Icon-512.png', await _mark(512));
    // Maskable icons are cropped to a circle: full bleed, cross in the
    // safe zone.
    _write(
      'web/icons/Icon-maskable-192.png',
      await _mark(192, corner: 0, scale: 0.78),
    );
    _write(
      'web/icons/Icon-maskable-512.png',
      await _mark(512, corner: 0, scale: 0.78),
    );

    // Android
    for (final (dir, px) in [
      ('mdpi', 48),
      ('hdpi', 72),
      ('xhdpi', 96),
      ('xxhdpi', 144),
      ('xxxhdpi', 192),
    ]) {
      _write(
        'android/app/src/main/res/mipmap-$dir/ic_launcher.png',
        await _mark(px, inset: 0.04),
      );
    }

    // iOS: square and opaque; the system rounds the corners.
    const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final (pt, scales) in [
      ('20x20', [1, 2, 3]),
      ('29x29', [1, 2, 3]),
      ('40x40', [1, 2, 3]),
      ('60x60', [2, 3]),
      ('76x76', [1, 2]),
      ('83.5x83.5', [2]),
      ('1024x1024', [1]),
    ]) {
      final base = double.parse(pt.split('x').first);
      for (final x in scales) {
        _write(
          '$ios/Icon-App-$pt@${x}x.png',
          await _opaqueMark((base * x).round()),
        );
      }
    }

    // macOS: rounded tile inside a margin, per Apple's icon grid.
    for (final px in [16, 32, 64, 128, 256, 512, 1024]) {
      _write(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$px.png',
        await _mark(px, corner: 0.225, inset: 0.098),
      );
    }

    // Windows
    _write(
      'windows/runner/resources/app_icon.ico',
      _ico({
        for (final px in [16, 24, 32, 48, 64, 128, 256])
          px: await _mark(px, corner: 0.2),
      }),
    );

    // Brand files
    _write('docs/branding/naak-hms-icon-1024.png', await _mark(1024));
  });

  test('generate wordmark logos', () async {
    if (_fontDir.isEmpty) {
      markTestSkipped('FONT_DIR not given');
      return;
    }
    await _loadFont('NaakBlack', 'roboto-black.ttf');
    await _loadFont('NaakLight', 'roboto-light.ttf');
    await _loadFont('NaakRegular', 'roboto-regular.ttf');
    _write('docs/branding/naak-hms-logo.png', await _wordmark(onDark: false));
    _write(
      'docs/branding/naak-hms-logo-dark.png',
      await _wordmark(onDark: true),
    );
  });
}
