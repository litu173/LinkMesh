# LinkMesh

Offline-first messaging over Bluetooth Low Energy. Phones find each other with no
internet or cell network, chat one-to-one, and relay each other's messages
across a multi-hop mesh. An SOS mode repeatedly broadcasts your GPS position to
every node in range.

Status: **MVP (spec steps 1–5)**, Android first.

**[Live preview & mesh simulator](https://litu173.github.io/LinkMesh/)** ·
**[Download the APK](https://github.com/litu173/LinkMesh/releases/latest/download/LinkMesh.apk)**

## Setup

The repo holds `lib/`, `test/` and the Android manifest. Generate the rest of
the Android project once with Flutter (≥ 3.44):

```bash
flutter create . --platforms android --org com.linkmesh --project-name linkmesh
```

`flutter create` keeps existing files, so the custom `AndroidManifest.xml`
(BLE + location permissions) is kept. Then:

```bash
flutter pub get
flutter test
flutter run
```

Build an installable APK with `flutter build apk --release`. The output is
`build/app/outputs/flutter-apk/app-release.apk`, signed with the debug key,
which is fine for side-loading test devices.

> `permission_handler` is pinned to `^12.0.1`. Version 13 needs Android SDK 37,
> which Flutter 3.47's Gradle plugin can't resolve yet.

BLE needs **two or more real Android phones**, since emulators have no
Bluetooth radio. Keep the app open in the foreground on each.

> **License note:** `flutter_blue_plus` requires a declared license. The app
> uses `License.nonprofit` (personal, nonprofit or educational use) in
> `lib/ble/ble_transport.dart`. For-profit use needs its paid commercial license.

## Architecture

```
UI (Riverpod)        ui/  home · chats · nearby · sos · chat
  │ watches
State                state/providers.dart
  │
Services             services/  identity · sos · location · permissions
  │
Mesh routing         mesh/mesh_router.dart   ← transport-agnostic, unit tested
  │  MeshTransport interface (mesh/transport.dart)
Link layer           ble/ble_transport.dart  (WiFi Direct / LoRa later)
  │
Storage              data/  MessageStore → SQLite (sqflite) | in-memory
```

The router only uses the `MeshTransport` interface. Phase 2 (WiFi Direct) and
Phase 3 (LoRa) add new transports without changing routing logic.

### BLE link layer

Every phone runs both BLE roles at the same time:

| Role | Package | Does |
|---|---|---|
| Peripheral | `ble_peripheral` | Advertises the LinkMesh service UUID. Its GATT server has an **inbox** characteristic (write) and an **identity** characteristic (read, `{"id","name"}`). |
| Central | `flutter_blue_plus` | Scans for the service on a duty cycle (8 s scan every 20 s). Connects to the strongest peers (up to 5), reads their identity, writes frames into their inbox. |

Each direction of a link is its own GATT connection: A sends to B over A's
connection to B. Frames are split into MTU-sized chunks with a 6-byte header
(`frameId·index·count`) and reassembled per sender (`mesh/chunker.dart`).

The UI shows three connection states: **Connected**, **Weak signal**
(RSSI < −85 dBm) and **Disconnected/in range**.

### Message format

Uses the spec's JSON, plus `type`, `sender_name`, `ref_id`, `lat` and `lng`:

```json
{
  "id": "uuid-v4",
  "type": "text | ack | sos",
  "sender_id": "node-uuid",
  "sender_name": "Ayesha",
  "receiver_id": "node-uuid or *",
  "timestamp": 1759500000000,
  "content": "text message",
  "hop_count": 0,
  "max_hops": 5,
  "ref_id": "acked message id (ack only)",
  "lat": 12.97, "lng": 77.59
}
```

### Mesh logic (`mesh/mesh_router.dart`)

On every received frame:

1. **Own message coming back** with `hop_count > 0`: a neighbour relayed it,
   so its status becomes **⇄ Relayed**.
2. **Already seen** (id in the TTL cache, or already in the DB): ignore.
3. **Text for me**: store it, and send an `ack` back through the mesh.
4. **Ack for me**: the original becomes **✓✓ Delivered**, and the ack carries
   the hop count, which the UI shows as "via N devices".
5. **SOS**: store it, raise an alert, and relay it.
6. **Anything else**: relay it if `hop_count < max_hops`, with `hop_count + 1`.

**Store-and-forward:** every node keeps recent messages (15 min, max 200) in a
relay buffer and replays them to each newly linked peer. This handles devices
dropping out mid-chain, and messages sent while nobody is in range.

### Delivery status

| Icon | Status | Meaning |
|---|---|---|
| 🕓 | pending | No peer yet; it goes out automatically when one appears |
| ✓ | sent | A neighbour accepted it |
| ⇄ | relayed | A neighbour was heard forwarding it |
| ✓✓ | delivered | The recipient's ack came back |

## Tests

`test/fake_network.dart` simulates radio neighbourhoods in memory, so the spec's
scenarios run without hardware:

| Spec scenario | Test |
|---|---|
| Two devices direct | `1. two devices communicate directly` |
| Three-device relay chain | `2. three devices relay through the middle node` |
| Device drop mid-chain | `3. middle device drops…`, `3b. sender with no peers…` |
| Duplicate prevention | `4. dense mesh delivers exactly once…` |
| High latency | `5. high latency links still deliver` |

Plus tests for the `max_hops` bound, SOS propagation, malformed frames,
chunking and the dedupe cache.

### Manual test on devices

1. Install on phones A, B and C, and give each a name (profile icon).
2. **Direct:** put A and B side by side. Both show 1 connected. Send A → B and
   watch the status reach ✓✓.
3. **Relay:** separate A and C beyond range (~50 m+, or through walls), with B
   in between. Message C from A: it should arrive "via 1 device".
4. **Drop:** send while B is switched off, then switch B back on.
5. **SOS:** tap SOS on A. B and C get a red alert with coordinates.

## Known MVP limitations

- **Foreground only.** Android stops BLE when the app is backgrounded. A
  foreground service is planned for Phase 2.
- **Flooding, not routing.** Fine for tens of nodes, but it wastes airtime in
  dense crowds. "Improved routing" is a Phase 2 item.
- **No encryption.** Relays can read message content. Phase 2 adds end-to-end
  encryption (X25519 + AES-GCM).
- **Send-only phones:** some phones can't advertise. They can still send and
  relay through others, but nobody can connect to them.
- The dedupe cache is in memory. After a restart, the DB check still suppresses
  duplicates of messages addressed to this node.

## Roadmap

- **Phase 2:** foreground service, group chat, WiFi Direct transport for files,
  E2E encryption, smarter routing (e.g. pick next hop from ack paths).
- **Phase 3:** ESP32 + LoRa bridge transport (BLE ↔ LoRa), hybrid routing, and
  an offline map of SOS positions.
