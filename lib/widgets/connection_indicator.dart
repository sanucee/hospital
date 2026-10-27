import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospital_store.dart';
import '../data/lan_backend.dart';

/// Shows, in the app bar, when this computer can't reach the hospital
/// server or has changes still waiting to be sent. Nothing is shown while
/// everything is in sync, or when the hospital server isn't used.
class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final backend = context.read<HospitalStore>().backend;
    if (backend is! LanBackend) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: backend.status,
      builder: (context, _, _) {
        final waiting = backend.pendingChanges;
        if (backend.online && waiting == 0) return const SizedBox.shrink();
        final offline = !backend.online;
        final color = offline ? Colors.orange.shade800 : Colors.blueGrey;
        final label = offline
            ? (waiting == 0 ? 'Offline' : 'Offline · $waiting waiting')
            : 'Sending $waiting…';
        return Tooltip(
          message: offline
              ? 'The hospital server at ${backend.serverUri.host} can\'t be '
                    'reached. You can keep working: changes are saved on this '
                    'computer and sent when the connection returns.'
              : 'Changes are being sent to the hospital server.',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Chip(
              avatar: Icon(
                offline ? Icons.cloud_off : Icons.sync,
                size: 16,
                color: color,
              ),
              label: Text(label, style: TextStyle(color: color)),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: color.withValues(alpha: 0.5)),
            ),
          ),
        );
      },
    );
  }
}
