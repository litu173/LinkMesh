import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/mesh_message.dart';
import '../models/stored_message.dart';
import 'message_store.dart';

class SqliteMessageStore implements MessageStore {
  SqliteMessageStore._(this._db);

  final Database _db;
  final _changes = StreamController<void>.broadcast();

  static Future<SqliteMessageStore> open() async {
    final path = p.join(await getDatabasesPath(), 'linkmesh.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            sender_name TEXT NOT NULL,
            receiver_id TEXT NOT NULL,
            peer_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            content TEXT NOT NULL,
            hop_count INTEGER NOT NULL,
            max_hops INTEGER NOT NULL,
            ref_id TEXT,
            lat REAL,
            lng REAL,
            outgoing INTEGER NOT NULL,
            status INTEGER NOT NULL,
            relay_hops INTEGER NOT NULL
          )''');
        await db.execute(
          'CREATE INDEX idx_messages_peer ON messages(type, peer_id, timestamp)',
        );
        await db.execute(
          'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
    );
    return SqliteMessageStore._(db);
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<StoredMessage?> get(String id) async {
    final rows = await _db.query('messages', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<void> save(StoredMessage stored) async {
    final m = stored.message;
    await _db.insert(
      'messages',
      {
        'id': m.id,
        'type': m.type.name,
        'sender_id': m.senderId,
        'sender_name': m.senderName,
        'receiver_id': m.receiverId,
        'peer_id': stored.peerId,
        'timestamp': m.timestamp,
        'content': m.content,
        'hop_count': m.hopCount,
        'max_hops': m.maxHops,
        'ref_id': m.refId,
        'lat': m.lat,
        'lng': m.lng,
        'outgoing': stored.outgoing ? 1 : 0,
        'status': stored.status.index,
        'relay_hops': stored.relayHops,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changes.add(null);
  }

  @override
  Future<List<StoredMessage>> conversation(String peerId) async {
    final rows = await _db.query(
      'messages',
      where: 'type = ? AND peer_id = ?',
      whereArgs: [MessageType.text.name, peerId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<ConversationSummary>> conversations() async {
    // Latest message per peer, plus the most recent name they used.
    final rows = await _db.rawQuery('''
      SELECT m.*,
        (SELECT sender_name FROM messages n
           WHERE n.type = m.type AND n.peer_id = m.peer_id AND n.outgoing = 0
           ORDER BY n.timestamp DESC LIMIT 1) AS peer_name
      FROM messages m
      WHERE m.type = ? AND m.timestamp = (
        SELECT MAX(timestamp) FROM messages x
        WHERE x.type = m.type AND x.peer_id = m.peer_id)
      GROUP BY m.peer_id
      ORDER BY m.timestamp DESC
    ''', [MessageType.text.name]);
    return rows
        .map((r) => ConversationSummary(
              peerId: r['peer_id']! as String,
              peerName: (r['peer_name'] as String?) ?? '',
              lastMessage: _fromRow(r),
            ))
        .toList();
  }

  @override
  Future<List<StoredMessage>> sosAlerts() async {
    final rows = await _db.rawQuery('''
      SELECT m.* FROM messages m
      WHERE m.type = ? AND m.outgoing = 0 AND m.timestamp = (
        SELECT MAX(timestamp) FROM messages x
        WHERE x.type = m.type AND x.outgoing = 0 AND x.sender_id = m.sender_id)
      GROUP BY m.sender_id
      ORDER BY m.timestamp DESC
    ''', [MessageType.sos.name]);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<String?> getSetting(String key) async {
    final rows =
        await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value']! as String;
  }

  @override
  Future<void> setSetting(String key, String value) => _db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  StoredMessage _fromRow(Map<String, Object?> r) => StoredMessage(
        message: MeshMessage(
          id: r['id']! as String,
          type: MessageType.values.byName(r['type']! as String),
          senderId: r['sender_id']! as String,
          senderName: r['sender_name']! as String,
          receiverId: r['receiver_id']! as String,
          timestamp: r['timestamp']! as int,
          content: r['content']! as String,
          hopCount: r['hop_count']! as int,
          maxHops: r['max_hops']! as int,
          refId: r['ref_id'] as String?,
          lat: (r['lat'] as num?)?.toDouble(),
          lng: (r['lng'] as num?)?.toDouble(),
        ),
        outgoing: r['outgoing'] == 1,
        status: DeliveryStatus.values[r['status']! as int],
        relayHops: r['relay_hops']! as int,
      );
}
