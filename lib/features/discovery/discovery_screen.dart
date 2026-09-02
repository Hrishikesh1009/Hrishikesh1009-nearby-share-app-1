import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/peer_device.dart';
import '../../core/models/transfer_models.dart';
import '../../core/services/nearby_share_engine.dart';
import '../transfer/accept_transfer_dialog.dart';
import '../transfer/transfer_progress_card.dart';

/// Nearby Devices / Radar screen — the discovery UI anchor. Peers appear
/// and disappear live as `NearbyShareEngine.peers` changes (driven by the
/// three failover discovery layers), with no polling on the UI side.
///
/// This is a functional placeholder built to the brief's described anchors
/// (radar of nearby devices, tap-to-send, live progress card), not the
/// final visual design — the actual Claude Design screens for this project
/// couldn't be imported into this session (see README "Design import").
/// Swap this screen's body for the real layout without touching anything
/// under `core/` — that boundary is exactly what `NearbyShareEngine` exists
/// to protect.
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  bool _dialogShowing = false;

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<NearbyShareEngine>();

    final pending = engine.pendingRequest;
    if (pending != null && !_dialogShowing) {
      _dialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await AcceptTransferDialog.show(context, pending);
        _dialogShowing = false;
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Share'),
        actions: [
          if (!engine.isReady)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _Radar(
              peers: engine.peers,
              onTapPeer: (peer) => _pickAndSend(context, peer),
            ),
          ),
          for (final session in engine.activeSessions)
            if (const {
              TransferStatus.transferring,
              TransferStatus.connecting,
              TransferStatus.interrupted,
              TransferStatus.failed,
            }.contains(session.status))
              TransferProgressCard(session: session),
        ],
      ),
    );
  }

  Future<void> _pickAndSend(BuildContext context, PeerDevice peer) async {
    final result = await FilePicker.platform.pickFiles(withReadStream: false);
    final path = result?.files.single.path;
    if (path == null) return;

    final engine = context.read<NearbyShareEngine>();
    try {
      await engine.sendFile(peer, File(path));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _Radar extends StatelessWidget {
  const _Radar({required this.peers, required this.onTapPeer});

  final List<PeerDevice> peers;
  final void Function(PeerDevice) onTapPeer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide * 0.85;
        final center = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
        final radius = side / 2;

        return Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(side, side),
              painter: _RadarRingsPainter(Theme.of(context).colorScheme.primary),
            ),
            const CircleAvatar(radius: 24, child: Icon(Icons.smartphone)),
            for (var i = 0; i < peers.length; i++)
              _PeerBubble(
                peer: peers[i],
                center: center,
                radius: radius,
                angle: (2 * math.pi * i) / peers.length,
                onTap: () => onTapPeer(peers[i]),
              ),
            if (peers.isEmpty)
              Positioned(
                bottom: 0,
                child: Text(
                  'Searching for nearby devices…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PeerBubble extends StatelessWidget {
  const _PeerBubble({
    required this.peer,
    required this.center,
    required this.radius,
    required this.angle,
    required this.onTap,
  });

  final PeerDevice peer;
  final Offset center;
  final double radius;
  final double angle;
  final VoidCallback onTap;

  static const double _bubbleSize = 56;

  @override
  Widget build(BuildContext context) {
    final dx = center.dx + radius * math.cos(angle) - _bubbleSize / 2;
    final dy = center.dy + radius * math.sin(angle) - _bubbleSize / 2;

    return Positioned(
      left: dx,
      top: dy,
      width: _bubbleSize + 24,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: _bubbleSize / 2,
              backgroundColor: _layerColor(peer.layer),
              child: Text(
                peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              peer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Color _layerColor(TransportLayer layer) => switch (layer) {
        TransportLayer.nearby => Colors.greenAccent.shade400,
        TransportLayer.mdns => Colors.lightBlueAccent.shade400,
        TransportLayer.ble => Colors.orangeAccent.shade400,
      };
}

class _RadarRingsPainter extends CustomPainter {
  _RadarRingsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final center = size.center(Offset.zero);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, size.width / 2 * i / 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarRingsPainter oldDelegate) => oldDelegate.color != color;
}
