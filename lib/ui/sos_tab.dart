import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stored_message.dart';
import '../state/providers.dart';
import 'format.dart';

class SosTab extends ConsumerStatefulWidget {
  const SosTab({super.key});

  @override
  ConsumerState<SosTab> createState() => _SosTabState();
}

class _SosTabState extends ConsumerState<SosTab> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(sosActiveProvider).value ?? false;
    final alerts = ref.watch(sosAlertsProvider).value ?? const [];
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: active ? scheme.errorContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  active ? 'SOS is broadcasting' : 'Emergency broadcast',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  active
                      ? 'Repeating every ${_seconds(ref)} s to every device in '
                          'the mesh, with your GPS position when available.'
                      : 'Sends your message and GPS position to every device '
                          'in range, and keeps repeating until you stop it.',
                ),
                if (!active) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _message,
                    decoration: const InputDecoration(
                      labelText: 'Message (optional)',
                      hintText: 'e.g. Injured, need water',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () {
                    final sos = ref.read(sosServiceProvider);
                    active ? sos.stop() : sos.start(_message.text);
                  },
                  icon: Icon(active ? Icons.stop_circle : Icons.sos),
                  label: Text(active ? 'Stop SOS' : 'Start SOS'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Alerts received',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (alerts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No SOS alerts nearby.', textAlign: TextAlign.center),
          )
        else
          for (final alert in alerts) _AlertTile(alert: alert),
      ],
    );
  }

  int _seconds(WidgetRef ref) =>
      ref.read(sosServiceProvider).interval.inSeconds;
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final StoredMessage alert;

  @override
  Widget build(BuildContext context) {
    final m = alert.message;
    final location = m.hasLocation
        ? '${m.lat!.toStringAsFixed(5)}, ${m.lng!.toStringAsFixed(5)}'
        : 'Location unavailable';
    final hops = alert.relayHops == 0 ? 'direct' : relayLabel(alert.relayHops);
    return Card(
      child: ListTile(
        leading: Icon(Icons.warning_amber,
            color: Theme.of(context).colorScheme.error),
        title: Text('${m.senderName}: ${m.content}'),
        subtitle: Text('$location\n${formatTimestamp(m.timestamp)} · $hops'),
        isThreeLine: true,
      ),
    );
  }
}
