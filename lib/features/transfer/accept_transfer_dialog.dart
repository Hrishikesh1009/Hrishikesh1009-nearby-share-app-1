import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/services/nearby_share_engine.dart';
import '../../core/transport/incoming_transfer_request.dart';

/// The "Accept File Confirmation" modal UI anchor. Shown by
/// [DiscoveryScreen] whenever `NearbyShareEngine.pendingRequest` becomes
/// non-null, i.e. exactly when a peer's TCP connection has delivered file
/// metadata (name, size, hash) and is waiting on a decision before any
/// bytes move.
class AcceptTransferDialog extends StatelessWidget {
  const AcceptTransferDialog({super.key, required this.request});

  final IncomingTransferRequest request;

  static Future<void> show(BuildContext context, IncomingTransferRequest request) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AcceptTransferDialog(request: request),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manifest = request.manifest;
    final engine = context.read<NearbyShareEngine>();

    return AlertDialog(
      icon: const Icon(Icons.file_present_rounded, size: 40),
      title: const Text('Incoming file'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(manifest.fileName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(_formatBytes(manifest.fileSize)),
          const SizedBox(height: 8),
          Text(
            'From ${request.peerAddress.address}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'SHA-256 ${manifest.sha256Hex.substring(0, 12)}…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        // Declining gracefully terminates the socket — no partial file is
        // ever created on disk.
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(engine.declineIncoming());
          },
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(context).pop();
            final dir = await getApplicationDocumentsDirectory();
            final savePath = '${dir.path}/${manifest.fileName}';
            unawaited(engine.acceptIncoming(savePath));
          },
          child: const Text('Accept'),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(1)} ${units[unit]}';
}
