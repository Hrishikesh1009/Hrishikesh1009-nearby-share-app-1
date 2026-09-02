# Nearby Share

A zero-cloud, AirDrop-like local file-sharing app. Every byte moves
device-to-device over an encrypted local socket — there is no server, no
cloud relay, and no account. The UI implements the imported Claude Design
project (`WiFi & Bluetooth Sharing App.dc.html`) pixel-for-pixel: five tabs
(Home, Nearby, WiFi, Bluetooth, Settings), a History overlay, a Share
Sheet, and a transfer status modal.

## Architecture

```
lib/
├── theme/                design tokens copied from the source design
│   ├── oklch.dart         exact OKLCH -> sRGB conversion (the design's own color space)
│   └── design_tokens.dart AppColors / AppText / AppGradients / AppDurations
├── widgets/               small reusable pieces (RoundedCard, ToggleSwitch,
│                          AvatarBubble, the geometric icon glyphs)
├── core/
│   ├── models/            PeerDevice, TransferManifest/Session/Progress
│   ├── protocol/          binary wire protocol (length-framed packets)
│   ├── security/          X25519 + AES-256-GCM channel, streaming SHA-256
│   ├── discovery/         3 failover layers + one merged peer stream
│   ├── transport/         4MB chunked, ACK'd, resumable, cancellable send/receive
│   ├── resume/            on-disk byte-offset store
│   ├── history/           persisted transfer history (Home/History screens)
│   ├── settings/          persisted device name + feature toggles
│   ├── wifi/               real SSID + join-QR payload for the WiFi tab
│   ├── permissions/        one call to request everything the stack needs
│   └── services/           NearbyShareEngine — the network/UI seam
└── features/
    ├── shell/              AppShell: bottom nav + the three overlays
    ├── home/, nearby/, wifi/, bluetooth/, settings/   the five tabs
    ├── history/            the History overlay
    └── transfer/           the Share Sheet + the transfer status modal
```

`NearbyShareEngine` (`core/services/nearby_share_engine.dart`) is a single
`ChangeNotifier` and the only thing the UI touches for network state:
`peers` for the Nearby tab, `pendingRequest` for the incoming-file
confirmation, `outgoingBatch`/`incomingSession` for the transfer modal's
progress, `history`/`settings` for Home/History/Settings. No screen
imports a socket, a discovery plugin, or the crypto layer directly. Tab
selection, the History overlay, and Share Sheet visibility are ordinary
widget state in `features/shell/app_shell.dart` — that's UI-only
navigation, not network state, so it doesn't belong in the engine.

### Design fidelity

Every color, gradient, animation duration, and layout number in
`lib/theme/` and the tab widgets is taken directly from the source
`.dc.html`, not eyeballed — including reproducing its `oklch(...)` tokens
through the actual CSS Color Module 4 conversion math (`theme/oklch.dart`)
rather than approximating them as hex. The design's five `@keyframes`
(`radarPulse`, `spinSlow`, `fadeIn`, `sheetUp`, `popIn`, `gradientShift`)
are each reproduced with a Flutter `AnimationController`/`TweenAnimationBuilder`
equivalent.

One deliberate structural difference: the design's `390×844` rounded,
shadowed "phone" div is desktop-preview chrome for viewing a mobile mockup
in a browser — on a real device that's just the full screen, so the app's
`Scaffold` renders the design's *inner* content directly (padding, colors,
typography, bottom nav) rather than a smaller phone-shaped card floating
on a `#eae7e1` desktop background.

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
network segment; the two sides exchange their real listener host:port over
that session's own control channel, then dial our socket on it exactly the
same way — see `core/transport/local_address.dart`.

### Encrypted, non-HTTP data plane

`core/security/secure_channel.dart` implements an application-layer
encrypted channel rather than TLS/`SecureSocket`: there's no certificate
authority for ad-hoc device pairing, so instead each session does a fresh
X25519 ECDH handshake (forward secrecy), derives distinct per-direction
AES-256-GCM keys via HKDF, and seals every packet with a random 96-bit
nonce. `core/protocol/wire_protocol.dart` frames everything as
`[4-byte length][payload]` — a minimal, purpose-built binary protocol.

