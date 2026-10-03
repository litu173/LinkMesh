import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/mesh_bridge.dart';
import '../state/providers.dart';

/// Name, background relay and battery settings.
class SettingsSheet extends ConsumerStatefulWidget {
  const SettingsSheet({super.key});

  @override
  ConsumerState<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<SettingsSheet>
    with WidgetsBindingObserver {
  late final _name = TextEditingController(
    text: ref.read(identityServiceProvider).current.name,
  );
  bool? _background;
  bool? _batteryExempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    super.dispose();
  }

  // Re-check after returning from the system battery dialog.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final controller = ref.read(meshControllerProvider);
    final bridge = ref.read(bridgeProvider);
    final background = await controller.isBackgroundEnabled();
    final exempt = await bridge.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _background = background;
        _batteryExempt = exempt;
      });
    }
  }

  Future<void> _setBackground(bool value) async {
    setState(() => _background = value);
    await ref.read(meshControllerProvider).setBackgroundEnabled(value);
  }

  Future<void> _saveName() =>
      ref.read(identityServiceProvider).rename(_name.text);

  @override
  Widget build(BuildContext context) {
    final bridge = ref.read(bridgeProvider);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Settings', style: text.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            maxLength: 24,
            decoration: const InputDecoration(
              labelText: 'Your name on the mesh',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saveName(),
            onTapOutside: (_) => _saveName(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Receive & relay when closed'),
            subtitle: const Text(
              'Keeps LinkMesh running in the background while Bluetooth is '
              'on, with a small ongoing notification. Restarts after reboot.',
            ),
            value: _background ?? false,
            onChanged: _background == null ? null : _setBackground,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _batteryExempt ?? true
                  ? Icons.battery_full
                  : Icons.battery_alert,
            ),
            title: const Text('Battery optimisation'),
            subtitle: Text(
              _batteryExempt ?? true
                  ? 'Unrestricted: Android won\'t stop background relay.'
                  : 'Restricted: some phones stop background apps. '
                      'Tap to allow LinkMesh to run.',
            ),
            onTap: _batteryExempt == false
                ? bridge.requestBatteryExemption
                : null,
          ),
          const Divider(),
          Text('Sounds', style: text.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => bridge.playSound(AlertSound.message),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Message'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => bridge.playSound(AlertSound.sos),
                  icon: const Icon(Icons.sos),
                  label: const Text('SOS'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'SOS alerts use the alarm volume, so they sound even on silent.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
