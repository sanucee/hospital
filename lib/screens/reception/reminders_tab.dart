import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Reminders waiting to be sent, queued for later, and already handled.
class RemindersTab extends StatefulWidget {
  const RemindersTab({super.key});

  @override
  State<RemindersTab> createState() => _RemindersTabState();
}

enum _View { due, upcoming, history }

class _RemindersTabState extends State<RemindersTab> {
  _View _view = _View.due;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final due = store.remindersDue();
    final upcoming = store.upcomingReminders;
    final history =
        store.reminders
            .where((r) => r.status != ReminderStatus.pending)
            .toList()
          ..sort(
            (a, b) => (b.sentAt ?? b.sendAt).compareTo(a.sentAt ?? a.sendAt),
          );
    final list = switch (_view) {
      _View.due => due,
      _View.upcoming => upcoming,
      _View.history => history.take(200).toList(),
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_View>(
                segments: [
                  ButtonSegment(
                    value: _View.due,
                    label: Text('To send (${due.length})'),
                    icon: const Icon(Icons.notifications_active),
                  ),
                  ButtonSegment(
                    value: _View.upcoming,
                    label: Text('Scheduled (${upcoming.length})'),
                    icon: const Icon(Icons.schedule_send),
                  ),
                  const ButtonSegment(
                    value: _View.history,
                    label: Text('History'),
                    icon: Icon(Icons.history),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (v) => setState(() => _view = v.first),
              ),
              Text(
                store.profile.autoSendReminders
                    ? 'Automatic sending is on: SMS and WhatsApp go out from '
                          'the server; email is sent from here.'
                    : 'Sent from this device. Turn on automatic sending in '
                          'Hospital details.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(switch (_view) {
                  _View.due => 'No reminders to send right now',
                  _View.upcoming => 'No reminders scheduled',
                  _View.history => 'No reminders sent yet',
                }, icon: Icons.mark_email_read)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _tile(context, store, list[i]),
                ),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    HospitalStore store,
    AppointmentReminder r,
  ) {
    final a = store.appointmentById(r.appointmentId);
    final p = store.patientById(r.patientId);
    final open =
        r.status == ReminderStatus.pending || r.status == ReminderStatus.failed;
    final hasPhone = (p?.phone ?? '').trim().isNotEmpty;
    final hasEmail = (p?.email ?? '').trim().isNotEmpty;
    final when = r.sendAt.toLocal();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(switch (r.channel) {
                  ReminderChannel.sms => Icons.sms,
                  ReminderChannel.whatsapp => Icons.chat,
                  ReminderChannel.email => Icons.email,
                }, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${p?.name ?? 'Unknown'} · ${r.to}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                _statusChip(r),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (a != null)
                  'Appointment ${fmtDate(a.scheduledAt)} ${fmtTime(a.scheduledAt)} '
                      'with ${store.userName(a.doctorId)}',
                r.status == ReminderStatus.sent
                    ? 'Sent ${fmtDateTime(r.sentAt?.toLocal())}'
                          '${r.sentBy == 'system'
                              ? ' automatically'
                              : r.sentBy == null
                              ? ''
                              : ' by ${store.userName(r.sentBy!)}'}'
                    : 'Send at ${fmtDateTime(when)}',
                if (r.error.isNotEmpty) 'Error: ${r.error}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(r.message),
            if (open)
              Wrap(
                spacing: 4,
                children: [
                  if (hasPhone) ...[
                    TextButton.icon(
                      icon: const Icon(Icons.sms),
                      label: const Text('SMS'),
                      onPressed: () =>
                          _send(context, store, r, ReminderChannel.sms),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.chat),
                      label: const Text('WhatsApp'),
                      onPressed: () =>
                          _send(context, store, r, ReminderChannel.whatsapp),
                    ),
                  ],
                  if (hasEmail)
                    TextButton.icon(
                      icon: const Icon(Icons.email),
                      label: const Text('Email'),
                      onPressed: () =>
                          _send(context, store, r, ReminderChannel.email),
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy text'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: r.message));
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Message copied')),
                      );
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.done),
                    label: const Text('Mark sent'),
                    onPressed: () =>
                        guarded(context, () => store.markReminderSent(r.id)),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.block),
                    label: const Text('Skip'),
                    onPressed: () =>
                        guarded(context, () => store.skipReminder(r.id)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(AppointmentReminder r) => switch (r.status) {
    ReminderStatus.pending => StatusChip(
      r.sendAt.isAfter(DateTime.now()) ? 'Scheduled' : 'Due',
      color: r.sendAt.isAfter(DateTime.now()) ? Colors.blueGrey : Colors.orange,
    ),
    ReminderStatus.sending => const StatusChip('Sending', color: Colors.blue),
    ReminderStatus.sent => const StatusChip('Sent', color: Colors.green),
    ReminderStatus.failed => const StatusChip('Failed', color: Colors.red),
    ReminderStatus.cancelled => const StatusChip('Skipped', color: Colors.grey),
  };

  /// Opens the device's messaging app with the reminder filled in, then
  /// asks whether it went out.
  Future<void> _send(
    BuildContext context,
    HospitalStore store,
    AppointmentReminder r,
    ReminderChannel via,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = store.reminderLink(r, via: via);
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!context.mounted) return;
    if (!launched) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not open ${via.label} on this device. '
            'Copy the text and send it another way.',
          ),
        ),
      );
      return;
    }
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Did the ${via.label} go out?'),
        content: Text(
          'Mark the reminder to ${store.patientName(r.patientId)} as sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark sent'),
          ),
        ],
      ),
    );
    if (sent == true && context.mounted) {
      await guarded(
        context,
        () => store.markReminderSent(r.id),
        success: 'Reminder marked sent',
      );
    }
  }
}