### Memory safety

`core/transport/chunk_transfer.dart` moves files in sequential 4MB chunks
via `RandomAccessFile.read`/`writeFrom`. Peak memory for a transfer is
bounded by the chunk size regardless of whether the file is 5KB or 5GB.
The pre-transfer manifest hash (`core/security/file_hasher.dart`) is
likewise a streaming SHA-256.

### Resume engine

1. The sender computes the file's SHA-256 and sends a manifest
   `{transferId, fileName, fileSize, sha256, chunkSize}`.
2. The receiver replies `ACCEPT` with `resumeOffset` — the current length
   of any partial file already on disk for that `transferId`. A chunk is
   only ever ACKed after `RandomAccessFile.flush()`, so file length and
   "safely received" are the same number — no separate bookkeeping needed.
3. The sender seeks to `resumeOffset` and streams 4MB at a time,
   stop-and-wait per chunk.
4. On a dropped socket, the partial file on disk already *is* the resume
   point; reconnecting re-runs the same manifest/accept handshake.
5. After the last chunk, the receiver hashes the whole reassembled file
   and replies `VERIFY_OK`/`VERIFY_FAIL`.

**Known scope limit:** integrity is checked once, over the whole file,
after completion — not per-chunk during resume. A per-chunk
Merkle/rolling-hash scheme would catch corruption earlier in a very long
transfer.

### Cancellation

`core/transport/cancel_token.dart` backs the transfer modal's real Cancel
button on both directions: cancelling closes the encrypted channel, which
unblocks whatever the sender/receiver loop was waiting on and ends the
transfer with a `cancelled` status rather than hanging.

## What each tab actually does, and its honest platform limits

The source design mocks a "Share anything, instantly" app whose Home/Nearby
screens are this app's real P2P file transfer (fully implemented, above).
Two of its tabs — WiFi hotspot sharing and Bluetooth device pairing — ask
for OS capabilities a sandboxed third-party app genuinely cannot have on
Android or iOS. Rather than fake them, each is implemented as honestly as
possible and the limit is documented in code:

- **WiFi tab** (`features/wifi/wifi_tab.dart`, `core/wifi/wifi_share_info.dart`):
  the network name is real (`network_info_plus`), and the join QR is a real,
  scannable `WIFI:` payload (`qr_flutter`) — but neither platform lets an
  app read the network's actual password back from the OS, so the QR
  encodes a password *you set* for guests, not the router's real PSK.
  "Personal Hotspot" can't be toggled programmatically by a third-party app
  on either platform; the switch reflects intent and explains that on tap
  rather than silently doing nothing.
- **Bluetooth tab** (`features/bluetooth/bluetooth_tab.dart`): "Available
  Devices" is real, live BLE scan results. "My Devices" is an app-local
  "devices I care about" list (`AppSettingsStore.pairedDeviceNames`) with
  live in-range status — not real OS Bluetooth pairing/bonding or another
  device's battery telemetry, neither of which a sandboxed app can read or
  perform. "Pair" adds to that list; toggling a row off forgets it.
- **Settings tab**: the Notifications toggle is a persisted preference
  only — it doesn't yet fire real local notifications (out of scope for
  this change; `flutter_local_notifications` would be the natural next
  step). WiFi/Bluetooth/Discoverable map onto real, distinct behavior:
  browsing on the mDNS/BLE layer vs. this device advertising itself.

## What's actually been verified

This was built without a Flutter toolchain, then a Flutter 3.47.2 SDK was
installed in the same sandbox specifically to check it — not just trust the
hand-written code. In order:

1. **`flutter pub get`** — the dependency versions first written (guessed
   from training knowledge, no live registry access) didn't all exist;
   every one was re-pinned against the real current pub.dev release
   (`flutter_nearby_connections`, `bonsoir`, `flutter_blue_plus`,
   `permission_handler`, `file_picker`, and others moved by 1-2 major
   versions). `pubspec.lock` is committed with the resolved set.
