import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../discovery/aggregated_discovery_service.dart';
import '../models/peer_device.dart';
import '../models/transfer_models.dart';
import '../permissions/permission_service.dart';
import '../resume/resume_store.dart';
import '../security/file_hasher.dart';
import '../transport/chunk_transfer.dart';
import '../transport/incoming_transfer_request.dart';
import '../transport/transfer_client.dart';
import '../transport/transfer_server.dart';

/// The single source of truth every screen binds to. Owns discovery, the
/// transfer server/client, resume state, and every [TransferSession] —
/// this is the seam between network services and UI state the integration
/// brief calls for: screens only read from / call methods on this class,
/// never touch sockets, discovery plugins, or crypto directly.
///
/// UI anchors this maps onto:
///  - [peers]           -> Nearby Devices / Radar screen's list
///  - [pendingRequest]  -> Accept File Confirmation modal (non-null = show it)
///  - [activeSessions]  -> the transfer progress indicator(s)
class NearbyShareEngine extends ChangeNotifier {
  NearbyShareEngine({String? localDeviceName})
      : _localDeviceName = localDeviceName ?? 'Device-${const Uuid().v4().substring(0, 4)}';

  final String _localDeviceName;
  late final ResumeStore _resumeStore;
  late final TransferServer _transferServer;
  late final AggregatedDiscoveryService _discovery;

  StreamSubscription<List<PeerDevice>>? _peersSub;
  StreamSubscription<IncomingTransferRequest>? _requestsSub;

  List<PeerDevice> _peers = const [];
  List<PeerDevice> get peers => _peers;

  IncomingTransferRequest? _pendingRequest;

  /// Non-null exactly when the Accept File Confirmation modal should be
  /// showing.
  IncomingTransferRequest? get pendingRequest => _pendingRequest;

  final Map<String, TransferSession> _sessions = {};
  List<TransferSession> get activeSessions => _sessions.values.toList(growable: false);

  TransferSession? get currentTransfer {
    for (final session in _sessions.values) {
      if (session.status == TransferStatus.transferring ||
          session.status == TransferStatus.connecting) {
        return session;
      }
    }
    return null;
  }

  bool _ready = false;
  bool get isReady => _ready;

  Future<void> start() async {
    if (_ready) return;
    await PermissionService.ensureAll();

    _resumeStore = await ResumeStore.open();
    _transferServer = await TransferServer.bind();
    _discovery = AggregatedDiscoveryService(transferPort: _transferServer.port);

    _peersSub = _discovery.peers.listen((list) {
      _peers = list;
      notifyListeners();
    });
    _requestsSub = _transferServer.requests.listen(_onIncomingRequest);

    await _discovery.start(localDeviceName: _localDeviceName);
    _ready = true;
    notifyListeners();
  }

  void _onIncomingRequest(IncomingTransferRequest request) {
    // One manifest, one decision at a time: a second simultaneous inbound
    // request simply waits on the sender's own 5-minute acceptance window
    // (see transfer_client.dart) rather than being queued here.
    _pendingRequest = request;
    notifyListeners();
  }

  /// Called by the Accept File Confirmation modal's Accept button.
  Future<void> acceptIncoming(String savePath) async {
    final request = _pendingRequest;
    if (request == null) return;
    _pendingRequest = null;

    final matchedPeer = _peers.where((p) => p.host == request.peerAddress.address);
    final peer = matchedPeer.isNotEmpty
        ? matchedPeer.first
        : PeerDevice(
            id: 'inbound:${request.peerAddress.address}',
            name: request.peerAddress.address,
            layer: TransportLayer.mdns,
            lastSeen: DateTime.now(),
            host: request.peerAddress.address,
          );

    final session = TransferSession(
      manifest: request.manifest,
      direction: TransferDirection.incoming,
      peer: peer,
      status: TransferStatus.transferring,
      savePath: savePath,
    );
    _sessions[session.id] = session;
    notifyListeners();

    final tracker = _RateTracker(session.manifest.fileSize);
    try {
      await request.accept(savePath, onProgress: (bytes) => _onProgress(session, tracker, bytes));
      session.status = TransferStatus.completed;
      await _resumeStore.clear(session.id);
    } catch (e) {
      session.status = TransferStatus.failed;
      session.errorMessage = e.toString();
    }
    notifyListeners();
  }

