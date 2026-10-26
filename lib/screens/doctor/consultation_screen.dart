import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';

/// The doctor's workspace for a visit: clinical notes, lab requests and
/// prescriptions. Lab orders go straight to the laboratory queue and
/// prescriptions straight to the pharmacy queue.
class ConsultationScreen extends StatefulWidget {
  const ConsultationScreen({super.key, required this.consultationId});

  final String consultationId;

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  late final Consultation _c;
  late final _complaints = TextEditingController(text: _c.complaints);
  late final _diagnosis = TextEditingController(text: _c.diagnosis);
  late final _notes = TextEditingController(text: _c.notes);
  late final _temp = TextEditingController(text: _c.vitals.temperature);
  late final _bp = TextEditingController(text: _c.vitals.bloodPressure);
  late final _pulse = TextEditingController(text: _c.vitals.pulse);
  late final _spo2 = TextEditingController(text: _c.vitals.spo2);
  late final _weight = TextEditingController(text: _c.vitals.weight);

  @override
  void initState() {
    super.initState();
    _c = context.read<HospitalStore>().consultationById(widget.consultationId)!;
  }

  void _applyFields() {
    _c
      ..complaints = _complaints.text.trim()
      ..diagnosis = _diagnosis.text.trim()
      ..notes = _notes.text.trim()
      ..vitals = Vitals(
        temperature: _temp.text.trim(),
        bloodPressure: _bp.text.trim(),
        pulse: _pulse.text.trim(),
        spo2: _spo2.text.trim(),
        weight: _weight.text.trim(),
      );
  }

  Future<void> _save() async {
    _applyFields();
    await guarded(context, () => context.read<HospitalStore>().saveConsultation(_c),
        success: 'Consultation saved');
  }