2. **`flutter analyze`** — clean (0 issues) after fixing real API drift:
   `bonsoir` 7.x's whole discovery-event API changed shape (no more
   `.ready`/`event.type`/`ResolvedBonsoirService` — see
   `core/discovery/mdns_discovery_service.dart` for the rewrite against the
   real sealed-event API), `file_picker` 12.x dropped the `.platform`
   singleton for plain static methods, and a couple of my own mistakes
   (`AccumulatorSink` is in `package:convert`, not `package:async`; a
   `library` directive placed after imports).
3. **`flutter test`** — a real widget test now passes; it originally caught
   a genuine bug: `NearbyShareEngine.dispose()` unconditionally touched
   `late final` service fields that are only assigned once `start()`
   completes, throwing `LateInitializationError` if disposed any earlier.
   Fixed with an explicit `_servicesInitialized` guard.
4. **`flutter build linux --debug` + actually running it** (Xvfb + the
   real GTK binary, screenshotted with `import`/`xdotool`) — the app
   launches, and all five tabs, the History overlay, gradients, and the
   real QR code render pixel-correct. This also surfaced a live bug class:
   `bonsoir`'s Avahi client, `flutter_blue_plus_linux`'s BlueZ client, and
   `network_info_plus`'s NetworkManager client can each throw *synchronously
   inside `Stream.listen()`* rather than rejecting an awaited `Future` —
   which silently escapes any `try/catch`/`.catchError()` around the call
   (this sandbox has no D-Bus daemon, so all three did). Fixed generally
   with a `runZonedGuarded` wrapper in `main.dart`, which is the correct
   backstop for exactly this error class rather than a workaround specific
   to this container.

Screenshots from that run — Home, Nearby (with the animated gradient
banner), WiFi (a real scannable QR), Bluetooth, Settings, and the History
overlay — all matched the source design.

## Known gaps (please read before relying on this)

- **Nothing here has run on an actual Android or iOS device or emulator**
  — this sandbox has neither SDK. The Linux desktop run above proves the
  Dart application code (all of `lib/`) compiles and runs correctly, and
  exercises the packages that ship a Linux implementation, but the
  Android/iOS-native sides of `flutter_nearby_connections`,
  `bonsoir_android`/`bonsoir_darwin`, `flutter_blue_plus_android`/`_darwin`,
  and `permission_handler`'s real runtime prompts are unverified. These are
  official plugin implementations, not code in this repo, but "compiles"
  isn't "works on a phone."
- **`NearbyShareEngine`'s Nearby-layer host/port resolution isn't wired
  up.** The design (exchange host/port over the Nearby/Multipeer session's
  control channel, see `core/transport/local_address.dart`) is decided,
  but the actual invite/accept + control-message calls against
  `flutter_nearby_connections` are left as a documented seam rather than
  guessed at blind — `flutter_nearby_connections` has no Linux
  implementation at all, so this seam specifically couldn't be exercised
  by the verification above either. Until it's filled in, sending to a
  Nearby-only peer (no mDNS host/port yet resolved) throws a clear error
  instead of hanging.
- **`android/` is hand-written, `ios/` platform project is not** — only
  `linux/` was generated and verified. iOS only has the `Info.plist` keys
  documented; run `flutter create .` on macOS to fill in the Xcode project
  (it won't touch existing `lib/`/`pubspec.yaml`/`android/`), then open
  `ios/Runner.xcworkspace` in Xcode to set a signing team.
- **iOS background execution is genuinely limited** — see the comment in
  `ios/Runner/Info.plist`.
- **Chunk pipelining.** The sender is intentionally stop-and-wait for a
  simple, exact resume story; a small in-flight window is the natural next
  step if profiling shows the per-chunk round-trip is the throughput
  ceiling.

## Running

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

`flutter run -d linux` works out of the box (verified above) if you want to
poke at the UI without any mobile hardware — Wi-Fi Direct/BLE/mDNS peer
discovery won't find anything without a real Avahi/BlueZ/NetworkManager
D-Bus stack, but every screen renders and navigates.

Android: `minSdk 26`, requires Android 13+ for full Nearby Wi-Fi permission
support (falls back to location-based scan permission below that).
iOS: run `flutter create .` on macOS first (see "Known gaps" above), then
open `ios/Runner.xcworkspace` in Xcode to set a signing team — Wi-Fi
Direct/Bluetooth discovery does not work in the simulator.
