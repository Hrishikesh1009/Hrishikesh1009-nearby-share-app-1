import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/history/transfer_history_store.dart';
import '../../core/models/transfer_models.dart';
import '../../core/services/nearby_share_engine.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/icons.dart';

/// The one transfer-status overlay, covering three states the design
/// itself only drew two of:
///  - **incoming, undecided** — the design has no dedicated screen for
///    this (its reference script only ever *sends*); this reuses the same
///    popped-up card the design uses for send progress, with Accept/Decline
///    in place of a progress bar, rather than inventing an unrelated modal.
///  - **sending/receiving** — spinner + progress bar + speed, matching the
///    design's `transferSending` state.
///  - **done** — checkmark, matching `transferDone`.
class TransferModal extends StatelessWidget {
  const TransferModal({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<NearbyShareEngine>();

    return Positioned.fill(
      child: Stack(children: [
        Container(color: const Color.fromRGBO(20, 18, 15, 0.35)),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: AppDurations.popIn,
              curve: Curves.easeOut,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 22),
                decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(22)),
                child: engine.pendingRequest != null
                    ? _IncomingConfirm(engine: engine)
                    : _TransferProgress(engine: engine),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _IncomingConfirm extends StatelessWidget {
  const _IncomingConfirm({required this.engine});

  final NearbyShareEngine engine;

  @override
  Widget build(BuildContext context) {
    final request = engine.pendingRequest!;
    final manifest = request.manifest;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.blueAlpha(0.15), shape: BoxShape.circle),
          child: FileGlyph(color: AppColors.blue),
        ),
        const SizedBox(height: 16),
        const Text('Incoming file', style: AppText.transferTitle, textAlign: TextAlign.center),
        const SizedBox(height: 3),
        Text(manifest.fileName, style: AppText.transferSub, textAlign: TextAlign.center),
        const SizedBox(height: 3),
        Text(
          '${formatBytes(manifest.fileSize)} · from ${request.peerAddress.address}',
          style: AppText.transferFileProgress,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Row(children: [
          LightPillButton(label: 'Decline', onTap: engine.declineIncoming, expand: true),
          const SizedBox(width: 10),
          DarkPillButton(label: 'Accept', onTap: () => _accept(context), expand: true),
        ]),
      ],
    );
  }

  Future<void> _accept(BuildContext context) async {
    final request = engine.pendingRequest;
    if (request == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/${request.manifest.fileName}';
    unawaited(engine.acceptIncoming(savePath));
  }
}

class _TransferProgress extends StatelessWidget {
  const _TransferProgress({required this.engine});

  final NearbyShareEngine engine;

  @override
  Widget build(BuildContext context) {
    final batch = engine.outgoingBatch;
    final incoming = batch == null ? engine.incomingSession : null;

    final bool sending;
    final bool done;
    final bool ok;
    final String title;
    final String subtitle;
    final String? fileProgressLabel;
    final double fraction;
    final String speedLabel;

    if (batch != null) {
      sending = !batch.done;
      done = batch.done;
      ok = batch.error == null && !batch.cancelled;
      final session = batch.currentSession;
      title = !done
          ? 'Sending files…'
          : (ok ? 'Sent successfully' : (batch.cancelled ? 'Cancelled' : 'Failed to send'));
      subtitle = done
          ? (ok
              ? '${formatBytes(batch.totalBytes)} sent to ${batch.peer.name}'
              : (batch.error ?? 'Transfer cancelled'))
          : '${formatBytes(batch.overallBytesTransferred)} of ${formatBytes(batch.totalBytes)} sent';
      fileProgressLabel =
          sending && session != null ? 'File ${batch.currentIndex + 1} of ${batch.files.length} · ${session.manifest.fileName}' : null;
      fraction = batch.overallFraction;
      speedLabel = session == null
          ? ''
          : '${session.progress.megabytesPerSecond.toStringAsFixed(1)} MB/s${_etaSuffix(session.progress.eta)}';
    } else if (incoming != null) {
      final terminal = const {
        TransferStatus.completed,
        TransferStatus.failed,
        TransferStatus.cancelled,
        TransferStatus.declined,
      }.contains(incoming.status);
      sending = !terminal;
      done = terminal;
      ok = incoming.status == TransferStatus.completed;
      title = !terminal
          ? 'Receiving file…'
          : (ok ? 'Received successfully' : (incoming.status == TransferStatus.cancelled ? 'Cancelled' : 'Failed to receive'));
      subtitle = terminal
          ? (ok
              ? '${formatBytes(incoming.manifest.fileSize)} received from ${incoming.peer.name}'
              : (incoming.errorMessage ?? 'Transfer cancelled'))
          : '${formatBytes(incoming.progress.bytesTransferred)} of ${formatBytes(incoming.manifest.fileSize)} received';
      fileProgressLabel = !terminal ? incoming.manifest.fileName : null;
      fraction = incoming.progress.fraction;
      speedLabel = '${incoming.progress.megabytesPerSecond.toStringAsFixed(1)} MB/s${_etaSuffix(incoming.progress.eta)}';
    } else {
      // Nothing to show; TransferModal shouldn't be mounted in this case.
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (done && ok)
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.greenAlpha(0.15), shape: BoxShape.circle),
            child: CheckmarkGlyph(color: AppColors.green),
          )
        else if (sending)
          RotatingSpinner(),
        const SizedBox(height: 16),
        Text(title, style: AppText.transferTitle, textAlign: TextAlign.center),
        const SizedBox(height: 3),
        Text(subtitle, style: AppText.transferSub, textAlign: TextAlign.center),
        if (fileProgressLabel != null) ...[
          const SizedBox(height: 3),
          Text(fileProgressLabel, style: AppText.transferFileProgress, textAlign: TextAlign.center),
        ],
        if (sending) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              // `num.clamp` returns `num`, not `double` — `.toDouble()`
              // keeps this assignable to `LinearProgressIndicator.value`.
              value: fraction.clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              backgroundColor: AppColors.borderAlpha(0.08),
              valueColor: AlwaysStoppedAnimation(AppColors.blue),
            ),
          ),
          const SizedBox(height: 8),
          Text(speedLabel, style: AppText.transferSpeed),
        ],
        const SizedBox(height: 4),
        DarkPillButton(
          label: done ? 'Done' : 'Cancel',
          onTap: done ? engine.dismissTransfer : engine.cancelCurrentTransfer,
        ),
      ],
    );
  }

  String _etaSuffix(Duration? eta) {
    if (eta == null) return '';
    final m = eta.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = eta.inSeconds.remainder(60).toString().padLeft(2, '0');
    return ' · $m:$s left';
  }
}

/// The `spinSlow` conic-gradient ring, spinning continuously while a
/// transfer is in flight.
class RotatingSpinner extends StatefulWidget {
  const RotatingSpinner({super.key});

  @override
  State<RotatingSpinner> createState() => _RotatingSpinnerState();
}

class _RotatingSpinnerState extends State<RotatingSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.spinSlow)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: AppGradients.spinnerRing, shape: BoxShape.circle),
        child: Container(width: 40, height: 40, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
      ),
    );
  }
}