  Future<void> _complete() async {
    _applyFields();
    final store = context.read<HospitalStore>();
    if (_c.diagnosis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a diagnosis before completing the visit')));
      return;
    }
    DateTime? followUp;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Complete consultation'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Lab orders and prescriptions already sent stay '
                'active in their departments.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_repeat),
              label: Text(followUp == null
                  ? 'Schedule follow-up (optional)'
                  : 'Follow-up: ${fmtDate(followUp)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2100),
                );
                if (d != null) {
                  setState(
                      () => followUp = DateTime(d.year, d.month, d.day, 10));
                }
              },
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Complete')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    _c.followUpDate = followUp;
    final nav = Navigator.of(context);
    final ok = await guarded(context, () => store.completeConsultation(_c.id),
        success: 'Visit completed');
    if (ok) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final patient = store.patientById(_c.patientId)!;
    final editable = _c.isOpen && store.currentUser?.id == _c.doctorId;
    final labs = store.labOrdersFor(consultationId: _c.id);
    final rxs = store.prescriptionsFor(consultationId: _c.id);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final clinical = SectionCard(
      title: 'Clinical notes',
      icon: Icons.edit_note,
      child: Column(children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _vital(_temp, 'Temp °C', editable),
          _vital(_bp, 'BP mmHg', editable),
          _vital(_pulse, 'Pulse /min', editable),
          _vital(_spo2, 'SpO₂ %', editable),
          _vital(_weight, 'Weight kg', editable),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _complaints,
          enabled: editable,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Presenting complaints'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _diagnosis,
          enabled: editable,
          decoration: const InputDecoration(labelText: 'Diagnosis'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          enabled: editable,
          maxLines: 4,
          decoration:
              const InputDecoration(labelText: 'Examination / plan notes'),
        ),
      ]),
    );

    final labCard = SectionCard(
      title: 'Laboratory',
      icon: Icons.biotech,
      trailing: editable
          ? FilledButton.tonalIcon(
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _OrderLabDialog(consultation: _c)),
              icon: const Icon(Icons.add),
              label: const Text('Order tests'),
            )
          : null,
      child: labs.isEmpty
          ? const Text('No tests ordered for this visit.')
          : Column(children: [
              for (final o in labs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    o.urgent ? Icons.priority_high : Icons.science_outlined,
                    color: o.urgent ? Colors.red : null,
                  ),
                  title: Text(o.testName),
                  subtitle: o.status == LabOrderStatus.completed
                      ? Text(
                          '${o.result}'
                          '${o.resultRemarks.isEmpty ? '' : ' · ${o.resultRemarks}'}'
                          '\nRef: ${store.labTestById(o.testId)?.referenceRange ?? '—'}',
                          style: TextStyle(
                              color: o.abnormal ? Colors.red : null,
                              fontWeight: FontWeight.w600),
                        )
                      : Text('Ordered ${fmtTime(o.orderedAt)}'),
                  isThreeLine: o.status == LabOrderStatus.completed,
                  trailing: Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip.lab(o),
                      if (o.status == LabOrderStatus.completed &&
                          !o.reviewedByDoctor &&
                          store.currentUser?.id == o.doctorId)
                        IconButton(
                          tooltip: 'Mark reviewed',
                          icon: const Icon(Icons.done),
                          onPressed: () => store.markResultReviewed(o.id),
                        ),
                    ],
                  ),
                ),
            ]),
    );

    final rxCard = SectionCard(
      title: 'Prescriptions',
      icon: Icons.medication,
      trailing: editable
          ? FilledButton.tonalIcon(
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) =>
                      _PrescribeDialog(consultation: _c, patient: patient)),
              icon: const Icon(Icons.add),
              label: const Text('Prescribe'),
            )
          : null,
      child: rxs.isEmpty
          ? const Text('No medicines prescribed for this visit.')
          : Column(children: [
              for (final rx in rxs) ...[
                Row(children: [
                  Text(fmtTime(rx.createdAt),
                      style: Theme.of(context).textTheme.labelMedium),
                  const Spacer(),
                  StatusChip.prescription(rx.status),
                  if (editable && rx.status == PrescriptionStatus.pending)
                    IconButton(
                      tooltip: 'Cancel prescription',
                      icon: const Icon(Icons.close),
                      onPressed: () => guarded(
                          context, () => store.cancelPrescription(rx.id)),
                    ),
                ]),
                for (final i in rx.items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(i.medicineName),
                    subtitle: Text('${i.dosage} · ${i.frequency} · '
                        '${i.durationDays} days · qty ${i.quantity}'
                        '${i.instructions.isEmpty ? '' : ' · ${i.instructions}'}'),
                  ),
                const Divider(),
              ],
            ]),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Consultation – ${patient.name}'),
        actions: [
          IconButton(
            tooltip: 'Full medical record',
            icon: const Icon(Icons.folder_shared),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        PatientDetailScreen(patientId: patient.id))),
          ),
          if (editable) ...[
            TextButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Save')),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                  onPressed: _complete,
                  icon: const Icon(Icons.check),
                  label: const Text('Complete')),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${patient.mrn} · ${patient.age}y ${patient.gender} · '
              'Blood ${patient.bloodGroup.isEmpty ? '—' : patient.bloodGroup}'),
          if (patient.allergies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: StatusChip('Allergies: ${patient.allergies}',
                  color: Colors.red, icon: Icons.warning),
            ),
          if (!_c.isOpen)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: StatusChip('Completed ${fmtDateTime(_c.completedAt)}',
                  color: Colors.green),
            ),
          const SizedBox(height: 12),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: clinical),
              const SizedBox(width: 16),
              Expanded(child: Column(children: [labCard, rxCard])),
            ])
          else ...[
            clinical,
            labCard,
            rxCard,
          ],
        ],
      ),
    );
  }

  Widget _vital(TextEditingController c, String label, bool enabled) =>
      SizedBox(
        width: 120,
        child: TextField(
          controller: c,
          enabled: enabled,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );
}

class _OrderLabDialog extends StatefulWidget {
  const _OrderLabDialog({required this.consultation});

  final Consultation consultation;

  @override
  State<_OrderLabDialog> createState() => _OrderLabDialogState();
}

class _OrderLabDialogState extends State<_OrderLabDialog> {
  final _selected = <String>{};
  bool _urgent = false;
  final _notes = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final byCategory = <String, List<LabTest>>{};
    for (final t in store.labTests) {
      byCategory.putIfAbsent(t.category, () => []).add(t);
    }
    final total = store.labTests
        .where((t) => _selected.contains(t.id))
        .fold<double>(0, (s, t) => s + t.price);

    return AlertDialog(
      title: const Text('Order laboratory tests'),
      content: SizedBox(
        width: 480,
        height: 520,
        child: Column(children: [
          Expanded(
            child: ListView(children: [
              for (final entry in byCategory.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(entry.key,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final t in entry.value)
                  CheckboxListTile(
                    dense: true,
                    value: _selected.contains(t.id),
                    title: Text(t.name),
                    subtitle: Text('${t.sampleType} · ${t.referenceRange}'),
                    secondary: Text(money(t.price)),
                    onChanged: (v) => setState(() =>
                        v! ? _selected.add(t.id) : _selected.remove(t.id)),
                  ),
              ],
            ]),
          ),
          SwitchListTile(
            value: _urgent,
            title: const Text('Urgent'),
            onChanged: (v) => setState(() => _urgent = v),
          ),
          TextField(
            controller: _notes,
            decoration:
                const InputDecoration(labelText: 'Clinical notes for lab'),
          ),
        ]),
      ),
      actions: [
        Text('Total ${money(total)}'),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  final ok = await guarded(
                      context,
                      () => store.orderLabTests(
                            consultationId: widget.consultation.id,
                            testIds: _selected.toList(),
                            urgent: _urgent,
                            clinicalNotes: _notes.text.trim(),
                          ),
                      success: 'Sent ${_selected.length} test(s) to the lab');
                  if (ok) nav.pop();
                },
          child: const Text('Send to lab'),
        ),
      ],
    );
  }
}

