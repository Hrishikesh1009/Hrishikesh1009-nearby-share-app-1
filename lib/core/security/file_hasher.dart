import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Streaming SHA-256 helpers. Both directions matter for memory safety:
/// hashing a 5GB file must never materialize it in RAM, and neither must
/// writing/reading it during transfer (see `core/transport/`, which always
/// moves data in bounded 4MB chunks via `RandomAccessFile`).
class FileHasher {
  /// Hashes [file] end-to-end by streaming it through SHA-256, never
  /// holding more than one internal digest-sink buffer in memory
  /// regardless of file size.
  static Future<String> sha256Hex(File file) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.events.single.toString();
  }

  static bool matches(String expectedHex, String actualHex) =>
      expectedHex.toLowerCase() == actualHex.toLowerCase();
}
