import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/nearby_share_engine.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/common.dart';

/// The Settings tab. Every toggle here is wired to something real:
///  - WiFi / Bluetooth: whether this device is actively *browsing* on the
///    mDNS / BLE layer (`AggregatedDiscoveryService.mdnsLayer`/`bleLayer`)
///  - Discoverable: whether this device *advertises itself* for others to
///    find (`NearbyShareEngine.setDiscoverable`) — a distinct axis from
///    browsing
///  - Notifications / Smart Transfer: persisted preferences
///    (`AppSettingsStore`) — Notifications doesn't yet drive a real local
///    notification (that's a separate OS-integration piece outside this
///    change's scope), which is noted rather than implied.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  Future<void> _toggleMdns(NearbyShareEngine engine) async {
    final layer = engine.discovery.mdnsLayer;
    if (layer.isActive) {
      await layer.stop();
    } else {
      await layer.start(localDeviceName: engine.settings.deviceName);
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleBle(NearbyShareEngine engine) async {
    final layer = engine.discovery.bleLayer;
    if (layer.isActive) {
      await layer.stop();
    } else {
      await layer.start(localDeviceName: engine.settings.deviceName);
    }
    if (mounted) setState(() {});
  }

  Future<void> _editDeviceName(NearbyShareEngine engine) async {
    final controller = TextEditingController(text: engine.settings.deviceName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await engine.setDeviceName(result.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<NearbyShareEngine>();

    final rows = <_SettingsRowData>[
      _SettingsRowData(
        label: 'WiFi',
        desc: 'Allow WiFi sharing and discovery',
        value: engine.discovery.mdnsLayer.isActive,
        onToggle: () => _toggleMdns(engine),
      ),
      _SettingsRowData(
        label: 'Bluetooth',
        desc: 'Allow Bluetooth pairing and transfers',
        value: engine.discovery.bleLayer.isActive,
        onToggle: () => _toggleBle(engine),
      ),
      _SettingsRowData(
        label: 'Discoverable',
        desc: 'Let nearby devices find you',
        value: engine.settings.discoverable,
        onToggle: () => engine.setDiscoverable(!engine.settings.discoverable),
      ),
      _SettingsRowData(
        label: 'Notifications',
        desc: 'Alerts for incoming transfers',
        value: engine.settings.notificationsEnabled,
        onToggle: () => engine.setNotificationsEnabled(!engine.settings.notificationsEnabled),
      ),
      _SettingsRowData(
        label: 'Smart Transfer',
        desc: 'Use Bluetooth to find devices, WiFi Direct to send faster',
        value: engine.settings.smartTransferEnabled,
        onToggle: () => engine.setSmartTransferEnabled(!engine.settings.smartTransferEnabled),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Settings', style: AppText.heading),
        const SizedBox(height: 22),
        RoundedCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: GestureDetector(
            onTap: () => _editDeviceName(engine),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Device Name', style: AppText.settingsRowTitle),
                Text(engine.settings.deviceName, style: AppText.greetingLabel),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('PERMISSIONS', style: AppText.sectionLabelSmall),
        const SizedBox(height: 10),
        for (final row in rows)
          RoundedCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.label, style: AppText.settingsRowTitle),
                    const SizedBox(height: 2),
                    Text(row.desc, style: AppText.settingsRowDesc),
                  ],
                ),
              ),
              ToggleSwitch(value: row.value, onChanged: row.onToggle),
            ]),
          ),
        const SizedBox(height: 12),
        Center(child: Text('Version 0.1.0', style: AppText.version)),
      ],
    );
  }
}

class _SettingsRowData {
  const _SettingsRowData({required this.label, required this.desc, required this.value, required this.onToggle});

  final String label;
  final String desc;
  final bool value;
  final VoidCallback onToggle;
}
