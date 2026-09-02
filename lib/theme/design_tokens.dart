import 'package:flutter/material.dart';

import 'oklch.dart';

/// Every color, gradient and animation constant in this file is copied
/// directly from `WiFi & Bluetooth Sharing App.dc.html` (the source
/// design) — values, not vibes. Where the design used CSS `oklch(...)`,
/// [oklch] reproduces the exact conversion rather than an eyeballed hex.
class AppColors {
  AppColors._();

  /// The app's screen background (`#f7f5f1` in the design — the design's
  /// outer `#eae7e1` letterboxing is desktop-preview chrome for viewing a
  /// phone mockup and isn't part of the actual app screen).
  static const screenBg = Color(0xFFF7F5F1);
  static const cardBg = Color(0xFFFFFFFF);

  /// `#1c1b19` — both the primary text color and, inverted, the fill for
  /// dark buttons ("Scan for Devices", "Send", nav-icon "off" glyphs).
  static const ink = Color(0xFF1C1B19);

  static Color textAlpha(double a) => Color.fromRGBO(28, 27, 25, a);
  static Color borderAlpha(double a) => Color.fromRGBO(26, 26, 22, a);

  static final border = borderAlpha(0.08);
  static final inactiveGray = textAlpha(0.35);
  static final switchOffBg = borderAlpha(0.15);

  static final blue = oklch(0.55, 0.15, 250);
  static Color blueAlpha(double a) => oklch(0.55, 0.15, 250, a);
  static final violet = oklch(0.55, 0.15, 280);
  static Color violetAlpha(double a) => oklch(0.55, 0.15, 280, a);
  static final green = oklch(0.6, 0.15, 150);
  static Color greenAlpha(double a) => oklch(0.6, 0.15, 150, a);

  /// The "AI Gradient" palette — the design ships three, this app only
  /// wires up the default (`Blue → Violet`) since there's no design
  /// affordance to switch palettes from inside the running app.
  static final gradient1 = oklch(0.62, 0.16, 240);
  static final gradient2 = oklch(0.62, 0.16, 270);
  static final gradient3 = oklch(0.62, 0.16, 300);
}

class AppGradients {
  AppGradients._();

  /// The Smart Transfer banner's animated gradient (`gradientShift`
  /// keyframe: `background-position 0% -> 200% 50%` over 6s). Flutter has
  /// no background-position analog for gradients, so [shift] (0-1, driven
  /// by a repeating [AnimationController]) instead slides the gradient's
  /// begin/end alignment left-to-right, which reproduces the same "color
  /// sweeping across the banner" effect.
  static LinearGradient smartBanner(double shift) {
    final dx = -1.0 + 4.0 * shift; // sweeps a 3-color band across the banner
    return LinearGradient(
      begin: Alignment(dx - 1, 0),
      end: Alignment(dx + 1, 0),
      colors: [AppColors.gradient1, AppColors.gradient2, AppColors.gradient3],
    );
  }

  /// The radar's center dot (`linear-gradient(135deg, c1, c3)`), static.
  static final radarCenter = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.gradient1, AppColors.gradient3],
  );

  /// The sending-spinner ring (`conic-gradient(from 0deg, c1, c2, c3, c1)`),
  /// rotated continuously by `spinSlow` — the rotation is applied by the
  /// widget (a [RotationTransition]), this just supplies the static sweep.
  static final spinnerRing = SweepGradient(
    colors: [AppColors.gradient1, AppColors.gradient2, AppColors.gradient3, AppColors.gradient1],
  );
}

class AppText {
  AppText._();

  static final greetingLabel = TextStyle(fontSize: 14, color: AppColors.textAlpha(0.55));
  static const heading =
      TextStyle(fontSize: 25, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.15);
  static const sectionTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
  static final sectionLabelSmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.textAlpha(0.5),
    letterSpacing: 0.3,
  );
  static final cardLabelSmall =
      TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textAlpha(0.5));
  static const cardValue = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
  static final cardSub = TextStyle(fontSize: 12, color: AppColors.textAlpha(0.5));
  static const quickActionLabel =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2);
  static const itemTitle = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);
  static final itemSub = TextStyle(fontSize: 12, color: AppColors.textAlpha(0.5));
  static const itemDirection = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
  static const navLabel = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600);
  static const sheetTitle = TextStyle(fontSize: 17, fontWeight: FontWeight.w700);
  static final sheetSub = TextStyle(fontSize: 12.5, color: AppColors.textAlpha(0.5));
  static const historyTitle = TextStyle(fontSize: 19, fontWeight: FontWeight.w700);
  static const buttonLabel = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  static const shareButtonLabel = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700);
  static const settingsRowTitle = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600);
  static final settingsRowDesc = TextStyle(fontSize: 12.5, color: AppColors.textAlpha(0.5));
  static const transferTitle = TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700);
  static final transferSub = TextStyle(fontSize: 13, color: AppColors.textAlpha(0.55));
  static final transferFileProgress = TextStyle(fontSize: 12, color: AppColors.textAlpha(0.45));
  static final transferSpeed =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textAlpha(0.5));
  static const passwordText =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.5);
  static final deviceType = TextStyle(fontSize: 12, color: AppColors.textAlpha(0.5));
  static final version = TextStyle(fontSize: 12, color: AppColors.textAlpha(0.35));
}

/// Durations copied from the design's `@keyframes` declarations.
class AppDurations {
  AppDurations._();

  static const radarPulse = Duration(milliseconds: 1800);
  static const spinSlow = Duration(seconds: 1);
  static const fadeIn = Duration(milliseconds: 300);
  static const sheetUp = Duration(milliseconds: 280);
  static const popIn = Duration(milliseconds: 250);
  static const gradientShift = Duration(seconds: 6);
}
