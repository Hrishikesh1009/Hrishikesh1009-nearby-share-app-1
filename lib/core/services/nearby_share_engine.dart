import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../discovery/aggregated_discovery_service.dart';
import '../history/transfer_history_store.dart';
import '../models/peer_device.dart';
import '../models/transfer_models.dart';
import '../permissions/permission_service.dart';
import '../resume/resume_store.dart';
import '../security/file_hasher.dart';
import '../settings/app_settings_store.dart';
import '../transport/cancel_token.dart';
import '../transport/chunk_transfer.dart';
import '../transport/incoming_transfer_request.dart';
import '../transport/transfer_client.dart';
import '../transport/transfer_server.dart';

/// The single source of truth every screen binds to. Owns discovery, the
/// transfer server/client, resume state, settings and history — this is
/// the seam between network services and UI state: no screen touches a
/// socket, a discovery plugin, or the crypto layer directly.
///
/// UI anchors this maps onto:
///  - [peers]            -> Nearby tab's device list / radar
///  - [pendingRequest]    -> the incoming-file confirmation state of the transfer modal
///  - [outgoingBatch]     -> the sending/progress state of the transfer modal
///  - [history]/[settings] -> Home's Recent Activity, the History screen, Settings tab
class NearbyShareEngine extends ChangeNotifier {
  late final ResumeStore _resumeStore;
  late final TransferServer _transferServer;
  late final AggregatedDiscoveryService _discovery;
  late final TransferHistoryStore _historyStore;
  late final AppSettingsStore _settingsStore;

  StreamSubscription<List<PeerDevice>>? _peersSub;
  StreamSubscription<IncomingTransferRequest>? _requestsSub;

  List<PeerDevice> _peers = const [];
  List<PeerDevice> get peers => _peers;

  /// Raw discovery layers, exposed read-only for the Bluetooth tab, which
  /// (unlike the Nearby tab) needs literal BLE visibility rather than the
  /// cross-layer de-duplicated [peers] list.
  AggregatedDiscoveryService get discovery => _discovery;

  TransferHistoryStore get history => _historyStore;
  AppSettingsStore get settings => _settingsStore;

  IncomingTransferRequest? _pendingRequest;

  /// Non-null exactly when the incoming-file confirmation state should be
  /// showing.
  IncomingTransferRequest? get pendingRequest => _pendingRequest;

  CancelToken? _outgoingCancelToken;
  CancelToken? _incomingCancelToken;

  final Map<String, TransferSession> _sessions = {};
  List<TransferSession> get activeSessions => _sessions.values.toList(growable: false);

  BatchTransfer? _outgoingBatch;

  /// The current outgoing send — one or more files to one peer, matching
  /// the Share Sheet's multi-file selection. The transfer modal's
  /// "File X of Y" / overall progress / ETA are all derived from this.
  BatchTransfer? get outgoingBatch => _outgoingBatch;

  TransferSession? _incomingSession;

  /// The most recent incoming transfer, kept around (including its
  /// terminal status) until [dismissIncoming] is called — mirrors
  /// [outgoingBatch]'s `done` flag so the transfer modal can show a
  /// completed/failed incoming transfer's result instead of the overlay
  /// just vanishing the instant the last chunk lands.
  TransferSession? get incomingSession => _incomingSession;

  bool _ready = false;
  bool get isReady => _ready;

  // Guards `dispose()`: it's reachable before `start()` has assigned the
  // `late final` service fields below — a widget test that never calls
  // `start()`, or a real app closed while `start()` is still mid-flight
  // (permission prompt still showing, etc.) — and touching an
  // unassigned `late final` field throws `LateInitializationError` rather
  // than doing nothing. Set true the moment they're all assigned, not at
  // the end of `start()` (discovery's own `start()` call after this point
  // can still fail/hang independently — see its own try/catch per layer).
  bool _servicesInitialized = false;

  Future<void> start() async {
    if (_ready) return;
    await PermissionService.ensureAll();

    _resumeStore = await ResumeStore.open();
    _historyStore = await TransferHistoryStore.open();
    _settingsStore = await AppSettingsStore.open();
    _transferServer = await TransferServer.bind();
    _discovery = AggregatedDiscoveryService(transferPort: _transferServer.port);
    _servicesInitialized = true;

    _peersSub = _discovery.peers.listen((list) {
      _peers = list;
      notifyListeners();
    });
    _requestsSub = _transferServer.requests.listen(_onIncomingRequest);

    if (_settingsStore.discoverable) {
      await _discovery.start(localDeviceName: _settingsStore.deviceName);
    }
    _ready = true;
    notifyListeners();
  }

