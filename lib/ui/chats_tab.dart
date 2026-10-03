import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/peer.dart';
import '../state/providers.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'widgets/delivery_status_icon.dart';

class ChatsTab extends ConsumerWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(peersProvider).value ?? const <Peer>[];
    return ref.watch(conversationsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load chats: $e')),
          data: (conversations) {
            if (conversations.isEmpty) {
              return const _EmptyState(
                icon: Icons.forum_outlined,
                text: 'No chats yet.\nOpen Nearby to message someone in range.',
              );
            }
            return ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = conversations[i];
                final name = nameFor(c.peerId, peers, c.peerName);
                final last = c.lastMessage;
                final online = peers.any((p) =>
                    p.nodeId == c.peerId &&
                    p.state == PeerLinkState.connected);
                return ListTile(
                  leading: Badge(
                    isLabelVisible: online,
                    smallSize: 10,
                    backgroundColor: Colors.green,
                    child: CircleAvatar(child: Text(_initial(name))),
                  ),
                  title: Text(name),
                  subtitle: Row(
                    children: [
                      if (last.outgoing) ...[
                        DeliveryStatusIcon(status: last.status),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          last.message.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  trailing: Text(formatTimestamp(last.message.timestamp)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        ChatScreen(peerId: c.peerId, initialName: name),
                  )),
                );
              },
            );
          },
        );
  }
}

String _initial(String name) =>
    name.isEmpty ? '?' : name.characters.first.toUpperCase();

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
