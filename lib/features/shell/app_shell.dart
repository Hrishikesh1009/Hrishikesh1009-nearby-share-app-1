import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/peer_device.dart';
import '../../core/services/nearby_share_engine.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/icons.dart';
import '../bluetooth/bluetooth_tab.dart';
import '../history/history_overlay.dart';
import '../home/home_tab.dart';
import '../nearby/nearby_tab.dart';
import '../settings/settings_tab.dart';
import '../transfer/share_sheet.dart';
import '../transfer/transfer_modal.dart';
import '../wifi/wifi_tab.dart';

enum AppTab { home, nearby, wifi, bluetooth, settings }

/// The whole app in one screen: bottom-nav tab content plus three overlays
/// (History, the Share Sheet, the transfer modal) — exactly the design's
/// structure, where every screen and overlay lives inside one scrolling
/// content area under one persistent bottom nav.
///
/// Tab/History/Share-Sheet visibility is ordinary widget state (it's
/// UI-only navigation, not network state); [NearbyShareEngine] — read via
/// `Provider` — supplies everything that *is* network state: peers, the
/// pending incoming request, and the active outgoing batch.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _tab = AppTab.home;
  bool _historyOpen = false;
  PeerDevice? _sharePeer;
  List<File>? _shareFiles;

  void _setTab(AppTab tab) => setState(() {
        _tab = tab;
        _historyOpen = false;
      });

  void _openHistory() => setState(() => _historyOpen = true);
  void _closeHistory() => setState(() => _historyOpen = false);

  Future<void> _openShareSheetFor(PeerDevice peer) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    final paths = result?.files.where((f) => f.path != null).map((f) => f.path!) ?? const [];
    final files = paths.map(File.new).toList();
    if (files.isEmpty || !mounted) return;
    setState(() {
      _sharePeer = peer;
      _shareFiles = files;
    });
  }

  void _closeShareSheet() => setState(() {
        _sharePeer = null;
        _shareFiles = null;
      });

  Future<void> _confirmSend() async {
    final peer = _sharePeer;
    final files = _shareFiles;
    _closeShareSheet();
    if (peer == null || files == null) return;
    try {
      await context.read<NearbyShareEngine>().sendFiles(peer, files);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<NearbyShareEngine>();

    // `NearbyShareEngine.start()` (kicked off in main.dart) awaits
    // permissions + opens the transfer server + `SharedPreferences` before
    // its `late final` service fields (discovery/history/settings) are
    // safe to touch — every tab reads at least one of them. Gate the whole
    // shell on `isReady` rather than guard each tab individually.
    if (!engine.isReady) {
      return const Scaffold(
        backgroundColor: AppColors.screenBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final showTransferOverlay =
        engine.pendingRequest != null || engine.outgoingBatch != null || engine.incomingSession != null;

    return Scaffold(
      backgroundColor: AppColors.screenBg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
                    child: AnimatedSwitcher(
                      duration: AppDurations.fadeIn,
                      child: KeyedSubtree(
                        key: ValueKey(_tab),
                        child: SingleChildScrollView(child: _tabBody()),
                      ),
                    ),
                  ),
                ),
                _BottomNav(tab: _tab, onSelect: _setTab),
              ],
            ),
            if (_historyOpen) HistoryOverlay(onBack: _closeHistory),
            if (_sharePeer != null && _shareFiles != null && !showTransferOverlay)
              ShareSheet(
                peer: _sharePeer!,
                files: _shareFiles!,
                onCancel: _closeShareSheet,
                onSend: _confirmSend,
              ),
            if (showTransferOverlay) const TransferModal(),
          ],
        ),
      ),
    );
  }

  Widget _tabBody() {
    switch (_tab) {
      case AppTab.home:
        return HomeTab(onOpenHistory: _openHistory, onNavigate: _setTab);
      case AppTab.nearby:
        return NearbyTab(onShare: _openShareSheetFor);
      case AppTab.wifi:
        return const WifiTab();
      case AppTab.bluetooth:
        return const BluetoothTab();
      case AppTab.settings:
        return const SettingsTab();
    }
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.tab, required this.onSelect});

  final AppTab tab;
  final void Function(AppTab) onSelect;

  Color _colorFor(AppTab t) => tab == t ? AppColors.blue : AppColors.inactiveGray;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 18),
      decoration: BoxDecoration(
        color: AppColors.screenBg,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _item(AppTab.home, 'Home', RoundedSquareGlyph(size: 20, radius: 6, color: _colorFor(AppTab.home))),
          _item(AppTab.nearby, 'Nearby', RingDotGlyph(size: 20, color: _colorFor(AppTab.nearby))),
          _item(
            AppTab.wifi,
            'WiFi',
            AscendingBars(
              heights: const [7, 11, 16],
              colors: List.filled(3, _colorFor(AppTab.wifi)),
              barWidth: 4,
            ),
          ),
          _item(AppTab.bluetooth, 'Bluetooth', BluetoothGlyph(size: 15, color: _colorFor(AppTab.bluetooth))),
          _item(
            AppTab.settings,
            'Settings',
            RoundedSquareGlyph(size: 20, radius: 10, color: _colorFor(AppTab.settings)),
          ),
        ],
      ),
    );
  }

  Widget _item(AppTab t, String label, Widget icon) {
    return GestureDetector(
      onTap: () => onSelect(t),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 5),
            Text(label, style: AppText.navLabel.copyWith(color: _colorFor(t))),
          ],
        ),
      ),
    );
  }
}
