import 'package:flutter/material.dart';

import '../../models/stored_message.dart';
import '../format.dart';
import 'delivery_status_icon.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final StoredMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outgoing = message.outgoing;
    final background =
        outgoing ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final foreground =
        outgoing ? scheme.onPrimaryContainer : scheme.onSurface;
    final meta = foreground.withValues(alpha: 0.7);
    final metaStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: meta,
        );

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(outgoing ? 16 : 4),
              bottomRight: Radius.circular(outgoing ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                message.message.content,
                style: TextStyle(color: foreground, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.relayHops > 0) ...[
                    Text(relayLabel(message.relayHops), style: metaStyle),
                    Text('  ·  ', style: metaStyle),
                  ],
                  Text(
                    formatTimestamp(message.message.timestamp),
                    style: metaStyle,
                  ),
                  if (outgoing) ...[
                    const SizedBox(width: 4),
                    DeliveryStatusIcon(status: message.status, color: meta),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
