import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final staff = [...store.users]
      ..sort((a, b) => a.role.index.compareTo(b.role.index));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            showDialog(context: context, builder: (_) => const _StaffDialog()),
        icon: const Icon(Icons.person_add),
        label: const Text('Add staff'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final u in staff)
            ListTile(
              leading: CircleAvatar(child: Text(u.name[0])),
              title: Text(u.name),
              subtitle: Text(
                [
                  u.role.label,
                  store.isRemote
                      ? (u.authUid == null ? 'No login' : u.email)
                      : '@${u.username}',
                  if (u.specialization != null) u.specialization!,
                  if (u.role == UserRole.doctor)
                    'Fee ${money(u.consultationFee)}',
                ].join(' · '),
              ),
              trailing: u.id == store.currentUser?.id
                  ? const StatusChip('You', color: Colors.teal)
                  : Wrap(
                      spacing: 4,
                      children: [
                        if (store.isRemote && u.authUid == null)
                          TextButton.icon(
                            icon: const Icon(Icons.key),
                            label: const Text('Create login'),
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => _CreateLoginDialog(staff: u),
                            ),
                          ),
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => guarded(
                            context,
                            () => store.removeStaff(u.id),
                            success: '${u.name} removed',
                          ),
                        ),
                      ],
                    ),
            ),
          if (!store.isRemote) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.restart_alt, color: Colors.red),
              title: const Text('Reset to demo data'),
              subtitle: const Text(
                'Deletes all records and reloads sample data',
              ),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reset all data?'),
                    content: const Text('This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await store.resetToDemoData();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _StaffDialog extends StatefulWidget {
  const _StaffDialog();

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _spec = TextEditingController();
  final _fee = TextEditingController(text: '50');
  UserRole _role = UserRole.doctor;

  @override
  Widget build(BuildContext context) {
    final remote = context.read<HospitalStore>().isRemote;
    return AlertDialog(
      title: const Text('Add staff member'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final r in UserRole.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) => setState(() => _role = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _username,
                keyboardType: remote ? TextInputType.emailAddress : null,
                decoration: InputDecoration(
                  labelText: remote ? 'Sign-in email' : 'Username',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: remote
                      ? 'At least 6 characters; share it with them'
                      : null,
                ),
              ),
              if (_role == UserRole.doctor) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _spec,
                  decoration: const InputDecoration(
                    labelText: 'Specialization',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _fee,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Consultation fee',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            final ok = await guarded(context, () async {
              if ([
                _name,
                _username,
                _password,
              ].any((c) => c.text.trim().isEmpty)) {
                throw HospitalException('Name, username and password required');
              }
              if (remote && _password.text.length < 6) {
                throw HospitalException(
                  'Password must be at least 6 characters',
                );
              }
              await context.read<HospitalStore>().addStaff(
                name: _name.text.trim(),
                username: _username.text.trim(),
                password: _password.text,
                role: _role,
                specialization: _role == UserRole.doctor
                    ? _spec.text.trim()
                    : null,
                consultationFee: _role == UserRole.doctor
                    ? double.tryParse(_fee.text) ?? 0
                    : 0,
              );
            }, success: 'Staff member added');
            if (ok) nav.pop();
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _CreateLoginDialog extends StatefulWidget {
  const _CreateLoginDialog({required this.staff});

  final StaffUser staff;

  @override
  State<_CreateLoginDialog> createState() => _CreateLoginDialogState();
}

class _CreateLoginDialogState extends State<_CreateLoginDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Login for ${widget.staff.name}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Sign-in email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                helperText: 'At least 6 characters; share it with them',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            final store = context.read<HospitalStore>();
            final ok = await guarded(context, () async {
              if (_email.text.trim().isEmpty || _password.text.length < 6) {
                throw HospitalException(
                  'Enter an email and a password of 6+ characters',
                );
              }
              await store.createLoginFor(
                widget.staff.id,
                email: _email.text,
                password: _password.text,
              );
            }, success: 'Login created for ${widget.staff.name}');
            if (ok) nav.pop();
          },
          child: const Text('Create login'),
        ),
      ],
    );
  }
}
