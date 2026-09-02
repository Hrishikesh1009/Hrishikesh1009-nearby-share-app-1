# Nearby Share

A zero-cloud, AirDrop-like local file-sharing app. Every byte moves
device-to-device over an encrypted local socket — there is no server, no
cloud relay, and no account.

## Design import — what happened

This repository was set up to integrate against a Claude Design project
(`WiFi & Bluetooth Sharing App.dc.html`, importing `support.js`) for the
three screens described in the integration brief: a Nearby
Devices/Radar discovery screen, an Accept File Confirmation modal, and a
transfer progress indicator. The `claude_design` MCP tool needed to fetch
that project requires a design-login authorization that this headless
session doesn't have, and the fallback paths (`/design-login` run
interactively, "Send to Claude Code Web", or pasting the file content)
weren't available either in this session.

So: **the backend below is real and complete; the three screens under
`lib/features/` are functional placeholders**, not the actual design.
They implement exactly the anchors the brief specifies and bind to the
exact same `NearbyShareEngine` state the real screens will, so swapping
them for the actual design is a UI-only change — nothing under `lib/core/`
needs to move.

To finish the integration once the design is available: get its `.dc.html`
+ `support.js` into a session that *can* reach the design MCP (or paste the
content directly), then rebuild `lib/features/discovery/discovery_screen.dart`,
`lib/features/transfer/accept_transfer_dialog.dart`, and
`lib/features/transfer/transfer_progress_card.dart` against it, keeping
their existing `Provider`/`NearbyShareEngine` bindings intact.

## Architecture

```
lib/
├── core/
│   ├── models/          PeerDevice, TransferManifest/Session/Progress
│   ├── protocol/        binary wire protocol (length-framed packets)
│   ├── security/        X25519 + AES-256-GCM channel, streaming SHA-256
│   ├── discovery/       3 failover layers + one merged peer stream
│   ├── transport/       4MB chunked, ACK'd, resumable send/receive
│   ├── resume/          on-disk byte-offset store
│   ├── permissions/     one call to request everything the stack needs
│   └── services/        NearbyShareEngine — the network/UI seam
└── features/
    ├── discovery/       Nearby Devices / Radar screen (placeholder UI)
    └── transfer/        Accept File modal + progress card (placeholder UI)
```

`NearbyShareEngine` (`core/services/nearby_share_engine.dart`) is a single
`ChangeNotifier` and the only thing the UI ever touches: `peers` for the
radar list, `pendingRequest` for the accept modal, `activeSessions` /
`currentTransfer` for the progress indicator. No screen imports a socket,
a discovery plugin, or the crypto layer directly.

### Failover connection stack

| Layer | Purpose | Package |
|---|---|---|
| 1. Wi-Fi Direct / Multipeer | OS-managed high-throughput link, preferred | `flutter_nearby_connections` |
| 2. mDNS / Bonjour | Zero-config discovery on the local router network | `bonsoir` |
| 3. Bluetooth LE | Discovery/handshake only, never the file stream | `flutter_blue_plus` |

All three run concurrently (`AggregatedDiscoveryService`); a peer visible on
more than one layer is de-duplicated with layer 1 preferred. **The file
bytes always travel over our own raw `dart:io.Socket`** (`core/transport/`)
— never through a plugin's own message channel and never over HTTP or
WebSockets. On Layer 2 that socket dials the mDNS-advertised host:port
directly. On Layer 1, the OS-managed session establishes a shared local
network segment (a Wi-Fi Direct group or Multipeer-bridged link); the two
sides exchange their real listener host:port over that session's own
control channel, then dial our socket on it exactly the same way — see
`core/transport/local_address.dart`.

### Encrypted, non-HTTP data plane

`core/security/secure_channel.dart` implements an application-layer
encrypted channel rather than TLS/`SecureSocket`: there's no certificate
authority for ad-hoc device pairing, so instead each session does a fresh
X25519 ECDH handshake (forward secrecy — the keys are never persisted),
derives distinct per-direction AES-256-GCM keys via HKDF, and seals every
packet with a random 96-bit nonce. `core/protocol/wire_protocol.dart` frames
everything as `[4-byte length][payload]` — a minimal, purpose-built binary
protocol, not HTTP request/response and not a WebSocket handshake.

### Memory safety

