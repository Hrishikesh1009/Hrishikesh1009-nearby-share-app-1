import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/peer_device.dart';
import '../../core/services/nearby_share_engine.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/common.dart';

/// The Bluetooth tab. "My Devices" / "Available Devices" here map onto
/// what a sandboxed app can actually see and do over BLE — raw
/// advertisements (`core/discovery/ble_discovery_service.dart`) and an
/// app-local "devices I care about" list — not real OS-level Bluetooth
/// pairing/bonding or another device's battery telemetry, neither of which
/// a normal app can read. "Pair" adds a device to that local list;
/// toggling a "My Devices" row off forgets it (removes it from the list)
/// rather than pretending to sever a system BT connection this app was
/// never actually holding.
class BluetoothTab extends StatefulWidget {
  const BluetoothTab({super.key});

  @override
  State<BluetoothTab> createState() => _BluetoothTabState();
}

class _BluetoothTabState extends State<BluetoothTab> {
  Future<void> _toggleBluetooth(NearbyShareEngine engine) async {
    final layer = engine.discovery.bleLayer;
    if (layer.isActive) {
      await layer.stop();
    } else {
      await layer.start(localDeviceName: engine.settings.deviceName);
    }
    if (mounted) setState(() {});
  }

  Future<void> _pair(NearbyShareEngine engine, String name) async {
    final names = {...engine.settings.pairedDeviceNames, name}.toList();
    await engine.settings.setPairedDeviceNames(names);
    if (mounted) setState(() {});
  }

  Future<void> _forget(NearbyShareEngine engine, String name) async {
    final names = engine.settings.pairedDeviceNames.where((n) => n != name).toList();
    await engine.settings.setPairedDeviceNames(names);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<NearbyShareEngine>();
    final bleLayer = engine.discovery.bleLayer;
    final btEnabled = bleLayer.isActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Bluetooth', style: AppText.heading),
        const SizedBox(height: 4),
        Text('Manage paired and nearby devices', style: AppText.greetingLabel),
        const SizedBox(height: 22),
        RoundedCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            const Expanded(child: Text('Bluetooth', style: AppText.settingsRowTitle)),
            ToggleSwitch(value: btEnabled, onChanged: () => _toggleBluetooth(engine)),
          ]),
        ),
        const SizedBox(height: 24),
        if (btEnabled)
          StreamBuilder<PeerEvent>(
            stream: bleLayer.events,
            builder: (context, snapshot) {
              final paired = engine.settings.pairedDeviceNames;
              final live = bleLayer.currentDevices;
              final liveNames = live.map((d) => d.name).toSet();
              final available = live.where((d) => !paired.contains(d.name)).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MY DEVICES', style: AppText.sectionLabelSmall),
                  const SizedBox(height: 10),
                  if (paired.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text('No paired devices yet', style: AppText.itemSub),
                    )
                  else
                    for (var i = 0; i < paired.length; i++)
                      _MyDeviceRow(
                        name: paired[i],
                        index: i,
                        inRange: liveNames.contains(paired[i]),
                        onForget: () => _forget(engine, paired[i]),
                      ),
                  const SizedBox(height: 14),
                  Text('AVAILABLE DEVICES', style: AppText.sectionLabelSmall),
                  const SizedBox(height: 10),
                  if (available.isEmpty)
                    Text('No unpaired devices in range', style: AppText.itemSub)
                  else
                    for (var i = 0; i < available.length; i++)
                      _AvailableDeviceRow(
                        peer: available[i],
                        index: i,
                        onPair: () => _pair(engine, available[i].name),
                      ),
                ],
              );
            },
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text('Turn on Bluetooth to see devices', style: AppText.itemSub),
            ),
          ),
      ],
    );
  }
}

class _MyDeviceRow extends StatelessWidget {
  const _MyDeviceRow({required this.name, required this.index, required this.inRange, required this.onForget});

  final String name;
  final int index;
  final bool inRange;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        AvatarBubble(name: name, index: index),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: AppText.itemTitle),
              Text(inRange ? 'In range' : 'Not in range', style: AppText.itemSub),
            ],
          ),
        ),
        ToggleSwitch(value: true, onChanged: onForget),
      ]),
    );
  }
}

class _AvailableDeviceRow extends StatelessWidget {
  const _AvailableDeviceRow({required this.peer, required this.index, required this.onPair});

  final PeerDevice peer;
  final int index;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        AvatarBubble(name: peer.name, index: index + 1),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(peer.name, style: AppText.itemTitle),
              Text('Not paired', style: AppText.itemSub),
            ],
          ),
        ),
        GestureDetector(
          onTap: onPair,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration:
                BoxDecoration(color: AppColors.violetAlpha(0.12), borderRadius: BorderRadius.circular(10)),
            child: Text('Pair', style: AppText.shareButtonLabel.copyWith(color: AppColors.violet)),
          ),
        ),
      ]),
    );
  }
}
