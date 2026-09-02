import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/history/transfer_history_store.dart';
import '../../core/services/nearby_share_engine.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/icons.dart';

/// The full Transfer History screen, shown as a full-bleed overlay above
/// the current tab (matching the design's `position:absolute;inset:0`
/// treatment) rather than a pushed route — there is only ever one "page"
/// of app in this design, and History is a layer on top of it.
class HistoryOverlay extends StatelessWidget {
  const HistoryOverlay({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<NearbyShareEngine>();
    final entries = engine.history.entries;

    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppDurations.fadeIn,
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: Container(
          color: AppColors.screenBg,
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                GestureDetector(
                  onTap: onBack,
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.borderAlpha(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const BackChevronGlyph(),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Transfer History', style: AppText.historyTitle),
              ]),
              const SizedBox(height: 20),
              Expanded(
                child: entries.isEmpty
                    ? Center(child: Text('No transfers yet', style: AppText.itemSub))
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, i) => _HistoryRow(entry: entries[i], index: i),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.index});

  final HistoryEntry entry;
  final int index;

  @override
  Widget build(BuildContext context) {
    final sent = entry.direction == HistoryDirection.sent;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderAlpha(0.06)))),
      child: Row(children: [
        AvatarBubble(name: entry.peerName, index: index, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name, style: AppText.itemTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                '${entry.peerName} · ${formatRelativeTime(entry.timestamp)} · ${entry.size}',
                style: AppText.itemSub,
              ),
            ],
          ),
        ),
        Text(
          sent ? 'Sent' : 'Received',
          style: AppText.itemDirection.copyWith(color: sent ? AppColors.blue : AppColors.violet),
        ),
      ]),
    );
  }
}
