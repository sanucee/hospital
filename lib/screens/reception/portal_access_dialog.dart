import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../widgets/common.dart';

/// How a patient signs in to the patient portal, and (with Firebase) their
/// portal account.
class PortalAccessDialog extends StatefulWidget {
  const PortalAccessDialog({super.key, required this.patientId});

  final String patientId;

  @override
  State<PortalAccessDialog> createState() => _PortalAccessDialogState();
}

class _PortalAccessDialogState extends State<PortalAccessDialog> {
  late final _email = TextEditingController(
    text: context.read<HospitalStore>().patientById(widget.patientId)?.email,
  );
  final _pass = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final p = store.patientById(widget.patientId)!;
    final hasAccount = p.portalUid != null;
    return AlertDialog(
      title: Text('Patient portal – ${p.name}'),
      content: SizedBox(
        width: 420,
        child: !store.isRemote
            ? Text(
                'On the login screen, choose "Patients" and sign in with '
                'MRN ${p.mrn} and the date of birth ${fmtDate(p.dateOfBirth)}.'
                '\n\nPatients can then book online, cancel bookings, see '
                'reviewed results, prescriptions and bills, and update their '
                'contact details.',
              )
            : hasAccount
            ? Text(
                'Signs in with ${p.portalEmail}.\n\nRemoving access signs '
                'them out of the portal; their records are kept.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Create a portal sign-in so the patient can book online '
                    'and see their results and bills.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    decoration: const InputDecoration(
                      labelText: 'Temporary password (6+ characters)',
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (store.isRemote && hasAccount)
          OutlinedButton(
            onPressed: () => guarded(
              context,
              () => store.revokePortalLogin(p.id),
              success: 'Portal access removed',
            ),
            child: const Text('Remove access'),
          ),
        if (store.isRemote && !hasAccount)
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              if (await guarded(
                context,
                () => store.createPortalLogin(
                  p.id,
                  email: _email.text,
                  password: _pass.text,
                ),
                success: 'Portal account created',
              )) {
                nav.pop();
              }
            },
            child: const Text('Create portal login'),
          ),
      ],
    );
  }
}
