import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Staff directory (HR details, logins, leaving/rejoining) and leave
/// approvals. Salaries live under Finance.
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final pending = store.pendingLeaves.length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const _StaffDialog(),
          ),
          icon: const Icon(Icons.person_add),
          label: const Text('Add staff'),
        ),
        body: Column(
          children: [
            TabBar(
              tabs: [
                Tab(text: 'Directory (${store.activeStaff.length} active)'),
                Tab(text: 'Leave${pending > 0 ? ' ($pending pending)' : ''}'),
              ],
            ),
            const Expanded(
              child: TabBarView(children: [_Directory(), _LeaveTab()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Directory extends StatelessWidget {
  const _Directory();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final staff = [...store.users]
      ..sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.role.index.compareTo(b.role.index);
      });
    final onLeave = store.onLeaveToday.map((l) => l.staffId).toSet();
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final u in staff)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: u.active ? null : Colors.grey.shade300,
              child: Text(u.name[0]),
            ),
            title: Text(
              u.name,
              style: TextStyle(color: u.active ? null : Colors.grey),
            ),
            subtitle: Text(
              [
                u.role.label,
                if (u.designation.isNotEmpty) u.designation,
                if (u.department.isNotEmpty) u.department,
                if (u.role.canSignIn)
                  store.isRemote
                      ? (u.authUid == null ? 'No login' : u.email)
                      : '@${u.username}',
                if (u.specialization != null && u.specialization!.isNotEmpty)
                  u.specialization!,
                if (u.role == UserRole.doctor)
                  'Fee ${money(u.consultationFee)}',
                if (u.phone.isNotEmpty) u.phone,
                if (u.joinedOn != null) 'Joined ${fmtDate(u.joinedOn)}',
              ].join(' · '),
            ),
            onTap: () => showDialog(
              context: context,
              builder: (_) => _ProfileDialog(staff: u),
            ),
            trailing: Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!u.active)
                  const StatusChip('Left', color: Colors.grey)
                else if (onLeave.contains(u.id))
                  const StatusChip('On leave', color: Colors.orange),
                if (u.id == store.currentUser?.id)
                  const StatusChip('You', color: Colors.teal)
                else ...[
                  if (store.isRemote &&
                      u.active &&
                      u.role.canSignIn &&
                      u.authUid == null)
                    TextButton.icon(
                      icon: const Icon(Icons.key),
                      label: const Text('Create login'),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _CreateLoginDialog(staff: u),
                      ),
                    ),
                  IconButton(
                    tooltip: u.active ? 'Mark as left' : 'Rejoin',
                    icon: Icon(u.active ? Icons.person_off : Icons.person_add),
                    onPressed: () => guarded(
                      context,
                      () => store.setStaffActive(u.id, !u.active),
                      success: u.active
                          ? '${u.name} marked as left'
                          : '${u.name} is active again',
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (!store.isRemote) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restart_alt, color: Colors.red),
            title: const Text('Reset to demo data'),
            subtitle: const Text('Deletes all records and reloads sample data'),
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
    );
  }
}

class _LeaveTab extends StatelessWidget {
  const _LeaveTab();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final all = [...store.leaves]
      ..sort((a, b) {
        if ((a.status == LeaveStatus.pending) !=
            (b.status == LeaveStatus.pending)) {
          return a.status == LeaveStatus.pending ? -1 : 1;
        }
        return b.from.compareTo(a.from);
      });
    if (all.isEmpty) {
      return const EmptyState('No leave requests', icon: Icons.beach_access);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        for (final l in all)
          Card(
            child: ListTile(
              leading: const Icon(Icons.beach_access),
              title: Text(
                '${store.userName(l.staffId)} · ${l.type.label} leave',
              ),
              subtitle: Text(
                '${fmtDate(l.from)} – ${fmtDate(l.to)} (${l.days} day(s))'
                '${l.reason.isEmpty ? '' : ' · ${l.reason}'}',
              ),
              trailing: l.status == LeaveStatus.pending
                  ? Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => guarded(
                            context,
                            () => store.decideLeave(l.id, approve: false),
                          ),
                          child: const Text('Decline'),
                        ),
                        FilledButton(
                          onPressed: () => guarded(
                            context,
                            () => store.decideLeave(l.id, approve: true),
                            success: 'Leave approved',
                          ),
                          child: const Text('Approve'),
                        ),
                      ],
                    )
                  : StatusChip(
                      l.status == LeaveStatus.approved
                          ? 'Approved'
                          : 'Declined',
                      color: l.status == LeaveStatus.approved
                          ? Colors.green
                          : Colors.red,
                    ),
            ),
          ),
      ],
    );
  }
}

