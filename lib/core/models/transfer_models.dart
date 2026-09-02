import 'peer_device.dart';

/// The manifest sent before any file bytes: what the receiver is being
/// asked to accept. [sha256Hex] is computed by streaming the whole file
/// through SHA-256 up front (see `core/security/file_hasher.dart`) — it is
/// never held in memory as a single buffer.
class TransferManifest {
  const TransferManifest({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.sha256Hex,
    required this.chunkSize,
  });

  final String transferId;
  final String fileName;
  final int fileSize;
  final String sha256Hex;
  final int chunkSize;

  Map<String, dynamic> toJson() => {
        'transferId': transferId,
        'fileName': fileName,
        'fileSize': fileSize,
        'sha256': sha256Hex,
        'chunkSize': chunkSize,
      };

  factory TransferManifest.fromJson(Map<String, dynamic> json) => TransferManifest(
        transferId: json['transferId'] as String,
        fileName: json['fileName'] as String,
        fileSize: json['fileSize'] as int,
        sha256Hex: json['sha256'] as String,
        chunkSize: json['chunkSize'] as int,
      );
}

enum TransferDirection { outgoing, incoming }

enum TransferStatus {
  /// Manifest sent/received, waiting on the receiver to tap Accept/Decline.
  awaitingAcceptance,
  connecting,
  transferring,

  /// Socket dropped mid-stream; the byte offset is safe in the resume
  /// store and the session will pick up from there once reconnected.
  interrupted,
  verifying,
  completed,
  failed,
  declined,
  cancelled,
}

/// A smoothed instantaneous-throughput sample the progress UI binds to.
class TransferProgress {
  const TransferProgress({
    required this.bytesTransferred,
    required this.totalBytes,
    required this.bytesPerSecond,
    required this.eta,
  });

  final int bytesTransferred;
  final int totalBytes;
  final double bytesPerSecond;
  final Duration? eta;

  double get fraction => totalBytes == 0 ? 0 : bytesTransferred / totalBytes;
  double get megabytesPerSecond => bytesPerSecond / (1024 * 1024);

  static const zero = TransferProgress(
    bytesTransferred: 0,
    totalBytes: 0,
    bytesPerSecond: 0,
    eta: null,
  );
}

/// One file transfer, in either direction, as tracked by [NearbyShareEngine].
class TransferSession {
  TransferSession({
    required this.manifest,
    required this.direction,
    required this.peer,
    this.status = TransferStatus.awaitingAcceptance,
    this.savePath,
    this.sourcePath,
  }) : progress = TransferProgress(
          bytesTransferred: 0,
          totalBytes: manifest.fileSize,
          bytesPerSecond: 0,
          eta: null,
        );

  final TransferManifest manifest;
  final TransferDirection direction;
  final PeerDevice peer;

  TransferStatus status;
  TransferProgress progress;
  String? errorMessage;

  /// Where an incoming file is being written on disk.
  String? savePath;

  /// The local file being read for an outgoing transfer.
  String? sourcePath;

  String get id => manifest.transferId;
}
