import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Small geometric glyphs reproducing the design's icon-less `<div>` shapes
/// (colored rounded squares, rotated diamonds, bar charts) exactly —
/// the design never uses an icon font or SVGs, just styled boxes.

/// A rounded square, used for the "Send Files" quick action and the Home
/// nav icon.
class RoundedSquareGlyph extends StatelessWidget {
  const RoundedSquareGlyph({super.key, required this.size, required this.radius, required this.color});

  final double size;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

/// A 45°-rotated rounded square — the Bluetooth glyph throughout the app
/// (quick action, nav icon).
class BluetoothGlyph extends StatelessWidget {
  const BluetoothGlyph({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45deg
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}

/// A ring with a filled center dot — the Nearby nav icon.
class RingDotGlyph extends StatelessWidget {
  const RingDotGlyph({super.key, required this.size, required this.color, this.dotSize = 6});

  final double size;
  final Color color;
  final double dotSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2.5),
      ),
      child: Container(
        width: dotSize,
        height: dotSize,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Ascending bar-chart glyph — the WiFi nav icon, the "Share WiFi" quick
/// action, and each found/paired device's signal-strength indicator (which
/// colors bars individually to show signal level).
class AscendingBars extends StatelessWidget {
  const AscendingBars({
    super.key,
    required this.heights,
    required this.colors,
    this.barWidth = 3,
    this.gap = 2,
  }) : assert(heights.length == colors.length);

  final List<double> heights;
  final List<Color> colors;
  final double barWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < heights.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Container(
            width: barWidth,
            height: heights[i],
            decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(1)),
          ),
        ],
      ],
    );
  }
}

/// Signal-strength bars for a device row: 1-3 bars lit in [AppColors.blue],
/// the rest dimmed, matching `foundDevices`'s `bar1/bar2/bar3` computation.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.strength});

  /// 0-3.
  final int strength;

  @override
  Widget build(BuildContext context) {
    final dim = AppColors.borderAlpha(0.15);
    return AscendingBars(
      heights: const [6, 10, 14],
      colors: [
        strength >= 1 ? AppColors.blue : dim,
        strength >= 2 ? AppColors.blue : dim,
        strength >= 3 ? AppColors.blue : dim,
      ],
    );
  }
}

/// The success checkmark shown when a transfer completes.
class CheckmarkGlyph extends StatelessWidget {
  const CheckmarkGlyph({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(children: [
        Positioned(
          top: 13,
          left: 1,
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(width: 11, height: 2.5, color: color),
          ),
        ),
        Positioned(
          top: 11,
          left: 6,
          child: Transform.rotate(
            angle: -0.785398,
            child: Container(width: 16, height: 2.5, color: color),
          ),
        ),
      ]),
    );
  }
}

/// The file glyph used in the Share Sheet's file rows.
class FileGlyph extends StatelessWidget {
  const FileGlyph({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15,
      height: 19,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// The back chevron on the History screen.
class BackChevronGlyph extends StatelessWidget {
  const BackChevronGlyph({super.key, this.color = AppColors.ink});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: color, width: 2),
            bottom: BorderSide(color: color, width: 2),
          ),
        ),
      ),
    );
  }
}

/// The password-visibility toggle glyph (a stylized eye outline).
class EyeGlyph extends StatelessWidget {
  const EyeGlyph({super.key, this.color = AppColors.ink});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 10,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

// Note: the design's WiFi tab QR is a decorative placeholder pattern
// (`buildQrCells()` in the source script — a deterministic pseudo-random
// grid, not a real QR code). This app renders an actual scannable code
// instead (`qr_flutter`, in `features/wifi/wifi_tab.dart`) at the same
// 140x140 size and container styling, since a guest genuinely needs to
// scan it — see `core/wifi/wifi_share_info.dart` for the payload.
