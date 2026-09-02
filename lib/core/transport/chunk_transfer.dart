import 'dart:async';
import 'dart:io';

import '../models/transfer_models.dart';
import '../protocol/wire_protocol.dart';
import '../security/file_hasher.dart';
import '../security/secure_channel.dart';

/// Sequential 4MB binary chunks. This is the memory-safety boundary: a 5GB
/// file is read and written 4MB at a time via [RandomAccessFile], so peak
/// memory for the transfer is bounded by [kChunkSize] regardless of file
/// size, on both the sending and receiving side.
const int kChunkSize = 4 * 1024 * 1024;

/// Sender-side loop for one accepted transfer. Stop-and-wait per chunk: the
/// next chunk is only read off disk and sent once the previous one's ACK
/// (meaning "durably flushed to disk on the receiver") has arrived. This
/// keeps the resume story exact — an ACK'd offset is guaranteed safe — at
/// the cost of one network round-trip per 4MB chunk. On a typical LAN/Wi-Fi
/// Direct RTT (low single-digit ms) this is not the throughput bottleneck;
/// pipelining a small window of in-flight chunks is a natural follow-up if
/// profiling on real devices shows otherwise.
Future<void> runSender({
  required SecureChannel channel,
  required File sourceFile,
  required TransferManifest manifest,
  required int resumeOffset,
  required void Function(int bytesSent) onProgress,
}) async {
  final raf = await sourceFile.open(mode: FileMode.read);
  Completer<int>? pendingAck;
  final verifyCompleter = Completer<bool>();

  // One persistent listener for the whole session, set up before any send,
  // so a fast reply can never race past an ad-hoc listener attaching late.
  final sub = channel.packets.listen((packet) {
    switch (packet.type) {
      case PacketType.chunkAck:
        pendingAck?.complete(decodeChunkAckOffset(packet.body));
        pendingAck = null;
        break;
      case PacketType.verifyOk:
        if (!verifyCompleter.isCompleted) verifyCompleter.complete(true);
        break;
      case PacketType.verifyFail:
        if (!verifyCompleter.isCompleted) verifyCompleter.complete(false);
        break;
      default:
        break;
    }
  });

  try {
    var offset = resumeOffset;
    await raf.setPosition(resumeOffset);

    while (offset < manifest.fileSize) {
      final remaining = manifest.fileSize - offset;
      final readLength = remaining < kChunkSize ? remaining : kChunkSize;
      final bytes = await raf.read(readLength);

      final ackCompleter = Completer<int>();
      pendingAck = ackCompleter;
      await channel.send(encodeChunk(offset, bytes));

      final acked = await ackCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('no ACK for chunk at offset $offset'),
      );
      final expected = offset + bytes.length;
      if (acked != expected) {
        throw StateError('ACK offset mismatch: expected $expected, got $acked');
      }
      offset = expected;
      onProgress(offset);
    }

    await channel.send(encodeComplete());

    final verified = await verifyCompleter.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException('receiver did not confirm the file hash in time'),
    );
    if (!verified) {
      throw StateError('receiver reported a SHA-256 mismatch after reassembly');
    }
  } finally {
    await sub.cancel();
    await raf.close();
  }
}

/// Receiver-side loop. Incoming chunks are appended to [destinationFile] in
/// the exact order the sender emits them (guaranteed by the sender's
/// stop-and-wait ACK discipline), each one flushed to disk *before* the ACK
/// goes out — that flushed length is what makes the on-disk file length a
/// trustworthy resume offset if the connection drops immediately after.
Future<void> runReceiver({
  required SecureChannel channel,
  required File destinationFile,
  required TransferManifest manifest,
  required void Function(int bytesReceived) onProgress,
}) async {
  final raf = await destinationFile.open(mode: FileMode.append);
  final completeReceived = Completer<void>();

  final sub = channel.packets.listen((packet) async {
    switch (packet.type) {
      case PacketType.chunk:
        final chunk = decodeChunk(packet.body);
        await raf.writeFrom(chunk.bytes);
        await raf.flush();
        final newOffset = chunk.offset + chunk.bytes.length;
        onProgress(newOffset);
        await channel.send(encodeChunkAck(newOffset));
        break;
      case PacketType.complete:
        if (!completeReceived.isCompleted) completeReceived.complete();
        break;
      default:
        break;
    }
  });

  try {
    await completeReceived.future.timeout(const Duration(minutes: 30));
    await raf.close();

    final actualHash = await FileHasher.sha256Hex(destinationFile);
    final ok = FileHasher.matches(manifest.sha256Hex, actualHash);
    await channel.send(ok ? encodeVerifyOk() : encodeVerifyFail());
    if (!ok) {
      throw StateError(
          'hash mismatch after reassembly: expected ${manifest.sha256Hex}, got $actualHash');
    }
  } finally {
    await sub.cancel();
  }
}
