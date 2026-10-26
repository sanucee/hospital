import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospital_store.dart';
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
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
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
  );
}