`core/transport/chunk_transfer.dart` moves files in sequential 4MB chunks
via `RandomAccessFile.read`/`writeFrom`. Peak memory for a transfer is
bounded by the chunk size regardless of whether the file is 5KB or 5GB —
nothing reads a whole file into a buffer. The pre-transfer manifest hash
(`core/security/file_hasher.dart`) is likewise a streaming SHA-256, not a
`readAsBytes()`.

### Resume engine

1. Before any bytes move, the sender computes the file's SHA-256 and sends
   a manifest `{transferId, fileName, fileSize, sha256, chunkSize}`.
2. The receiver replies `ACCEPT` with a `resumeOffset` — the current length
   of any partial file already on disk for that `transferId` (0 for a fresh
   transfer). The on-disk file length is treated as ground truth for
   resume, not a separate counter, because a chunk is only ever ACKed
   *after* it's flushed to disk (see below) — so length and "safely
   received" are the same number.
3. The sender seeks to `resumeOffset` and streams from there, one 4MB chunk
   at a time, waiting for a `CHUNK_ACK` (sent only after
   `RandomAccessFile.flush()`) before sending the next chunk.
4. If the socket drops mid-transfer, nothing needs to be explicitly
   "saved" — the partial file on disk already *is* the resume point. On
   reconnection the same manifest/accept handshake runs again and picks up
   exactly where it left off.
5. After the last chunk, the receiver hashes the complete reassembled file
   and replies `VERIFY_OK`/`VERIFY_FAIL` against the manifest's SHA-256.

`core/resume/resume_store.dart` additionally persists offset/progress as a
convenience cache for the UI (so a killed-and-relaunched app can show "43%
sent" before a socket even reconnects) — it is not the resume mechanism's
source of truth.

**Known scope limit:** integrity is checked once, over the whole
reassembled file, after the transfer completes — not per-chunk during
resume. A per-chunk Merkle/rolling-hash scheme would catch a corrupted
chunk earlier in a very long transfer; it's a reasonable follow-up, flagged
here rather than silently assumed.

## Known gaps (please read before relying on this)

- **No Flutter/Dart SDK was available in the sandbox this was written in.**
  Nothing here has been run through `flutter pub get`, `flutter analyze`,
  or a build. Run those first — third-party plugin API surfaces
  (`flutter_nearby_connections` in particular) can drift between versions,
  and `core/discovery/nearby_discovery_service.dart` is the one file most
  likely to need small signature adjustments.
- **`NearbyShareEngine._resolveNearbyEndpoint` isn't wired up.** The
  design (host/port exchanged over the Nearby/Multipeer session, see
  `local_address.dart`'s doc comment) is decided, but the actual
  invite/accept + control-message calls against
  `flutter_nearby_connections` are left as a documented seam rather than
  guessed at blind. Until it's filled in, `sendFile` to a Nearby-only peer
  (no mDNS host/port yet resolved) throws a clear "no reachable data layer
  yet" error instead of silently hanging.
- **`android/` is hand-written, `ios/` is not.** The Android Gradle files
  here are enough to build; the iOS platform folder only has the
  `Info.plist` keys documented (Xcode's `.pbxproj` isn't practical to
  hand-author correctly). Run `flutter create .` once you have the SDK —
  it fills in missing platform folders without touching existing `lib/`
  or `pubspec.yaml`, then merge the `Info.plist` keys already written here.
- **iOS background execution is genuinely limited.** The
  `bluetooth-central`/`bluetooth-peripheral` background modes keep BLE
  handshakes alive briefly; they do not grant indefinite background
  execution for an in-progress TCP file stream. That's an iOS platform
  constraint, not a gap in this code — see the comment in
  `ios/Runner/Info.plist`.
- **Chunk pipelining.** The sender is intentionally stop-and-wait (one
  in-flight chunk, ACK before the next) for a simple, exact resume story.
  If profiling on real hardware shows the per-chunk round-trip is the
  throughput ceiling, a small in-flight window is the natural next step.

## Running

```bash
flutter pub get
flutter analyze
flutter run
```

Android: `minSdk 26`, requires Android 13+ for full Nearby Wi-Fi permission
support (falls back to location-based scan permission below that).
iOS: run `flutter create .` first (see "Known gaps" above), then open
`ios/Runner.xcworkspace` in Xcode to set a signing team before running on
a device — Wi-Fi Direct/Bluetooth discovery does not work in the
simulator.
