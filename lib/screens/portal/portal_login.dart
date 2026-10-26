import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../widgets/common.dart';

/// Patient sign-in on the login screen: MRN and date of birth on this
/// device, or email and password with Firebase. New patients register here.
class PortalLoginForm extends StatefulWidget {
  const PortalLoginForm({super.key});

  @override
  State<PortalLoginForm> createState() => _PortalLoginFormState();
}

class _PortalLoginFormState extends State<PortalLoginForm> {
  final _id = TextEditingController();
  final _pass = TextEditingController();
  DateTime? _dob;
  String? _error;
  bool _busy = false;

  Future<void> _signIn() async {
    final store = context.read<HospitalStore>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (store.isRemote) {
        await store.login(_id.text, _pass.text);
      } else {
        if (_id.text.trim().isEmpty || _dob == null) {
          throw HospitalException('Enter your MRN and date of birth');
        }
        await store.portalSignIn(mrn: _id.text, dateOfBirth: _dob!);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final remote = store.isRemote;
    final scheme = Theme.of(context).colorScheme;
    final demo = remote || store.patients.isEmpty ? null : store.patients.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Book appointments, see your results and bills.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('portal-id'),
          controller: _id,
          keyboardType: remote ? TextInputType.emailAddress : null,
          decoration: InputDecoration(
            labelText: remote ? 'Email' : 'Medical record number (MRN)',
            hintText: remote ? null : 'MRN-00001',
            prefixIcon: const Icon(Icons.badge),
          ),
        ),
        const SizedBox(height: 12),
        if (remote)
          TextField(
            controller: _pass,
            obscureText: true,
            onSubmitted: (_) => _signIn(),
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock),
            ),
          )
        else
          InkWell(
            key: const Key('portal-dob'),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _dob ?? DateTime(1990),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
                initialEntryMode: DatePickerEntryMode.input,
              );
              if (d != null) setState(() => _dob = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date of birth',
                prefixIcon: Icon(Icons.cake),
              ),
              child: Text(fmtDate(_dob)),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('portal-login'),
          onPressed: _busy ? null : _signIn,
          icon: const Icon(Icons.login),
          label: const Text('Sign in to the patient portal'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const _RegisterDialog(),
          ),
          child: const Text('New patient? Register online'),
        ),
        if (demo != null) ...[
          const SizedBox(height: 8),
          Center(
            child: ActionChip(
              avatar: const Icon(Icons.person, size: 18),
              label: Text('Demo patient: ${demo.name}'),
              onPressed: () {
                _id.text = demo.mrn;
                _dob = demo.dateOfBirth;
                _signIn();
              },
            ),
          ),
        ],
        if (!remote)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Your MRN is on your hospital card and receipts.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _RegisterDialog extends StatefulWidget {
  const _RegisterDialog();

  @override
  State<_RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<_RegisterDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  DateTime? _dob;
  String _gender = 'Female';
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final store = context.read<HospitalStore>();
    final nav = Navigator.of(context);
    if (_dob == null) {
      setState(() => _error = 'Enter your date of birth');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.portalRegister(
        name: _name.text,
        dateOfBirth: _dob!,
        gender: _gender,
        phone: _phone.text,
        email: _email.text,
        password: _pass.text,
      );
      nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = context.read<HospitalStore>().isRemote;
    return AlertDialog(
      title: const Text('Register as a new patient'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dob ?? DateTime(1990),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                          initialEntryMode: DatePickerEntryMode.input,
                        );
                        if (d != null) setState(() => _dob = d);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date of birth',
                        ),
                        child: Text(fmtDate(_dob)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: const InputDecoration(labelText: 'Gender'),
                      items: const [
                        DropdownMenuItem(
                          value: 'Female',
                          child: Text('Female'),
                        ),
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (v) => setState(() => _gender = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  helperText: 'For appointment confirmations and reminders',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: remote ? 'Email (to sign in)' : 'Email (optional)',
                ),
              ),
              if (remote) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Choose a password',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Reception checks your details and adds insurance at your '
                'first visit.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Register'),
        ),
      ],
    );
  }
}
