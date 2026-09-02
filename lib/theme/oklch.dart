import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Converts an OKLCH color — exactly the color space the source design
/// (`WiFi & Bluetooth Sharing App.dc.html`) is authored in — to a Flutter
/// [Color]. Flutter's [Color] is plain sRGB with no OKLCH support, so
/// rather than eyeball a hex approximation of each `oklch(L C H)` token in
/// the design, this reproduces the exact CSS Color Module 4 conversion
/// (OKLCH -> OKLab -> linear sRGB -> gamma-encoded sRGB) so the app's
/// palette is mathematically the same color the design specifies.
///
/// [lightness] is 0-1, [chroma] is typically 0-0.4, [hue] is in degrees.
Color oklch(double lightness, double chroma, double hue, [double alpha = 1.0]) {
  final hueRad = hue * math.pi / 180;
  final a = chroma * math.cos(hueRad);
  final b = chroma * math.sin(hueRad);

  final l_ = lightness + 0.3963377774 * a + 0.2158037573 * b;
  final m_ = lightness - 0.1055613458 * a - 0.0638541728 * b;
  final s_ = lightness - 0.0894841775 * a - 1.2914855480 * b;

  final l = l_ * l_ * l_;
  final m = m_ * m_ * m_;
  final s = s_ * s_ * s_;

  final rLinear = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  final gLinear = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  final bLinear = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

  return Color.fromRGBO(
    _gammaEncode(rLinear),
    _gammaEncode(gLinear),
    _gammaEncode(bLinear),
    alpha,
  );
}

int _gammaEncode(double linear) {
  final clamped = linear.clamp(0.0, 1.0);
  final encoded =
      clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * math.pow(clamped, 1 / 2.4) - 0.055;
  return (encoded.clamp(0.0, 1.0) * 255).round();
}
