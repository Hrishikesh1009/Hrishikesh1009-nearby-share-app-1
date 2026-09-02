import 'dart:io';

import '../models/transfer_models.dart';
import 'cancel_token.dart';

/// What backs the "Accept File Confirmation" modal: a manifest has arrived
/// over an already-handshaked (encrypted) socket, and the UI must decide
/// before any file bytes move. Declining here gracefully terminates the
/// socket instead of leaving it hanging.
class IncomingTransferRequest {
  IncomingTransferRequest({
    required this.manifest,
    required this.peerAddress,
    required Future<void> Function(
      String savePath,
      void Function(int bytes) onProgress,
      CancelToken? cancelToken,
    ) onAccept,
    required Future<void> Function() onDecline,
  })  : _onAccept = onAccept,
        _onDecline = onDecline;

  final TransferManifest manifest;
  final InternetAddress peerAddress;

  final Future<void> Function(
    String savePath,
    void Function(int bytes) onProgress,
    CancelToken? cancelToken,
  ) _onAccept;
  final Future<void> Function() _onDecline;

  Future<void> accept(
    String savePath, {
    required void Function(int bytes) onProgress,
    CancelToken? cancelToken,
  }) =>
      _onAccept(savePath, onProgress, cancelToken);

  Future<void> decline() => _onDecline();
}
