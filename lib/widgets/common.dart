import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// A rounded, bordered white card — the design's one repeated container
/// (`background:#fff;border:1px solid rgba(26,26,22,0.08);border-radius:*`)
/// used for every list row, status card, and settings row.
class RoundedCard extends StatelessWidget {
  const RoundedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 16,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

/// The pill toggle switch used throughout (Bluetooth enable, hotspot,
/// per-device connected state, settings permissions): 44x26, a 20x20 knob
/// sliding between `left: 3` (off) and `left: 21` (on).
class ToggleSwitch extends StatelessWidget {
  const ToggleSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          color: value ? AppColors.blue : AppColors.switchOffBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            top: 3,
            left: value ? 21 : 3,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A circular initials avatar, alternating blue/violet by list index —
/// exactly `avatarFor(name, idx)` from the design's reference script.
class AvatarBubble extends StatelessWidget {
  const AvatarBubble({super.key, required this.name, required this.index, this.size = 40});

  final String name;
  final int index;
  final double size;

  bool get _isBlue => index % 2 == 0;

  @override
  Widget build(BuildContext context) {
    final color = _isBlue ? AppColors.blue : AppColors.violet;
    final bg = _isBlue ? AppColors.blueAlpha(0.12) : AppColors.violetAlpha(0.12);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(fontSize: size * 0.375, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// The dark, full-width pill button (`Scan for Devices`, `Send`,
/// `Cancel`/`Done` on the transfer modal).
class DarkPillButton extends StatelessWidget {
  const DarkPillButton({super.key, required this.label, required this.onTap, this.expand = false});

  final String label;
  final VoidCallback? onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: Text(label, style: AppText.buttonLabel.copyWith(color: Colors.white)),
      ),
    );
    return expand ? Expanded(child: button) : button;
  }
}

/// The light, full-width pill button (`Cancel` on the Share Sheet, row
/// actions on Settings/History back).
class LightPillButton extends StatelessWidget {
  const LightPillButton({super.key, required this.label, required this.onTap, this.expand = false});

  final String label;
  final VoidCallback? onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration:
            BoxDecoration(color: AppColors.borderAlpha(0.06), borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: Text(label, style: AppText.buttonLabel),
      ),
    );
    return expand ? Expanded(child: button) : button;
  }
}