  // ---- Settings -----------------------------------------------------------

  Future<void> setDeviceName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _settingsStore.setDeviceName(trimmed);
    if (_settingsStore.discoverable) {
      await _restartDiscovery();
    }
    notifyListeners();
  }

  Future<void> setDiscoverable(bool value) async {
    await _settingsStore.setDiscoverable(value);
    if (value) {
      await _discovery.start(localDeviceName: _settingsStore.deviceName);
    } else {
      await _discovery.stop();
      _peers = const [];
    }
    notifyListeners();
  }

  Future<void> setSmartTransferEnabled(bool value) async {
    await _settingsStore.setSmartTransferEnabled(value);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await _settingsStore.setNotificationsEnabled(value);
    notifyListeners();
  }

  Future<void> setWifiSharePassword(String value) async {
    await _settingsStore.setWifiSharePassword(value);
    notifyListeners();
  }

  Future<void> _restartDiscovery() async {
    await _discovery.stop();
    await _discovery.start(localDeviceName: _settingsStore.deviceName);
  }

  // ---- Incoming -------------------------------------------------------------

  void _onIncomingRequest(IncomingTransferRequest request) {
    // One manifest, one decision at a time: a second simultaneous inbound
    // request simply waits on the sender's own 5-minute acceptance window
    // (see transfer_client.dart) rather than being queued here.
    _pendingRequest = request;
    notifyListeners();
  }

  /// Called by the transfer modal's Accept button.
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
    _incomingSession = session;
    notifyListeners();

    final cancelToken = CancelToken();
    _incomingCancelToken = cancelToken;
    final tracker = _RateTracker(session.manifest.fileSize);
    try {
      await request.accept(
        savePath,
        onProgress: (bytes) => _onProgress(session, tracker, bytes),
        cancelToken: cancelToken,
      );
      session.status = TransferStatus.completed;
      await _resumeStore.clear(session.id);
      await _historyStore.add(HistoryEntry(
        id: session.id,
        name: session.manifest.fileName,
        size: formatBytes(session.manifest.fileSize),
        peerName: peer.name,
        direction: HistoryDirection.received,
        timestamp: DateTime.now(),
      ));
    } on TransferCancelledException {
      session.status = TransferStatus.cancelled;
    } catch (e) {
      session.status = TransferStatus.failed;
      session.errorMessage = e.toString();
    } finally {
      if (identical(_incomingCancelToken, cancelToken)) _incomingCancelToken = null;
    }
    notifyListeners();
  }

  /// Called by the transfer modal's Decline button — gracefully terminates
  /// the socket without moving any file bytes.
  Future<void> declineIncoming() async {
    final request = _pendingRequest;
    if (request == null) return;
    _pendingRequest = null;
    await request.decline();
    notifyListeners();
  }

  // ---- Outgoing -------------------------------------------------------------

  /// Called from the Share Sheet's Send button: streams [files] to [peer]
  /// one at a time, tracked as a single [BatchTransfer] the transfer modal
  /// renders (title, "File X of Y", aggregate progress/ETA).
  Future<void> sendFiles(PeerDevice peer, List<File> files) async {
    if (files.isEmpty) return;

    var host = peer.host;
    var port = peer.port;
    var joinedNearbyGroup = false;

    if (host == null && peer.layer == TransportLayer.nearby && peer.nearbyEndpointId != null) {
      // Nearby-layer peers aren't dialable until we actually join their
      // Wi-Fi Direct group (see NearbyDiscoveryService's doc comment) —
      // mDNS/BLE peers already carry a resolved host/port from discovery
      // alone, but this layer's whole point is that discovery (BLE) and
      // the data-plane link (Wi-Fi Direct) are established separately.
      host = await _discovery.nearbyLayer.connectAndGetHostIp(peer.nearbyEndpointId!);
      port = _transferServer.port;
      joinedNearbyGroup = host != null;
    }

    if (host == null || port == null) {
      throw StateError(
        '${peer.name} has no reachable data layer yet '
        '(BLE-only peers are discovery/handshake only; wait for the Nearby '
        'or WiFi layer to resolve a socket address).',
      );
    }

    try {
      await _sendFilesTo(peer, files, host, port);
    } finally {
      if (joinedNearbyGroup) {
        // Restore normal Wi-Fi/internet connectivity now that the
        // transfer (or the attempt) is over.
        unawaited(_discovery.nearbyLayer.disconnectFromPeer());
      }
    }
  }

  Future<void> _sendFilesTo(PeerDevice peer, List<File> files, String host, int port) async {
    final sizes = await Future.wait(files.map((f) => f.length()));
    final totalBytes = sizes.fold<int>(0, (a, b) => a + b);
    final batch = BatchTransfer(peer: peer, files: files, totalBytes: totalBytes);
    _outgoingBatch = batch;
    notifyListeners();

    for (var i = 0; i < files.length; i++) {
      if (batch.cancelled) break;
      batch.currentIndex = i;
      final file = files[i];

      final sha256 = await FileHasher.sha256Hex(file);
      final manifest = TransferManifest(
        transferId: const Uuid().v4(),
        fileName: file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'file',
        fileSize: sizes[i],
        sha256Hex: sha256,
        chunkSize: kChunkSize,
      );
      final session = TransferSession(
        manifest: manifest,
        direction: TransferDirection.outgoing,
        peer: peer,
        sourcePath: file.path,
      );
      batch.currentSession = session;
      _sessions[session.id] = session;
      notifyListeners();

      final cancelToken = CancelToken();
      _outgoingCancelToken = cancelToken;
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
          cancelToken: cancelToken,
        );
        if (session.status == TransferStatus.completed) {
          await _resumeStore.clear(session.id);
          await _historyStore.add(HistoryEntry(
            id: session.id,
            name: manifest.fileName,
            size: formatBytes(manifest.fileSize),
            peerName: peer.name,
            direction: HistoryDirection.sent,
            timestamp: DateTime.now(),
          ));
        } else if (session.status == TransferStatus.declined) {
          batch.error = '${peer.name} declined the transfer';
          notifyListeners();
          break;
        }
      } on TransferCancelledException {
        session.status = TransferStatus.cancelled;
        batch.cancelled = true;
      } catch (e) {
        session.status = TransferStatus.failed;
        session.errorMessage = e.toString();
        batch.error = e.toString();
        notifyListeners();
        break;
      } finally {
        if (identical(_outgoingCancelToken, cancelToken)) _outgoingCancelToken = null;
      }
      batch.bytesCompletedBeforeCurrent += sizes[i];
    }

    batch.done = true;
    notifyListeners();
  }

  /// Called by the transfer modal's Cancel button, for whichever direction
  /// is currently active.
  void cancelCurrentTransfer() {
    _outgoingCancelToken?.cancel();
    _incomingCancelToken?.cancel();
    _outgoingBatch?.cancelled = true;
  }

  /// Dismisses a finished (or failed/cancelled) transfer modal.
  void dismissTransfer() {
    if (_outgoingBatch?.done ?? false) {
      _outgoingBatch = null;
    }
    final incoming = _incomingSession;
    if (incoming != null &&
        incoming.status != TransferStatus.transferring &&
        incoming.status != TransferStatus.connecting) {
      _incomingSession = null;
    }
    notifyListeners();
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
    if (_servicesInitialized) {
      unawaited(_discovery.stop());
      unawaited(_transferServer.close());
    }
    super.dispose();
  }
}

/// One or more files being sent to one peer, tracked as a unit — backs the
/// transfer modal's "File X of Y" and aggregate progress/ETA.
class BatchTransfer {
  BatchTransfer({required this.peer, required this.files, required this.totalBytes});

  final PeerDevice peer;
  final List<File> files;
  final int totalBytes;

  int currentIndex = 0;
  int bytesCompletedBeforeCurrent = 0;
  TransferSession? currentSession;
  bool done = false;
  bool cancelled = false;
  String? error;

  int get overallBytesTransferred =>
      bytesCompletedBeforeCurrent + (currentSession?.progress.bytesTransferred ?? 0);
  double get overallFraction => totalBytes == 0 ? 0 : overallBytesTransferred / totalBytes;
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
