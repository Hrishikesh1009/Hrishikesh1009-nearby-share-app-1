import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// The raw, non-HTTP wire protocol used over the encrypted TCP socket.
///
/// Every message on the wire is a length-prefixed frame:
///
///   [4 bytes big-endian uint32 frameLength][frameLength bytes payload]
///
/// `payload[0]` is a [PacketType] byte; the rest is type-specific. This
/// file only deals with *plaintext* framing/packet encoding — the actual
/// bytes on the socket are additionally AES-GCM sealed by
/// `core/security/secure_channel.dart`, which frames its own ciphertext the
/// same way. Keeping framing identical at both layers means
/// [FrameSplitter] is reused for both the outer (ciphertext) and, after
/// decryption, effectively the same structure for the inner packet.

enum PacketType {
  hello(0x01),
  manifest(0x02),
  accept(0x03),
  decline(0x04),
  chunk(0x05),
  chunkAck(0x06),
  complete(0x07),
  verifyOk(0x08),
  verifyFail(0x09),
  error(0x0A);

  const PacketType(this.code);
  final int code;

  static PacketType fromCode(int code) =>
      PacketType.values.firstWhere((t) => t.code == code, orElse: () => PacketType.error);
}

/// Splits a raw byte stream (e.g. `Socket`) into complete, length-delimited
/// frames, buffering across reads until a full frame is available. Handles
/// the common cases cleanly: several small frames arriving in one read, and
/// one large frame (a 4MB chunk) spanning many reads.
class FrameSplitter {
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int _bufferedLength = 0;
  // Broadcast: a channel's packets are watched by more than one persistent
  // listener at once (e.g. the chunk-ACK handler and the verify-result
  // handler both listen for the lifetime of a transfer), so this cannot be
  // a single-subscription controller.
  final StreamController<Uint8List> _framesController = StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get frames => _framesController.stream;

  void addChunk(Uint8List chunk) {
    if (chunk.isEmpty) return;
    _builder.add(chunk);
    _bufferedLength += chunk.length;
    _drain();
  }

  void _drain() {
    while (true) {
      if (_bufferedLength < 4) return;
      final all = _builder.toBytes(); // materializes + clears the builder
      final frameLen = ByteData.sublistView(all, 0, 4).getUint32(0, Endian.big);
      final totalNeeded = 4 + frameLen;
      if (all.length < totalNeeded) {
        _builder.add(all); // not enough yet, put it all back
        return;
      }
      final payload = Uint8List.sublistView(all, 4, totalNeeded);
      if (!_framesController.isClosed) {
        _framesController.add(payload);
      }
      _bufferedLength = all.length - totalNeeded;
      if (_bufferedLength > 0) {
        _builder.add(Uint8List.sublistView(all, totalNeeded));
      }
      // loop: there may be another full frame already buffered
    }
  }

  Future<void> close() => _framesController.close();
}

/// Builds a bare packet payload: `type` byte + body, no length prefix. This
/// is what [SecureChannel] encrypts wholesale for every packet after the
/// handshake — the *outer* length-prefixed framing around the ciphertext is
/// [SecureChannel]'s own concern, so packets never carry two length
/// prefixes.
Uint8List encodePacket(PacketType type, List<int> body) {
  final payload = Uint8List(1 + body.length)..[0] = type.code;
  payload.setRange(1, 1 + body.length, body);
  return payload;
}

/// Wraps a payload (`type` byte + body) in the `[len][payload]` framing.
/// Used only for the single plaintext frame exchanged before a
/// [SecureChannel] exists: the HELLO (X25519 public key) handshake.
Uint8List encodeFrame(PacketType type, List<int> body) {
  final payload = encodePacket(type, body);
  final frame = Uint8List(4 + payload.length);
  ByteData.view(frame.buffer).setUint32(0, payload.length, Endian.big);
  frame.setRange(4, frame.length, payload);
  return frame;
}

class DecodedPacket {
  const DecodedPacket(this.type, this.body);
  final PacketType type;
  final Uint8List body;
}

DecodedPacket decodeFrame(Uint8List payload) {
  return DecodedPacket(PacketType.fromCode(payload[0]), Uint8List.sublistView(payload, 1));
}

// ---- Packet body helpers -------------------------------------------------

/// The one packet that travels in plaintext, outer-framed directly (no
/// [SecureChannel] yet — this frame is what establishes it).
Uint8List encodeHello(Uint8List publicKeyBytes) => encodeFrame(PacketType.hello, publicKeyBytes);

Uint8List encodeManifest(Map<String, dynamic> manifestJson) =>
    encodePacket(PacketType.manifest, utf8.encode(jsonEncode(manifestJson)));

/// `resumeOffset`: 0 for a fresh transfer, or the byte offset the receiver
/// already has on disk for this `transferId` — the sender seeks straight
/// there instead of restarting the stream.
Uint8List encodeAccept(int resumeOffset) {
  final body = ByteData(8)..setUint64(0, resumeOffset, Endian.big);
  return encodePacket(PacketType.accept, body.buffer.asUint8List());
}

Uint8List encodeDecline() => encodePacket(PacketType.decline, const []);

/// `offset` is the byte position of `bytes[0]` within the whole file.
Uint8List encodeChunk(int offset, Uint8List bytes) {
  final header = ByteData(12)
    ..setUint64(0, offset, Endian.big)
    ..setUint32(8, bytes.length, Endian.big);
  final body = Uint8List(12 + bytes.length)
    ..setRange(0, 12, header.buffer.asUint8List())
    ..setRange(12, 12 + bytes.length, bytes);
  return encodePacket(PacketType.chunk, body);
}

/// Acknowledges that everything up to (not including) `ackedOffset` has
/// been durably written to disk.
Uint8List encodeChunkAck(int ackedOffset) {
  final body = ByteData(8)..setUint64(0, ackedOffset, Endian.big);
  return encodePacket(PacketType.chunkAck, body.buffer.asUint8List());
}

Uint8List encodeComplete() => encodePacket(PacketType.complete, const []);
Uint8List encodeVerifyOk() => encodePacket(PacketType.verifyOk, const []);
Uint8List encodeVerifyFail() => encodePacket(PacketType.verifyFail, const []);
Uint8List encodeError(String message) => encodePacket(PacketType.error, utf8.encode(message));

int decodeAcceptResumeOffset(Uint8List body) => ByteData.sublistView(body).getUint64(0, Endian.big);
int decodeChunkAckOffset(Uint8List body) => ByteData.sublistView(body).getUint64(0, Endian.big);

class ChunkPacket {
  const ChunkPacket(this.offset, this.bytes);
  final int offset;
  final Uint8List bytes;
}

ChunkPacket decodeChunk(Uint8List body) {
  final view = ByteData.sublistView(body);
  final offset = view.getUint64(0, Endian.big);
  final length = view.getUint32(8, Endian.big);
  return ChunkPacket(offset, Uint8List.sublistView(body, 12, 12 + length));
}

Map<String, dynamic> decodeManifest(Uint8List body) =>
    jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
