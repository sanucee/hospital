import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospital_store.dart';
import '../widgets/common.dart';
import 'patient_detail_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final user = store.currentUser!;
    final items = store.notificationsFor(user);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton.icon(
            onPressed: () => store.markAllRead(user),
            icon: const Icon(Icons.done_all),
            label: const Text('Mark all read'),
          ),
        ],
      ),
      body: items.isEmpty
          ? const EmptyState(
              'No notifications yet',
              icon: Icons.notifications_none,
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final n = items[i];
                final unread = !n.readBy.contains(user.id);
                return ListTile(
                  leading: Icon(
                    unread ? Icons.circle : Icons.circle_outlined,
                    size: 12,
                    color: unread
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(
                    n.title,
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(n.body),
                  trailing: Text(
                    fmtDateTime(n.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onTap: n.patientId == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PatientDetailScreen(patientId: n.patientId!),
                          ),
                        ),
                );
              },
            ),
    );
  }
}
