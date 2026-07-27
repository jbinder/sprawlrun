// Generates every launcher icon from a single vector description.
//
// Like the SFX, the artwork is produced rather than imported, so the repo has
// no binary assets of uncertain origin. Re-run after editing:
//
//     dart run tool/gen_icons.dart
//
// PNGs are written with a minimal encoder built on dart:io's zlib.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// The palette mirrors lib/theme/cyber_palette.dart.
const _void = (0x04, 0x07, 0x0B);
const _panel = (0x0A, 0x11, 0x19);
const _cyan = (0x00, 0xF0, 0xFF);
const _magenta = (0xFF, 0x2D, 0x9B);

void main() {
  _writeAndroid();
  _writeIos();
  _writeStoreIcon();
  stdout.writeln('Icons regenerated.');
}

void _writeAndroid() {
  const res = 'android/app/src/main/res';

  // Legacy square icon, and the adaptive foreground layer. Adaptive
  // foregrounds are drawn into the middle two thirds of the canvas because
  // launchers crop the outer third to whatever mask the device uses.
  const densities = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
  const foregrounds = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432};

  densities.forEach((density, size) {
    final dir = Directory('$res/mipmap-$density')..createSync(recursive: true);
    File('${dir.path}/ic_launcher.png').writeAsBytesSync(encodePng(renderIcon(size, background: true, inset: 0.80)));
    File('${dir.path}/ic_launcher_foreground.png')
        .writeAsBytesSync(encodePng(renderIcon(foregrounds[density]!, background: false, inset: 0.68)));
  });

  Directory('$res/mipmap-anydpi-v26').createSync(recursive: true);
  File('$res/mipmap-anydpi-v26/ic_launcher.xml').writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''');

  Directory('$res/values').createSync(recursive: true);
  File('$res/values/ic_launcher_background.xml').writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#04070B</color>
</resources>
''');
}

void _writeIos() {
  const dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final contents = File('$dir/Contents.json');
  if (!contents.existsSync()) return;

  final manifest = jsonDecode(contents.readAsStringSync()) as Map<String, dynamic>;
  for (final image in (manifest['images'] as List).cast<Map<String, dynamic>>()) {
    final filename = image['filename'] as String?;
    if (filename == null) continue;
    // "60x60" plus a "3x" scale means a 180 px file.
    final points = double.parse((image['size'] as String).split('x').first);
    final scale = int.parse((image['scale'] as String).replaceAll('x', ''));
    final size = (points * scale).round();
    File('$dir/$filename').writeAsBytesSync(encodePng(renderIcon(size, background: true, inset: 0.80)));
  }
}

