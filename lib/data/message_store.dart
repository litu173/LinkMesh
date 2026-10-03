import 'dart:async';

import '../models/mesh_message.dart';
import '../models/stored_message.dart';

/// Persistence for chat and SOS messages. The router depends on this
/// interface so it can be tested without a database.
abstract class MessageStore {
  /// Fires after any write.
  Stream<void> get changes;

  Future<StoredMessage?> get(String id);

  /// Inserts or replaces by message id.
  Future<void> save(StoredMessage message);

  Future<List<StoredMessage>> conversation(String peerId);
  Future<List<ConversationSummary>> conversations();

  /// Latest SOS per sender, newest first.
  Future<List<StoredMessage>> sosAlerts();

  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String value);
}

/// In-memory store for tests and previews.
class InMemoryMessageStore implements MessageStore {
  final _messages = <String, StoredMessage>{};
  final _settings = <String, String>{};
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<StoredMessage?> get(String id) async => _messages[id];

  @override
  Future<void> save(StoredMessage message) async {
    _messages[message.id] = message;
    _changes.add(null);
  }

  Iterable<StoredMessage> get _chats =>
      _messages.values.where((m) => m.message.type == MessageType.text);

  @override
  Future<List<StoredMessage>> conversation(String peerId) async =>
      _chats.where((m) => m.peerId == peerId).toList()
        ..sort((a, b) => a.message.timestamp.compareTo(b.message.timestamp));

  @override
  Future<List<ConversationSummary>> conversations() async {
    final latest = <String, StoredMessage>{};
    final names = <String, String>{};
    for (final m in _chats) {
      final current = latest[m.peerId];
      if (current == null || m.message.timestamp > current.message.timestamp) {
        latest[m.peerId] = m;
      }
      if (!m.outgoing) names[m.peerId] = m.message.senderName;
    }
    return latest.entries
        .map((e) => ConversationSummary(
              peerId: e.key,
              peerName: names[e.key] ?? '',
              lastMessage: e.value,
            ))
        .toList()
      ..sort((a, b) => b.lastMessage.message.timestamp
          .compareTo(a.lastMessage.message.timestamp));
  }

  @override
  Future<List<StoredMessage>> sosAlerts() async {
    final latest = <String, StoredMessage>{};
    for (final m in _messages.values) {
      if (m.message.type != MessageType.sos || m.outgoing) continue;
      final current = latest[m.message.senderId];
      if (current == null || m.message.timestamp > current.message.timestamp) {
        latest[m.message.senderId] = m;
      }
    }
    return latest.values.toList()
      ..sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
  }

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> setSetting(String key, String value) async =>
      _settings[key] = value;
}
