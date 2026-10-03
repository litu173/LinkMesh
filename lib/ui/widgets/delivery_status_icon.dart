import 'package:flutter/material.dart';

import '../../models/stored_message.dart';

/// ✓ sent, ⇄ relayed, ✓✓ delivered, clock while waiting for a peer.
class DeliveryStatusIcon extends StatelessWidget {
  const DeliveryStatusIcon({super.key, required this.status, this.color});

  final DeliveryStatus status;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (status) {
      DeliveryStatus.pending => (Icons.schedule, 'Waiting for a nearby device'),
      DeliveryStatus.sent => (Icons.check, 'Sent'),
      DeliveryStatus.relayed => (Icons.swap_horiz, 'Relayed'),
      DeliveryStatus.delivered => (Icons.done_all, 'Delivered'),
    };
    return Tooltip(
      message: label,
      child: Icon(icon, size: 14, color: color, semanticLabel: label),
    );
  }
}
