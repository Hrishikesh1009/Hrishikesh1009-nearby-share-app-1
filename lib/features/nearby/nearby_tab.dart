import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/peer_device.dart';
import '../../core/services/nearby_share_engine.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/icons.dart';

/// The Nearby tab — the design's "Nearby Devices" / radar screen and the
/// primary discovery UI anchor. [NearbyShareEngine.peers] is populated
/// continuously by the three failover discovery layers the moment the app
/// starts (see `core/discovery/`), so "Scan"/"Rescan" here is a UI gesture
/// that plays the radar-pulse animation and reveals the (already live)
/// list, rather than a one-shot scan our backend doesn't otherwise do.
class NearbyTab extends StatefulWidget {
  const NearbyTab({super.key, required this.onShare});

  final void Function(PeerDevice peer) onShare;

  @override
  State<NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends State<NearbyTab> with SingleTickerProviderStateMixin {
  late final AnimationController _radarController;
  bool _scanning = false;
  bool _hasScannedOnce = false;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(vsync: this, duration: AppDurations.radarPulse)..repeat();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() => _scanning = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _hasScannedOnce = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<NearbyShareEngine>();
    final peers = engine.peers;
    final devicesFound = _hasScannedOnce && peers.isNotEmpty;
    final showScanButton = !_scanning && !_hasScannedOnce;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nearby Devices', style: AppText.heading),
        const SizedBox(height: 4),
        Text('Devices in range are shown below', style: AppText.greetingLabel),
        const SizedBox(height: 14),
        if (engine.settings.smartTransferEnabled) const _SmartTransferBanner(),
        Center(
          child: Column(children: [
            SizedBox(
              width: 170,
              height: 170,
              child: Stack(alignment: Alignment.center, children: [
                if (_scanning)
                  AnimatedBuilder(
                    animation: _radarController,
                    builder: (context, _) => Stack(alignment: Alignment.center, children: [
                      _RadarRing(phase: _radarController.value),
                      _RadarRing(phase: (_radarController.value + 1 / 3) % 1.0),
                      _RadarRing(phase: (_radarController.value + 2 / 3) % 1.0),
                    ]),
                  ),
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.blueAlpha(0.12), shape: BoxShape.circle),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(gradient: AppGradients.radarCenter, shape: BoxShape.circle),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            if (showScanButton) DarkPillButton(label: 'Scan for Devices', onTap: _startScan),
            if (_scanning)
              Text('Scanning nearby…', style: AppText.greetingLabel.copyWith(fontWeight: FontWeight.w600)),
            if (devicesFound)
              GestureDetector(
                onTap: _startScan,
                child: Text(
                  'Devices found · Rescan',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.blue),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 28),
        if (devicesFound)
          Column(
            children: [
              for (final peer in peers) _DeviceRow(peer: peer, onShare: () => widget.onShare(peer)),
            ],
          ),
      ],
    );
  }
}

class _SmartTransferBanner extends StatefulWidget {
  const _SmartTransferBanner();

  @override
  State<_SmartTransferBanner> createState() => _SmartTransferBannerState();
}

class _SmartTransferBannerState extends State<_SmartTransferBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.gradientShift)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: AppGradients.smartBanner(_controller.value),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Smart Transfer on — Bluetooth finds devices, WiFi Direct moves the file',
              style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One `radarPulse` ring: scale 0.4->1, opacity 0.7->0 over its phase.
class _RadarRing extends StatelessWidget {
  const _RadarRing({required this.phase});

  final double phase;

  @override
  Widget build(BuildContext context) {
    // `phase` is always in [0, 1), so this is already within (0, 0.7] —
    // no clamp needed (and `num.clamp` returns `num`, not the `double`
    // `Opacity.opacity` wants, so it'd need a cast anyway).
    return Opacity(
      opacity: 0.7 * (1 - phase),
      child: Transform.scale(
        scale: 0.4 + 0.6 * phase,
        child: Container(
          width: 170,
          height: 170,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.blue, width: 2)),
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.peer, required this.onShare});

  final PeerDevice peer;
  final VoidCallback onShare;

  String get _layerLabel => switch (peer.layer) {
        TransportLayer.nearby => 'Wi-Fi Direct',
        TransportLayer.mdns => 'Local network',
        TransportLayer.ble => 'Bluetooth',
      };

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        AvatarBubble(name: peer.name, index: peer.avatarSeed),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(peer.name, style: AppText.itemTitle),
              Text(_layerLabel, style: AppText.deviceType),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: SignalBars(strength: peer.signalBars),
        ),
        GestureDetector(
          onTap: onShare,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: AppColors.blueAlpha(0.12), borderRadius: BorderRadius.circular(10)),
            child: Text('Share', style: AppText.shareButtonLabel.copyWith(color: AppColors.blue)),
          ),
        ),
      ]),
    );
  }
}
