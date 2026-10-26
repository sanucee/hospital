import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospital_store.dart';
import '../models/models.dart';
import 'common.dart';

/// Edits the hospital details printed on receipts and reports.
Future<void> showProfileDialog(BuildContext context) async {
  final store = context.read<HospitalStore>();
  final p = store.profile;
  final fields = [
    ('Hospital name', TextEditingController(text: p.name)),
    ('Address', TextEditingController(text: p.address)),
    ('Phone', TextEditingController(text: p.phone)),
    ('Email', TextEditingController(text: p.email)),
    ('Tax / registration no.', TextEditingController(text: p.taxId)),
    ('Receipt footer', TextEditingController(text: p.receiptFooter)),
  ];
  final countryCode = TextEditingController(text: p.countryCode);
  final hours = TextEditingController(text: p.reminderHours.join(', '));
  final template = TextEditingController(text: p.reminderTemplate);
  var autoSend = p.autoSendReminders;
  final erFee = TextEditingController(text: p.emergencyFee.toString());
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Hospital details'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Printed on receipts, prescriptions and reports.'),
                const SizedBox(height: 12),
                for (final (label, c) in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: c,
                      decoration: InputDecoration(labelText: label),
                    ),
                  ),
                TextField(
                  controller: erFee,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Emergency attendance fee',
                    helperText:
                        'Billed when a doctor sees an emergency patient',
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Appointment reminders',
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: countryCode,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Country calling code',
                    helperText: 'Turns 0803… into +234803… for SMS/WhatsApp',
                    prefixText: '+',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hours,
                  decoration: const InputDecoration(
                    labelText: 'Send reminders (hours before)',
                    helperText: 'Comma separated, e.g. 24, 2',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: template,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'Reminder message',
                    helperText: kReminderPlaceholders.join(' '),
                    helperMaxLines: 2,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: autoSend,
                  onChanged: (v) => setState(() => autoSend = v),
                  title: const Text('Send SMS/WhatsApp automatically'),
                  subtitle: const Text(
                    'Needs the sendDueReminders Cloud Function with Twilio '
                    'configured. Otherwise reception sends them by hand.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              if (await guarded(
                ctx,
                () => store.updateProfile(
                  name: fields[0].$2.text,
                  address: fields[1].$2.text,
                  phone: fields[2].$2.text,
                  email: fields[3].$2.text,
                  taxId: fields[4].$2.text,
                  receiptFooter: fields[5].$2.text,
                  countryCode: countryCode.text,
                  reminderHours: _parseHours(hours.text),
                  reminderTemplate: template.text,
                  autoSendReminders: autoSend,
                  emergencyFee: double.tryParse(erFee.text.trim()),
                ),
                success: 'Saved',
              )) {
                nav.pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

List<int> _parseHours(String text) {
  final parts = text.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty);
  return [
    for (final s in parts)
      int.tryParse(s) ??
          (throw HospitalException('"$s" is not a whole number of hours')),
  ];
}
