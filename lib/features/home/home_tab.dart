import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/history/transfer_history_store.dart';
import '../../core/services/nearby_share_engine.dart';
import '../../core/wifi/wifi_share_info.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/icons.dart';
import '../shell/app_shell.dart';

/// The Home tab: greeting, three quick actions, WiFi/Bluetooth status
/// cards, and Recent Activity.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.onOpenHistory, required this.onNavigate});

  final VoidCallback onOpenHistory;
  final void Function(AppTab) onNavigate;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<NearbyShareEngine>();
    final recent = engine.history.entries.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_greeting, style: AppText.greetingLabel),
        const SizedBox(height: 2),
        const Text('Share anything, instantly', style: AppText.heading),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(
            child: _QuickAction(
              label: 'Send Files',
              bg: AppColors.blueAlpha(0.12),
              icon: RoundedSquareGlyph(size: 14, radius: 4, color: AppColors.blue),
              onTap: () => onNavigate(AppTab.nearby),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              label: 'Share WiFi',
              bg: AppColors.violetAlpha(0.12),
              icon: AscendingBars(heights: const [6, 10, 14], colors: List.filled(3, AppColors.violet)),
              onTap: () => onNavigate(AppTab.wifi),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              label: 'Pair Device',
              bg: AppColors.blueAlpha(0.12),
              icon: BluetoothGlyph(size: 13, color: AppColors.blue),
              onTap: () => onNavigate(AppTab.bluetooth),
            ),
          ),
        ]),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: GestureDetector(onTap: () => onNavigate(AppTab.wifi), child: const _WifiStatusCard())),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => onNavigate(AppTab.bluetooth),
              child: _BluetoothStatusCard(engine: engine),
            ),
          ),
        ]),
        const SizedBox(height: 26),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent Activity', style: AppText.sectionTitle),
            GestureDetector(
              onTap: onOpenHistory,
              child: Text(
                'See all',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.blue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text('No transfers yet', style: AppText.itemSub),
          )
        else
          for (var i = 0; i < recent.length; i++) _HistoryRow(entry: recent[i], index: i),
      ],
    );
  }
}

class _WifiStatusCard extends StatefulWidget {
  const _WifiStatusCard();

  @override
  State<_WifiStatusCard> createState() => _WifiStatusCardState();
}

class _WifiStatusCardState extends State<_WifiStatusCard> {
  String _ssid = 'Loading…';

  @override
  void initState() {
    super.initState();
    WifiShareInfo.currentSsid().then((value) {
      if (mounted) setState(() => _ssid = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WIFI', style: AppText.cardLabelSmall),
          const SizedBox(height: 6),
          Text(_ssid, style: AppText.cardValue, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('Sharing on', style: AppText.cardSub),
        ],
      ),
    );
  }
}

class _BluetoothStatusCard extends StatelessWidget {
  const _BluetoothStatusCard({required this.engine});

  final NearbyShareEngine engine;

  @override
  Widget build(BuildContext context) {
    final paired = engine.settings.pairedDeviceNames;
    final bleNames = engine.discovery.bleLayer.currentDevices.map((d) => d.name).toSet();
    final connected = paired.where(bleNames.contains).length;

    return RoundedCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BLUETOOTH', style: AppText.cardLabelSmall),
          const SizedBox(height: 6),
          Text('$connected connected', style: AppText.cardValue),
          const SizedBox(height: 2),
          Text('${paired.length} paired', style: AppText.cardSub),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.label, required this.bg, required this.icon, required this.onTap});

  final String label;
  final Color bg;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: RoundedCard(
        radius: 18,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: icon,
            ),
            const SizedBox(height: 8),
            Text(label, style: AppText.quickActionLabel, textAlign: TextAlign.center),
          ],
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderAlpha(0.06)))),
      child: Row(children: [
        AvatarBubble(name: entry.peerName, index: index, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name, style: AppText.itemTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${entry.peerName} · ${formatRelativeTime(entry.timestamp)}', style: AppText.itemSub),
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
