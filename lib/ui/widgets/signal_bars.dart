import 'package:flutter/material.dart';

/// Four-bar signal strength indicator.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.bars, this.active = true});

  /// 0–4.
  final int bars;

  /// Greyed out when the peer isn't connected.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = !active
        ? scheme.outline
        : bars <= 1
            ? scheme.error
            : scheme.primary;
    return Semantics(
      label: 'Signal $bars of 4',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 4,
              height: 6.0 + i * 4,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: i < bars ? on : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}
