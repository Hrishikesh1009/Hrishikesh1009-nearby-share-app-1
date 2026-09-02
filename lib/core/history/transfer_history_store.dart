import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum HistoryDirection { sent, received }

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.name,
    required this.size,
    required this.peerName,
    required this.direction,
    required this.timestamp,
  });

  final String id;
  final String name;
  final String size; // pre-formatted, e.g. "128 MB"
  final String peerName;
  final HistoryDirection direction;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'peerName': peerName,
        'direction': direction.name,
        'timestamp': timestamp.toIso8601String(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        size: json['size'] as String,
        peerName: json['peerName'] as String,
        direction: HistoryDirection.values.byName(json['direction'] as String),
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

/// Persists completed transfers so the Home tab's "Recent Activity" and the
/// History screen show real data — the design's reference script only ever
/// holds these in memory (a hardcoded seed list plus whatever the demo
/// `setInterval` appends).
class TransferHistoryStore {
  TransferHistoryStore._(this._file);

  final File _file;
  List<HistoryEntry> _cache = [];

  List<HistoryEntry> get entries => List.unmodifiable(_cache);

  static Future<TransferHistoryStore> open() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/nearby_share/history.json');
    await file.parent.create(recursive: true);
    final store = TransferHistoryStore._(file);
    await store._load();
    return store;
  }

  Future<void> _load() async {
    if (!await _file.exists()) {
      _cache = [];
      return;
    }
    try {
      final raw = jsonDecode(await _file.readAsString()) as List<dynamic>;
      _cache = raw.map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      _cache = [];
    }
  }

  Future<void> add(HistoryEntry entry) async {
    _cache = [entry, ..._cache].take(200).toList();
    await _file.writeAsString(jsonEncode(_cache.map((e) => e.toJson()).toList()));
  }
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final decimals = unit > 0 && size < 10 ? 1 : 0;
  return '${size.toStringAsFixed(decimals)} ${units[unit]}';
}

/// Relative time label matching the design's "2 min ago" / "Yesterday"
/// style.
String formatRelativeTime(DateTime timestamp) {
  final diff = DateTime.now().difference(timestamp);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
}
