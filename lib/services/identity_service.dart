import 'dart:async';

import 'package:uuid/uuid.dart';

import '../data/message_store.dart';
import '../models/node_identity.dart';

/// Owns this device's persistent mesh id and display name.
class IdentityService {
  IdentityService._(this._store, this._current);

  static const _idKey = 'node_id';
  static const _nameKey = 'node_name';

  final MessageStore _store;
  NodeIdentity _current;
  final _changes = StreamController<NodeIdentity>.broadcast();

  NodeIdentity get current => _current;
  Stream<NodeIdentity> get changes => _changes.stream;

  static Future<IdentityService> load(MessageStore store) async {
    var id = await store.getSetting(_idKey);
    if (id == null) {
      id = const Uuid().v4();
      await store.setSetting(_idKey, id);
    }
    final name =
        await store.getSetting(_nameKey) ?? 'Node-${id.substring(0, 4)}';
    return IdentityService._(store, NodeIdentity(id: id, name: name));
  }

  Future<void> rename(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _store.setSetting(_nameKey, trimmed);
    _current = NodeIdentity(id: _current.id, name: trimmed);
    _changes.add(_current);
  }
}
