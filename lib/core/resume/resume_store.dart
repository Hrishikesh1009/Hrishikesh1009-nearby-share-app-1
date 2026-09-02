import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists the resume state for in-flight transfers to disk, so a dropped
/// connection — or the app being killed — doesn't lose the byte offset.
/// One small JSON file per transfer id; the file bytes themselves stay on
/// disk in their own destination file the whole time (see
/// `core/transport/`), never buffered here.
class ResumeStore {
  ResumeStore._(this._dir);

  final Directory _dir;

  static Future<ResumeStore> open() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/nearby_share/resume');
    await dir.create(recursive: true);
    return ResumeStore._(dir);
  }

  File _fileFor(String transferId) => File('${_dir.path}/$transferId.json');

  Future<void> saveOffset({
    required String transferId,
    required int byteOffset,
    required String destinationPath,
    required String expectedSha256,
    required int totalSize,
  }) async {
    final file = _fileFor(transferId);
    await file.writeAsString(jsonEncode({
      'transferId': transferId,
      'byteOffset': byteOffset,
      'destinationPath': destinationPath,
      'expectedSha256': expectedSha256,
      'totalSize': totalSize,
      'updatedAt': DateTime.now().toIso8601String(),
    }));
  }

  /// Returns the last acknowledged byte offset for [transferId], or 0 if
  /// there is no resumable state (fresh transfer).
  Future<int> readOffset(String transferId) async {
    final entry = await readEntry(transferId);
    return entry?['byteOffset'] as int? ?? 0;
  }

  Future<Map<String, dynamic>?> readEntry(String transferId) async {
    final file = _fileFor(transferId);
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String transferId) async {
    final file = _fileFor(transferId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
