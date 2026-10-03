import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/peer.dart';
import '../state/providers.dart';
import 'chat_screen.dart';
import 'widgets/signal_bars.dart';

class NearbyTab extends ConsumerWidget {
  const NearbyTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(peersProvider).value ?? const <Peer>[];
    if (peers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 16),
              Text(
                'Looking for nearby LinkMesh devices…\n'
                'Keep the app open on both phones, within ~30 m.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: peers.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _PeerTile(peer: peers[i]),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (peer.state) {
      PeerLinkState.connected => peer.quality == SignalQuality.weak
          ? ('Weak signal', scheme.error)
          : ('Connected', Colors.green),
      PeerLinkState.connecting => ('Connecting…', scheme.outline),
      PeerLinkState.discovered => ('In range', scheme.outline),
      PeerLinkState.disconnected => ('Disconnected', scheme.outline),
    };
    final nodeId = peer.nodeId;
    return ListTile(
      leading: CircleAvatar(child: Icon(Icons.smartphone, color: color)),
      title: Text(peer.displayName),
      subtitle: Text('$label · ${peer.rssi} dBm'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SignalBars(
            bars: peer.bars,
            active: peer.state == PeerLinkState.connected,
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.chat_bubble_outline,
            color: nodeId == null ? scheme.outlineVariant : scheme.primary,
          ),
        ],
      ),
      // A peer is chattable once we've read its node id.
      enabled: nodeId != null,
      onTap: nodeId == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ChatScreen(peerId: nodeId, initialName: peer.name),
              )),
    );
  }
}
