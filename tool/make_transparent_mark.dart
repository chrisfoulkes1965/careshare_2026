// ignore_for_file: avoid_print

// Builds `assets/images/CareShareMark.png` (white+alpha) for
// `Image` + `Color` + BlendMode.srcIn. Run: dart run tool/make_transparent_mark.dart
// Palette PNGs are expanded to true RGBA first, or setPixelRgba would write
// a palette index, not real colour.
import "dart:io";

import "package:image/image.dart" as img;

/// White / cream / light-greige tile and page backgrounds — becomes transparent.
bool _isLightNeutral(int r, int g, int b) {
  if (r > 230 && g > 228 && b > 220) {
    if ((r - g).abs() < 30 && (g - b).abs() < 35) {
      return true;
    }
  }
  if (r + g + b > 690 && (r - b).abs() < 20 && (g - b).abs() < 20) {
    return true;
  }
  return false;
}

/// Marketing tile: white line mark on a solid app-blue field.
bool _isBlueField(int r, int g, int b) {
  if (b < 90) {
    return false;
  }
  if (b > r + 25 && b > g - 40 && r < 160) {
    return true;
  }
  if (b > 180 && g > 150 && r < 130) {
    return true;
  }
  return false;
}

void _makeMask(img.Image image, {required bool blueOnLightTile}) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      if (p.aNormalized < 0.01) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }
      final red = p.r.toInt();
      final green = p.g.toInt();
      final blue = p.b.toInt();
      if (blueOnLightTile) {
        if (_isLightNeutral(red, green, blue)) {
          image.setPixelRgba(x, y, 0, 0, 0, 0);
        } else {
          image.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      } else {
        if (_isBlueField(red, green, blue)) {
          image.setPixelRgba(x, y, 0, 0, 0, 0);
        } else {
          image.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }
  }
}

img.Image? _trimNonTransparent(img.Image source) {
  var minX = source.width;
  var minY = source.height;
  var maxX = 0;
  var maxY = 0;
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      if (source.getPixel(x, y).aNormalized > 0.01) {
        if (x < minX) {
          minX = x;
        }
        if (y < minY) {
          minY = y;
        }
        if (x > maxX) {
          maxX = x;
        }
        if (y > maxY) {
          maxY = y;
        }
      }
    }
  }
  if (minX > maxX) {
    return null;
  }
  final w = maxX - minX + 1;
  final h = maxY - minY + 1;
  return img.copyCrop(source, x: minX, y: minY, width: w, height: h);
}

void main() {
  const sourcePath = "assets/images/CareShareInverted.png";
  const destPath = "assets/images/CareShareMark.png";

  final inFile = File(sourcePath);
  if (!inFile.existsSync()) {
    print("Missing $sourcePath");
    exit(1);
  }
  final bytes = inFile.readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    print("Could not decode $sourcePath");
    exit(1);
  }
  // Bake palette (and any sub-4ch) to real RGBA so setPixelRgba is linear colour.
  final img.Image image = decoded.palette != null || decoded.lengthInBytes < decoded.width * decoded.height * 4
      ? decoded.convert(numChannels: 4, format: img.Format.uint8, withPalette: false)
      : decoded;
  // Blue strokes on a white / cream rounded tile; remove the tile, keep a mask.
  const blueOnLightTile = true;
  _makeMask(image, blueOnLightTile: blueOnLightTile);
  final trimmed = _trimNonTransparent(image) ?? image;
  final out = File(destPath);
  out.writeAsBytesSync(img.encodePng(trimmed));
  print("Wrote $destPath ${trimmed.width}x${trimmed.height} (srcIn mask, theme tint in app)");
}
