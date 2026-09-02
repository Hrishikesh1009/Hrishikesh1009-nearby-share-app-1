import 'dart:async';
import 'dart:io';

import '../models/transfer_models.dart';
import '../protocol/wire_protocol.dart';
import '../security/secure_channel.dart';
import 'chunk_transfer.dart';
import 'incoming_transfer_request.dart';

/// Listens for incoming transfer connections on both failover data-plane
/// layers at once — a peer discovered via mDNS dials our advertised
/// LAN host:port directly; a peer discovered via Nearby/Multipeer learns
/// our host:port through that layer's own control channel first (see
/// `core/discovery/nearby_discovery_service.dart`) and then dials the same
/// listener. Either way, this is the one place raw file bytes ever land.
class TransferServer {
  TransferServer._(this._serverSocket);

  final ServerSocket _serverSocket;
  final _requestsController = StreamController<IncomingTransferRequest>.broadcast();

  int get port => _serverSocket.port;
  Stream<IncomingTransferRequest> get requests => _requestsController.stream;

  static Future<TransferServer> bind({int port = 0}) async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    final instance = TransferServer._(server);
    server.listen(instance._onConnection, onError: (_) {});
    return instance;
  }

  void _onConnection(Socket socket) {
    unawaited(_handleConnection(socket));
  }

  Future<void> _handleConnection(Socket socket) async {
    SecureChannel? channel;
    try {
      channel = await SecureChannel.handshake(socket, isInitiator: false);

      final manifestPacket = await channel.packets
          .firstWhere((p) => p.type == PacketType.manifest)
          .timeout(const Duration(seconds: 20));
      final manifest = TransferManifest.fromJson(decodeManifest(manifestPacket.body));
      final activeChannel = channel;

      _requestsController.add(IncomingTransferRequest(
        manifest: manifest,
        peerAddress: socket.remoteAddress,
        onAccept: (savePath, onProgress) async {
          final file = File(savePath);
          // The on-disk file length is ground truth for resume — not the
          // JSON resume-store cache, which only records intent. A chunk is
          // never acked until it is flushed to disk, so length == offset.
          final resumeOffset = await file.exists() ? await file.length() : 0;
          await activeChannel.send(encodeAccept(resumeOffset));
          try {
            await runReceiver(
              channel: activeChannel,
              destinationFile: file,
              manifest: manifest,
              onProgress: onProgress,
            );
          } finally {
            await activeChannel.close();
          }
        },
        onDecline: () async {
          await activeChannel.send(encodeDecline());
          await activeChannel.close();
        },
      ));
    } catch (_) {
      await channel?.close();
      await socket.close();
    }
  }

  Future<void> close() async {
    await _requestsController.close();
    await _serverSocket.close();
  }
}