class _DraftItem {
  Medicine? medicine;
  final dosage = TextEditingController(text: '1 tablet');
  String frequency = 'Twice daily';
  final days = TextEditingController(text: '5');
  final instructions = TextEditingController();
  final qty = TextEditingController();
}

const _frequencies = {
  'Once daily': 1,
  'Twice daily': 2,
  'Three times daily': 3,
  'Four times daily': 4,
  'At night': 1,
  'As needed': 1,
};

class _PrescribeDialog extends StatefulWidget {
  const _PrescribeDialog({required this.consultation, required this.patient});

  final Consultation consultation;
  final Patient patient;

  @override
  State<_PrescribeDialog> createState() => _PrescribeDialogState();
}

class _PrescribeDialogState extends State<_PrescribeDialog> {
  final _items = [_DraftItem()];

  void _autoQty(_DraftItem d) {
    final days = int.tryParse(d.days.text) ?? 0;
    final perDose =
        int.tryParse(RegExp(r'\d+').firstMatch(d.dosage.text)?[0] ?? '1') ?? 1;
    d.qty.text = '${days * (_frequencies[d.frequency] ?? 1) * perDose}';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final meds = [...store.medicines]..sort((a, b) => a.name.compareTo(b.name));

    return AlertDialog(
      title: const Text('Prescribe medicines'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.patient.allergies.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StatusChip('Allergies: ${widget.patient.allergies}',
                    color: Colors.red, icon: Icons.warning),
              ),
            for (var idx = 0; idx < _items.length; idx++)
              _itemEditor(meds, _items[idx], idx),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _items.add(_DraftItem())),
                icon: const Icon(Icons.add),
                label: const Text('Add another medicine'),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            final ok = await guarded(context, () async {
              final items = <PrescriptionItem>[];
              for (final d in _items) {
                if (d.medicine == null) {
                  throw HospitalException('Select a medicine for every row');
                }
                final qty = int.tryParse(d.qty.text) ?? 0;
                if (qty <= 0) {
                  throw HospitalException(
                      '${d.medicine!.name}: quantity must be positive');
                }
                items.add(PrescriptionItem(
                  medicineId: d.medicine!.id,
                  medicineName: d.medicine!.displayName,
                  dosage: d.dosage.text.trim(),
                  frequency: d.frequency,
                  durationDays: int.tryParse(d.days.text) ?? 0,
                  quantity: qty,
                  instructions: d.instructions.text.trim(),
                ));
              }
              await store.prescribe(
                  consultationId: widget.consultation.id, items: items);
            }, success: 'Prescription sent to pharmacy');
            if (ok) nav.pop();
          },
          child: const Text('Send to pharmacy'),
        ),
      ],
    );
  }

  Widget _itemEditor(List<Medicine> meds, _DraftItem d, int idx) {
    final m = d.medicine;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<Medicine>(
                initialValue: m,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Medicine'),
                items: [
                  for (final med in meds)
                    DropdownMenuItem(
                      value: med,
                      child: Text(
                        '${med.displayName} · stock ${med.stock}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: med.stock == 0 || med.isExpired
                                ? Colors.red
                                : null),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  d.medicine = v;
                  d.dosage.text = switch (v?.form) {
                    'Syrup' => '5 ml',
                    'Capsule' => '1 capsule',
                    'Injection' => '1 vial',
                    'Inhaler' => '2 puffs',
                    _ => '1 tablet',
                  };
                  _autoQty(d);
                }),
              ),
            ),
            if (_items.length > 1)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => _items.removeAt(idx)),
              ),
          ]),
          if (m != null && (m.stock == 0 || m.isExpired))
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Out of stock or expired in pharmacy',
                  style: TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: d.dosage,
                decoration: const InputDecoration(labelText: 'Dose'),
                onChanged: (_) => setState(() => _autoQty(d)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: d.frequency,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: [
                  for (final f in _frequencies.keys)
                    DropdownMenuItem(value: f, child: Text(f)),
                ],
                onChanged: (v) => setState(() {
                  d.frequency = v!;
                  _autoQty(d);
                }),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: d.days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Days'),
                onChanged: (_) => setState(() => _autoQty(d)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: d.qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: d.instructions,
            decoration: const InputDecoration(
                labelText: 'Instructions (e.g. after food)'),
          ),
        ]),
      ),
    );
  }
}
