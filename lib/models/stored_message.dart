import 'mesh_message.dart';

/// Outgoing delivery progress. Order matters: status only ever moves forward.
enum DeliveryStatus {
  /// No peer in range yet; will go out when one appears.
  pending,

  /// Handed to at least one neighbour.
  sent,

  /// A neighbour was heard forwarding it.
  relayed,

  /// The recipient sent back a receipt.
  delivered,
}

/// A message as kept on this device, with local-only bookkeeping.
class StoredMessage {
  const StoredMessage({
    required this.message,
    required this.outgoing,
    this.status = DeliveryStatus.pending,
    this.relayHops = 0,
  });

  final MeshMessage message;
  final bool outgoing;

  /// Only meaningful for outgoing messages.
  final DeliveryStatus status;

  /// How many devices the message passed through between sender and
  /// recipient ("via N devices").
  final int relayHops;

  String get id => message.id;

  /// The other party in the conversation.
  String get peerId => outgoing ? message.receiverId : message.senderId;

  StoredMessage copyWith({DeliveryStatus? status, int? relayHops}) =>
      StoredMessage(
        message: message,
        outgoing: outgoing,
        status: status ?? this.status,
        relayHops: relayHops ?? this.relayHops,
      );
}

class ConversationSummary {
  const ConversationSummary({
    required this.peerId,
    required this.peerName,
    required this.lastMessage,
  });

  final String peerId;
  final String peerName;
  final StoredMessage lastMessage;
}