/// HR fields shared by the add and edit dialogs.
class _HrFields {
  _HrFields([StaffUser? u])
    : name = TextEditingController(text: u?.name),
      department = TextEditingController(text: u?.department),
      designation = TextEditingController(text: u?.designation),
      phone = TextEditingController(text: u?.phone),
      spec = TextEditingController(text: u?.specialization),
      fee = TextEditingController(
        text: (u?.consultationFee ?? 50).toStringAsFixed(0),
      ),
      joinedOn = u?.joinedOn;

  final TextEditingController name;
  final TextEditingController department;
  final TextEditingController designation;
  final TextEditingController phone;
  final TextEditingController spec;
  final TextEditingController fee;
  DateTime? joinedOn;

  List<Widget> build(
    BuildContext context,
    UserRole role,
    void Function(VoidCallback) setState,
  ) {
    Widget field(
      TextEditingController c,
      String label, {
      TextInputType? type,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        decoration: InputDecoration(labelText: label),
      ),
    );
    return [
      field(name, 'Full name'),
      Row(
        children: [
          Expanded(child: field(designation, 'Designation')),
          const SizedBox(width: 12),
          Expanded(child: field(department, 'Department')),
        ],
      ),
      Row(
        children: [
          Expanded(child: field(phone, 'Phone', type: TextInputType.phone)),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(joinedOn == null ? 'Joined on' : fmtDate(joinedOn)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: joinedOn ?? DateTime.now(),
                    firstDate: DateTime(1970),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => joinedOn = d);
                },
              ),
            ),
          ),
        ],
      ),
      if (role == UserRole.doctor) ...[
        field(spec, 'Specialization'),
        field(fee, 'Consultation fee', type: TextInputType.number),
      ],
    ];
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.staff});

  final StaffUser staff;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _f = _HrFields(widget.staff);

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final u = widget.staff;
    final leaves = store.leavesFor(u.id);
    return AlertDialog(
      title: Text('${u.name} · ${u.role.label}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._f.build(context, u.role, setState),
              if (leaves.isNotEmpty) ...[
                Text('Leave', style: Theme.of(context).textTheme.titleSmall),
                for (final l in leaves.take(5))
                  Text(
                    '${l.type.label}: ${fmtDate(l.from)} – ${fmtDate(l.to)} '
                    '(${l.status.name})',
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
            if (await guarded(context, () async {
              if (_f.name.text.trim().isEmpty) {
                throw HospitalException('Enter a name');
              }
              await store.updateStaffProfile(
                u.id,
                name: _f.name.text,
                department: _f.department.text,
                designation: _f.designation.text,
                phone: _f.phone.text,
                joinedOn: _f.joinedOn,
                specialization: _f.spec.text.trim(),
                consultationFee: double.tryParse(_f.fee.text),
              );
            }, success: 'Saved')) {
              nav.pop();
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _StaffDialog extends StatefulWidget {
  const _StaffDialog();

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  final _f = _HrFields();
  final _username = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.doctor;

  @override
  Widget build(BuildContext context) {
    final remote = context.read<HospitalStore>().isRemote;
    final login = _role.canSignIn;
    return AlertDialog(
      title: const Text('Add staff member'),
      content: SizedBox(
        width: 460,
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
              ..._f.build(context, _role, setState),
              if (login) ...[
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
              ] else
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Support staff are on the staff list and payroll but '
                    "don't sign in.",
                  ),
                ),
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
            final store = context.read<HospitalStore>();
            final ok = await guarded(context, () async {
              if (_f.name.text.trim().isEmpty) {
                throw HospitalException('Enter a name');
              }
              if (login &&
                  (_username.text.trim().isEmpty || _password.text.isEmpty)) {
                throw HospitalException('Username and password required');
              }
              if (login && remote && _password.text.length < 6) {
                throw HospitalException(
                  'Password must be at least 6 characters',
                );
              }
              await store.addStaff(
                name: _f.name.text.trim(),
                username: login ? _username.text.trim() : '',
                password: login ? _password.text : '',
                role: _role,
                specialization: _role == UserRole.doctor
                    ? _f.spec.text.trim()
                    : null,
                consultationFee: _role == UserRole.doctor
                    ? double.tryParse(_f.fee.text) ?? 0
                    : 0,
                department: _f.department.text.trim(),
                designation: _f.designation.text.trim(),
                phone: _f.phone.text.trim(),
                joinedOn: _f.joinedOn,
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
