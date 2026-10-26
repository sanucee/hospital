import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final role = store.currentUser!.role;
    final canRegister = role == UserRole.admin || role == UserRole.receptionist;
    final results = store.searchPatients(_query);

    return Scaffold(
      floatingActionButton: canRegister
          ? FloatingActionButton.extended(
              onPressed: () => showPatientForm(context),
              icon: const Icon(Icons.person_add),
              label: const Text('Register patient'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name, MRN or phone',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? const EmptyState('No patients found', icon: Icons.person_off)
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = results[i];
                      final pendingLabs = store
                          .labOrdersFor(patientId: p.id)
                          .where((o) => store.labQueue.contains(o))
                          .length;
                      return ListTile(
                        leading: CircleAvatar(child: Text(p.name[0])),
                        title: Text(p.name),
                        subtitle: Text(
                          '${p.mrn} · ${p.age}y ${p.gender} · ${p.phone}',
                        ),
                        trailing: Wrap(
                          spacing: 6,
                          children: [
                            if (p.allergies.isNotEmpty)
                              const StatusChip(
                                'Allergy',
                                color: Colors.red,
                                icon: Icons.warning,
                              ),
                            if (pendingLabs > 0)
                              StatusChip(
                                '$pendingLabs lab pending',
                                color: Colors.blue,
                              ),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PatientDetailScreen(patientId: p.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Registers a new patient, or edits [existing].
Future<Patient?> showPatientForm(BuildContext context, {Patient? existing}) {
  return showDialog<Patient>(
    context: context,
    builder: (_) => _PatientForm(existing: existing),
  );
}

class _PatientForm extends StatefulWidget {
  const _PatientForm({this.existing});

  final Patient? existing;

  @override
  State<_PatientForm> createState() => _PatientFormState();
}

class _PatientFormState extends State<_PatientForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _allergies = TextEditingController(
    text: widget.existing?.allergies,
  );
  late DateTime? _dob = widget.existing?.dateOfBirth;
  late String _gender = widget.existing?.gender ?? 'Female';
  late String _blood = widget.existing?.bloodGroup ?? '';
  late String? _insurerId = widget.existing?.insurerId;
  late final _policy = TextEditingController(
    text: widget.existing?.policyNumber,
  );
  late DateTime? _policyExpiry = widget.existing?.policyExpiry;

  static const _bloodGroups = [
    '', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', //
  ];

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_dob == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select date of birth')));
      return;
    }
    final store = context.read<HospitalStore>();
    final nav = Navigator.of(context);
    // Re-fetch: another device may have synced a newer copy meanwhile.
    final e = widget.existing == null
        ? null
        : store.patientById(widget.existing!.id);
    if (e != null) {
      e
        ..name = _name.text.trim()
        ..phone = _phone.text.trim()
        ..email = _email.text.trim()
        ..address = _address.text.trim()
        ..allergies = _allergies.text.trim()
        ..dateOfBirth = _dob!
        ..gender = _gender
        ..bloodGroup = _blood
        ..insurerId = _insurerId
        ..policyNumber = _insurerId == null ? '' : _policy.text.trim()
        ..policyExpiry = _insurerId == null ? null : _policyExpiry;
      await store.updatePatient(e);
      nav.pop(e);
    } else {
      final p = await store.registerPatient(
        name: _name.text.trim(),
        dateOfBirth: _dob!,
        gender: _gender,
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
        bloodGroup: _blood,
        allergies: _allergies.text.trim(),
        insurerId: _insurerId,
        policyNumber: _policy.text.trim(),
        policyExpiry: _policyExpiry,
      );
      nav.pop(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Required' : null;
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Register patient' : 'Edit patient',
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name *'),
                  validator: required,
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
                          );
                          if (d != null) setState(() => _dob = d);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date of birth *',
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
                          DropdownMenuItem(
                            value: 'Other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _gender = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone *'),
                        validator: required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _blood,
                        decoration: const InputDecoration(
                          labelText: 'Blood group',
                        ),
                        items: [
                          for (final b in _bloodGroups)
                            DropdownMenuItem(
                              value: b,
                              child: Text(b.isEmpty ? 'Unknown' : b),
                            ),
                        ],
                        onChanged: (v) => setState(() => _blood = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (for appointment reminders)',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty || v.contains('@')
                      ? null
                      : 'Enter a valid email',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _allergies,
                  decoration: const InputDecoration(
                    labelText: 'Known allergies',
                    helperText: 'Shown to doctors and pharmacists',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _insurerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Health insurance',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('None (self-pay)'),
                    ),
                    for (final i in context.read<HospitalStore>().insurers)
                      if (i.active || i.id == _insurerId)
                        DropdownMenuItem(value: i.id, child: Text(i.name)),
                  ],
                  onChanged: (v) => setState(() => _insurerId = v),
                ),
                if (_insurerId != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _policy,
                          decoration: const InputDecoration(
                            labelText: 'Policy / member no.',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event),
                          label: Text(
                            _policyExpiry == null
                                ? 'Valid until'
                                : 'Until ${fmtDate(_policyExpiry)}',
                          ),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate:
                                  _policyExpiry ??
                                  DateTime.now().add(const Duration(days: 365)),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) setState(() => _policyExpiry = d);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
