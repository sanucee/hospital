import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospital_store.dart';
import 'common.dart';

/// The signed-in staff member changes their own password.
Future<void> showChangePasswordDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _ChangePasswordDialog());

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, {Key? key}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: key,
        controller: c,
        obscureText: true,
        decoration: InputDecoration(labelText: label),
      ),
    );
    return AlertDialog(
      title: const Text('Change password'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(_current, 'Current password', key: const Key('pw-current')),
            field(
              _next,
              'New password (6+ characters)',
              key: const Key('pw-new'),
            ),
            field(_again, 'New password again', key: const Key('pw-again')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('pw-save'),
          onPressed: () async {
            final nav = Navigator.of(context);
            final ok = await guarded(context, () async {
              if (_next.text != _again.text) {
                throw HospitalException('The new passwords do not match');
              }
              await context.read<HospitalStore>().changeMyPassword(
                _current.text,
                _next.text,
              );
            }, success: 'Password changed');
            if (ok) nav.pop();
          },
          child: const Text('Change password'),
        ),
      ],
    );
  }
}