/// A large flat icon for store listings and READMEs.
void _writeStoreIcon() {
  Directory('docs').createSync(recursive: true);
  File('docs/icon.png').writeAsBytesSync(encodePng(renderIcon(512, background: true, inset: 0.80)));
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// The mark: a hexagonal containment ring with a double slash cut through it —
/// the shell from mission one, and the `//` from the app's name.
///
/// Rendered by supersampling signed distance fields, which gives clean edges at
/// every size without needing a rasteriser.
Uint8List renderIcon(int size, {required bool background, double inset = 1.0}) {
  const ss = 4; // supersampling factor
  final n = size * ss;
  final acc = Float64List(size * size * 4);

  final centre = n / 2.0;
  final unit = n * inset / 2.0;

  for (var py = 0; py < n; py++) {
    for (var px = 0; px < n; px++) {
      final x = (px + 0.5 - centre) / unit;
      final y = (py + 0.5 - centre) / unit;

      var r = 0.0, g = 0.0, b = 0.0, a = 0.0;

      void over((int, int, int) colour, double alpha) {
        if (alpha <= 0) return;
        final cr = colour.$1 / 255.0, cg = colour.$2 / 255.0, cb = colour.$3 / 255.0;
        r = cr * alpha + r * (1 - alpha);
        g = cg * alpha + g * (1 - alpha);
        b = cb * alpha + b * (1 - alpha);
        a = alpha + a * (1 - alpha);
      }

      if (background) {
        over(_void, 1.0);
        // Faint grid, the same motif as the app's backdrop.
        final gx = ((px / ss) % 12) < 1 ? 1.0 : 0.0;
        final gy = ((py / ss) % 12) < 1 ? 1.0 : 0.0;
        if (gx + gy > 0) over(_panel, 0.9);
      }

      // Hexagon ring.
      final hex = _sdHexagon(x, y, 0.74).abs() - 0.075;
      over(_cyan, _coverage(hex));

      // Inner hexagon, dimmer, for depth.
      final inner = _sdHexagon(x, y, 0.44).abs() - 0.018;
      over(_cyan, _coverage(inner) * 0.45);

      // The double slash, drawn slightly wider than the ring so it reads as
      // cutting through rather than sitting on top.
      for (final offset in [-0.16, 0.16]) {
        final slash = _sdSegment(x - offset, y, -0.30, 0.52, 0.30, -0.52) - 0.085;
        over(_magenta, _coverage(slash));
      }

      final i = ((py ~/ ss) * size + (px ~/ ss)) * 4;
      acc[i] += r * a;
      acc[i + 1] += g * a;
      acc[i + 2] += b * a;
      acc[i + 3] += a;
    }
  }

  final out = Uint8List(size * size * 4);
  const samples = ss * ss;
  for (var i = 0; i < size * size; i++) {
    final alpha = acc[i * 4 + 3] / samples;
    // Un-premultiply so partly covered pixels keep their colour.
    final scale = alpha > 0 ? 1.0 / (alpha * samples) : 0.0;
    out[i * 4] = (acc[i * 4] * scale * 255).clamp(0, 255).round();
    out[i * 4 + 1] = (acc[i * 4 + 1] * scale * 255).clamp(0, 255).round();
    out[i * 4 + 2] = (acc[i * 4 + 2] * scale * 255).clamp(0, 255).round();
    out[i * 4 + 3] = (alpha * 255).clamp(0, 255).round();
  }
  return out;
}

/// Antialiased inside-ness for a signed distance, in normalised units.
double _coverage(double distance) => (0.5 - distance / 0.012).clamp(0.0, 1.0);

/// Signed distance to a regular flat-topped hexagon of radius [r].
double _sdHexagon(double px, double py, double r) {
  const kx = -0.8660254038, ky = 0.5, kz = 0.5773502692;
  var x = px.abs(), y = py.abs();
  final dot = kx * x + ky * y;
  final f = 2.0 * min(dot, 0.0);
  x -= f * kx;
  y -= f * ky;
  x -= x.clamp(-kz * r, kz * r);
  y -= r;
  return sqrt(x * x + y * y) * (y < 0 ? -1 : 1);
}

/// Signed distance to a line segment.
double _sdSegment(double px, double py, double ax, double ay, double bx, double by) {
  final pax = px - ax, pay = py - ay;
  final bax = bx - ax, bay = by - ay;
  final h = ((pax * bax + pay * bay) / (bax * bax + bay * bay)).clamp(0.0, 1.0);
  final dx = pax - bax * h, dy = pay - bay * h;
  return sqrt(dx * dx + dy * dy);
}

// ---------------------------------------------------------------------------
// PNG
// ---------------------------------------------------------------------------

/// Minimal RGBA PNG encoder: one IHDR, one zlib-deflated IDAT, one IEND.
Uint8List encodePng(Uint8List rgba) {
  final pixels = rgba.length ~/ 4;
  final size = sqrt(pixels).round();

  // Each scanline is prefixed with filter type 0 (None).
  final raw = Uint8List(size * (size * 4 + 1));
  var p = 0;
  for (var y = 0; y < size; y++) {
    raw[p++] = 0;
    raw.setRange(p, p + size * 4, rgba, y * size * 4);
    p += size * 4;
  }

  final out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final ihdr = BytesBuilder()
    ..add(_u32(size))
    ..add(_u32(size))
    ..add([8, 6, 0, 0, 0]); // 8-bit, RGBA, deflate, no filter, no interlace
  out.add(_chunk('IHDR', ihdr.toBytes()));
  out.add(_chunk('IDAT', Uint8List.fromList(ZLibEncoder(level: 9).convert(raw))));
  out.add(_chunk('IEND', Uint8List(0)));
  return out.toBytes();
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

Uint8List _chunk(String type, Uint8List data) {
  final body = Uint8List.fromList([...type.codeUnits, ...data]);
  return Uint8List.fromList([..._u32(data.length), ...body, ..._u32(_crc32(body))]);
}

final List<int> _crcTable = List<int>.generate(256, (i) {
  var c = i;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
