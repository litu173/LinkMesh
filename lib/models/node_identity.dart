import 'dart:convert';
import 'dart:typed_data';

/// This device's identity on the mesh.
class NodeIdentity {
  const NodeIdentity({required this.id, required this.name});

  final String id;
  final String name;

  Uint8List encode() =>
      Uint8List.fromList(utf8.encode(jsonEncode({'id': id, 'name': name})));

  static NodeIdentity? tryDecode(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      return NodeIdentity(
        id: json['id']! as String,
        name: (json['name'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
