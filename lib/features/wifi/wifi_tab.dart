import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/nearby_share_engine.dart';
import '../../core/wifi/wifi_share_info.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/icons.dart';

/// The WiFi tab — "Share Your WiFi". Real SSID, a real scannable join QR,
/// and a password *you* set for guests (see `core/wifi/wifi_share_info.dart`
/// for why this can't be the router's actual PSK). The Personal Hotspot
/// toggle can't be flipped programmatically by a sandboxed app on either
/// platform, so it's honest about that rather than pretending to control
/// it — see `_HotspotCard` below.
class WifiTab extends StatefulWidget {
  const WifiTab({super.key});

  @override
  State<WifiTab> createState() => _WifiTabState();
}

class _WifiTabState extends State<WifiTab> {
  String _ssid = 'Loading…';
  bool _passwordVisible = false;

  @override
  void initState() {
    super.initState();
    WifiShareInfo.currentSsid().then((value) {
      if (mounted) setState(() => _ssid = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<NearbyShareEngine>();
    final password = engine.settings.wifiSharePassword;
    final payload = WifiShareInfo.qrPayload(ssid: _ssid, password: password);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Share Your WiFi', style: AppText.heading),
        const SizedBox(height: 4),
        Text("Let guests join without typing a password", style: AppText.greetingLabel),
        const SizedBox(height: 22),
        RoundedCard(
          radius: 20,
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            QrImageView(data: payload, size: 140, backgroundColor: Colors.white, padding: EdgeInsets.zero),
            const SizedBox(height: 14),
            Text(_ssid, style: AppText.cardValue, textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text('Scan to join this network', style: AppText.cardSub),
          ]),
        ),
        const SizedBox(height: 16),
        RoundedCard(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PASSWORD', style: AppText.cardLabelSmall),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _editPassword(engine),
                    child: Text(
                      _passwordVisible ? password : '•' * password.length,
                      style: AppText.passwordText,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _passwordVisible = !_passwordVisible),
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(color: AppColors.borderAlpha(0.06), borderRadius: BorderRadius.circular(10)),
                child: const EyeGlyph(),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        const _HotspotCard(),
      ],
    );
  }

  Future<void> _editPassword(NearbyShareEngine engine) async {
    final controller = TextEditingController(text: engine.settings.wifiSharePassword);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guest password'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await engine.setWifiSharePassword(result.trim());
    }
  }
}

class _HotspotCard extends StatefulWidget {
  const _HotspotCard();

  @override
  State<_HotspotCard> createState() => _HotspotCardState();
}

class _HotspotCardState extends State<_HotspotCard> {
  // Intent-only: neither Android nor iOS lets a third-party app enable
  // Personal Hotspot programmatically, so this reflects what the user
  // *wants*, not a real radio state, and always explains that on tap.
  bool _wantsHotspotOn = false;

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      radius: 16,
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Personal Hotspot', style: AppText.settingsRowTitle),
              const SizedBox(height: 2),
              Text('Let nearby devices connect directly', style: AppText.settingsRowDesc),
            ],
          ),
        ),
        ToggleSwitch(
          value: _wantsHotspotOn,
          onChanged: () {
            setState(() => _wantsHotspotOn = !_wantsHotspotOn);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Apps can't turn on Personal Hotspot directly — enable it in your phone's Settings app."),
            ));
          },
        ),
      ]),
    );
  }
}
