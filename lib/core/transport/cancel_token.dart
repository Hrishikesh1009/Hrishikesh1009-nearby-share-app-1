import 'dart:async';

/// A simple cooperative cancellation signal for an in-flight transfer —
/// backs the design's transfer-modal Cancel button with a real abort
/// instead of a decorative button.
class CancelToken {
  bool _cancelled = false;
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _completer.complete();
  }
}

class TransferCancelledException implements Exception {
  const TransferCancelledException();
  @override
  String toString() => 'Transfer cancelled';
}
