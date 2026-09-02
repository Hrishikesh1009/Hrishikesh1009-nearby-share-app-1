import 'package:flutter/material.dart';

import '../../core/models/transfer_models.dart';

/// The transfer progress indicator UI anchor. Bound live to a
/// [TransferSession]'s [TransferProgress]: percentage (the linear bar),
/// instantaneous MB/s, and ETA, refreshed on every acknowledged chunk.
class TransferProgressCard extends StatelessWidget {
  const TransferProgressCard({super.key, required this.session});

  final TransferSession session;

  @override
  Widget build(BuildContext context) {
    final progress = session.progress;
    final verb = session.direction == TransferDirection.outgoing ? 'Sending' : 'Receiving';
    final preposition = session.direction == TransferDirection.outgoing ? 'to' : 'from';

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$verb ${session.manifest.fileName}',
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text('$preposition ${session.peer.name}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.fraction.clamp(0, 1),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(progress.fraction * 100).toStringAsFixed(0)}%'),
                Text('${progress.megabytesPerSecond.toStringAsFixed(1)} MB/s'),
                Text(_etaLabel(progress.eta)),
              ],
            ),
            if (session.status == TransferStatus.interrupted) ...[
              const SizedBox(height: 8),
              Text(
                'Connection lost — will resume from ${(progress.fraction * 100).toStringAsFixed(0)}% '
                'once the peer is back in range.',
                style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
              ),
            ],
            if (session.status == TransferStatus.failed) ...[
              const SizedBox(height: 8),
              Text(
                session.errorMessage ?? 'Transfer failed',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _etaLabel(Duration? eta) {
    if (eta == null) return '--:--';
    final minutes = eta.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = eta.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (eta.inHours > 0) {
      return '${eta.inHours}:$minutes:$seconds ETA';
    }
    return '$minutes:$seconds ETA';
  }
}
