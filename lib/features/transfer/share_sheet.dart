import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/history/transfer_history_store.dart';
import '../../core/models/peer_device.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/icons.dart';

/// The Share Sheet: confirms the real file(s) picked from the OS file
/// picker before they're sent — the design's version renders a fixed demo
/// batch, this one renders whatever [files] the user actually chose.
class ShareSheet extends StatelessWidget {
  const ShareSheet({super.key, required this.peer, required this.files, required this.onCancel, required this.onSend});

  final PeerDevice peer;
  final List<File> files;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(children: [
        GestureDetector(
          onTap: onCancel,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 200),
            builder: (context, t, _) => Container(color: Color.fromRGBO(20, 18, 15, 0.35 * t)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: TweenAnimationBuilder<Offset>(
            tween: Tween(begin: const Offset(0, 1), end: Offset.zero),
            duration: AppDurations.sheetUp,
            curve: Curves.easeOut,
            builder: (context, offset, child) => FractionalTranslation(translation: offset, child: child),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                color: AppColors.screenBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: FutureBuilder<List<int>>(
                  future: Future.wait(files.map((f) => f.length())),
                  builder: (context, snapshot) {
                    final sizes = snapshot.data;
                    final totalLabel = sizes == null
                        ? '…'
                        : formatBytes(sizes.fold<int>(0, (a, b) => a + b));

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 18),
                            decoration: BoxDecoration(
                              color: AppColors.borderAlpha(0.15),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        Text('Send to ${peer.name}', style: AppText.sheetTitle),
                        const SizedBox(height: 2),
                        Text('${files.length} files · $totalLabel', style: AppText.sheetSub),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 230),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: files.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) => RoundedCard(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.blueAlpha(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: FileGlyph(color: AppColors.blue),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        files[i].uri.pathSegments.isNotEmpty
                                            ? files[i].uri.pathSegments.last
                                            : files[i].path,
                                        style: AppText.itemTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        sizes == null ? '…' : formatBytes(sizes[i]),
                                        style: AppText.itemSub,
                                      ),
                                    ],
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(children: [
                          LightPillButton(label: 'Cancel', onTap: onCancel, expand: true),
                          const SizedBox(width: 10),
                          DarkPillButton(label: 'Send', onTap: sizes == null ? null : onSend, expand: true),
                        ]),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
