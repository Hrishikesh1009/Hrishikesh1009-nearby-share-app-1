import 'dart:async';
import 'dart:io';

import '../models/transfer_models.dart';
import '../protocol/wire_protocol.dart';
import '../security/secure_channel.dart';
import 'chunk_transfer.dart';

/// Outgoing side of one transfer: dial the peer's transfer socket, hand
/// over the manifest, wait for a human on the other end to tap Accept or
/// Decline in their "Accept File Confirmation" modal, then stream.
class TransferClient {
  static Future<void> sendFile({
    required InternetAddress host,
    required int port,
    required File sourceFile,
    required TransferManifest manifest,
    required void Function(int bytesSent) onProgress,
    required void Function(TransferStatus status) onStatus,
  }) async {
    onStatus(TransferStatus.connecting);
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
    final channel = await SecureChannel.handshake(socket, isInitiator: true);

    try {
      onStatus(TransferStatus.awaitingAcceptance);
      await channel.send(encodeManifest(manifest.toJson()));

      // The other side of this wait is a human looking at a confirmation
      // dialog, not a server — give it real time.
      final response = await channel.packets
          .firstWhere((p) => p.type == PacketType.accept || p.type == PacketType.decline)
          .timeout(const Duration(minutes: 5));

      if (response.type == PacketType.decline) {
        onStatus(TransferStatus.declined);
        return;
      }

      final resumeOffset = decodeAcceptResumeOffset(response.body);
      onStatus(TransferStatus.transferring);
      await runSender(
        channel: channel,
        sourceFile: sourceFile,
        manifest: manifest,
        resumeOffset: resumeOffset,
        onProgress: onProgress,
      );
      onStatus(TransferStatus.completed);
    } finally {
      await channel.close();
    }
  }
}