  /// Called by the Accept File Confirmation modal's Decline button —
  /// gracefully terminates the socket without moving any file bytes.
  Future<void> declineIncoming() async {
    final request = _pendingRequest;
    if (request == null) return;
    _pendingRequest = null;
    await request.decline();
    notifyListeners();
  }

  /// Called from the discovery/radar screen once the user has picked both
  /// a peer and a local file.
  Future<void> sendFile(PeerDevice peer, File file) async {
    final host = peer.host;
    final port = peer.port;
    if (host == null || port == null) {
      throw StateError(
        '${peer.name} has no reachable data layer yet '
        '(BLE-only peers are discovery/handshake only; wait for the Nearby '
        'or mDNS layer to resolve a socket address).',
      );
    }

    final fileSize = await file.length();
    final sha256 = await FileHasher.sha256Hex(file);
    final manifest = TransferManifest(
      transferId: const Uuid().v4(),
      fileName: file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'file',
      fileSize: fileSize,
      sha256Hex: sha256,
      chunkSize: kChunkSize,
    );

    final session = TransferSession(
      manifest: manifest,
      direction: TransferDirection.outgoing,
      peer: peer,
      sourcePath: file.path,
    );
    _sessions[session.id] = session;
    notifyListeners();

    final tracker = _RateTracker(manifest.fileSize);
    try {
      await TransferClient.sendFile(
        host: InternetAddress(host),
        port: port,
        sourceFile: file,
        manifest: manifest,
        onProgress: (bytes) => _onProgress(session, tracker, bytes),
        onStatus: (status) {
          session.status = status;
          notifyListeners();
        },
      );
      if (session.status == TransferStatus.completed) {
        await _resumeStore.clear(session.id);
      }
    } catch (e) {
      session.status = TransferStatus.failed;
      session.errorMessage = e.toString();
      notifyListeners();
    }
  }

  void _onProgress(TransferSession session, _RateTracker tracker, int bytesSoFar) {
    session.progress = tracker.sample(bytesSoFar);
    unawaited(_resumeStore.saveOffset(
      transferId: session.id,
      byteOffset: bytesSoFar,
      destinationPath: session.savePath ?? session.sourcePath ?? '',
      expectedSha256: session.manifest.sha256Hex,
      totalSize: session.manifest.fileSize,
    ));
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_peersSub?.cancel());
    unawaited(_requestsSub?.cancel());
    unawaited(_discovery.stop());
    unawaited(_transferServer.close());
    super.dispose();
  }
}

/// Smooths raw progress callbacks (which can fire in bursts) into the
/// instantaneous MB/s and ETA figures the progress indicator displays.
class _RateTracker {
  _RateTracker(this.totalBytes)
      : _lastTime = DateTime.now(),
        _lastBytes = 0;

  final int totalBytes;
  DateTime _lastTime;
  int _lastBytes;

  TransferProgress sample(int bytesSoFar) {
    final now = DateTime.now();
    final elapsedSeconds = now.difference(_lastTime).inMicroseconds / 1e6;
    final deltaBytes = bytesSoFar - _lastBytes;
    final instantaneous = elapsedSeconds > 0 ? deltaBytes / elapsedSeconds : 0.0;
    final remaining = totalBytes - bytesSoFar;
    final eta = instantaneous > 0 ? Duration(seconds: (remaining / instantaneous).round()) : null;

    _lastTime = now;
    _lastBytes = bytesSoFar;

    return TransferProgress(
      bytesTransferred: bytesSoFar,
      totalBytes: totalBytes,
      bytesPerSecond: instantaneous,
      eta: eta,
    );
  }
}
