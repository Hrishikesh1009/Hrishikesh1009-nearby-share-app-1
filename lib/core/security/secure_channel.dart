import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../protocol/wire_protocol.dart';

/// An encrypted, application-layer channel over a raw [Socket].
///
/// We deliberately do not use `SecureSocket`/TLS here: there is no
/// certificate authority for ad-hoc device pairing, and self-signed
/// certificate management adds real complexity for no benefit on a link
/// that is only ever a direct socket between two peers on the same LAN or
/// Wi-Fi Direct group. Instead:
///
/// 1. Both sides generate a fresh, ephemeral X25519 key pair and exchange
///    public keys in one plaintext HELLO frame (forward secrecy: the keys
///    are never persisted and are discarded when the channel closes).
/// 2. The shared secret is fed through HKDF-SHA256 twice, once per
///    direction, so the initiator's write key and the responder's write
///    key are different — no risk of nonce reuse across directions.
/// 3. Every packet after that is sealed with AES-256-GCM using a random
///    96-bit nonce per frame, then outer-framed as
///    `[len][nonce(12)][ciphertext][tag(16)]`.
class SecureChannel {
  SecureChannel._(this._socket, this._sendKey, this._recvKey, this._splitter);

  final Socket _socket;
  final SecretKey _sendKey;
  final SecretKey _recvKey;
  final FrameSplitter _splitter;

  static final AesGcm _aead = AesGcm.with256bits();
  static final X25519 _kx = X25519();

  StreamSubscription<Uint8List>? _rawSub;
  bool _closed = false;

  /// Performs the HELLO/X25519 handshake over [socket] and returns a ready
  /// channel. [isInitiator] must be true on exactly one side of the
  /// connection (the side that dialed out) so the two directions derive
  /// distinct keys.
  static Future<SecureChannel> handshake(Socket socket, {required bool isInitiator}) async {
    final keyPair = await _kx.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();

    final splitter = FrameSplitter();
    final sub = socket.listen(
      splitter.addChunk,
      onDone: () => unawaited(splitter.close()),
      onError: (Object _, StackTrace __) => unawaited(splitter.close()),
      cancelOnError: true,
    );

    socket.add(encodeHello(Uint8List.fromList(publicKey.bytes)));

    final helloPayload = await splitter.frames.first.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('peer did not send HELLO in time'),
    );
    final decoded = decodeFrame(helloPayload);
    if (decoded.type != PacketType.hello) {
      throw StateError('expected HELLO, got ${decoded.type}');
    }
    final remotePublicKey = SimplePublicKey(decoded.body, type: KeyPairType.x25519);

    final shared = await _kx.sharedSecretKey(keyPair: keyPair, remotePublicKey: remotePublicKey);
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final initiatorToResponder = await hkdf.deriveKey(
      secretKey: shared,
      info: 'nearby-share:initiator->responder'.codeUnits,
      nonce: const [],
    );
    final responderToInitiator = await hkdf.deriveKey(
      secretKey: shared,
      info: 'nearby-share:responder->initiator'.codeUnits,
      nonce: const [],
    );

    final channel = SecureChannel._(
      socket,
      isInitiator ? initiatorToResponder : responderToInitiator,
      isInitiator ? responderToInitiator : initiatorToResponder,
      splitter,
    );
    channel._rawSub = sub;
    return channel;
  }

  /// Decoded, decrypted packets, in arrival order.
  Stream<DecodedPacket> get packets => _splitter.frames.asyncMap(_decrypt);

  Future<DecodedPacket> _decrypt(Uint8List outer) async {
    final nonce = outer.sublist(0, 12);
    final tag = outer.sublist(outer.length - 16);
    final cipherText = outer.sublist(12, outer.length - 16);
    final clear = await _aead.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
      secretKey: _recvKey,
    );
    return decodeFrame(Uint8List.fromList(clear));
  }

  /// Encrypts and sends one already-encoded packet payload (i.e. the output
  /// of `wire_protocol.encodePacket(...)`).
  Future<void> send(Uint8List packetPayload) async {
    if (_closed) throw StateError('SecureChannel is closed');
    final nonce = _aead.newNonce();
    final box = await _aead.encrypt(packetPayload, secretKey: _sendKey, nonce: nonce);
    final outer = Uint8List(nonce.length + box.cipherText.length + box.mac.bytes.length);
    outer.setRange(0, nonce.length, nonce);
    outer.setRange(nonce.length, nonce.length + box.cipherText.length, box.cipherText);
    outer.setRange(nonce.length + box.cipherText.length, outer.length, box.mac.bytes);

    final framed = Uint8List(4 + outer.length);
    ByteData.view(framed.buffer).setUint32(0, outer.length, Endian.big);
    framed.setRange(4, framed.length, outer);
    _socket.add(framed);
    await _socket.flush();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _rawSub?.cancel();
    await _splitter.close();
    await _socket.close();
  }
}
