import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

Color newsColor(News2Risk r) => switch (r) {
  News2Risk.low => Colors.green,
  News2Risk.lowMedium => Colors.amber.shade800,
  News2Risk.medium => Colors.deepOrange,
  News2Risk.high => Colors.red,
};

StatusChip newsChip(VitalsReading v) => StatusChip(
  'NEWS2 ${v.news2.score}${v.news2.complete ? '' : '+'}',
  color: newsColor(v.news2.risk),
  icon: v.news2.needsDoctor ? Icons.warning : Icons.monitor_heart,
);

/// Observations, medication chart and nursing notes for one admission.
class NursingChartScreen extends StatelessWidget {
  const NursingChartScreen({super.key, required this.admissionId});

  final String admissionId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final a = store.admissionById(admissionId);
    if (a == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState('Not found'));
    }
    final p = store.patientById(a.patientId);
    final latest = store.latestVitals(a.id);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Nursing chart – ${p?.name ?? ''}'),
          actions: [
            if (latest != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(child: newsChip(latest)),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Observations'),
              Tab(text: 'Medications'),
              Tab(text: 'Notes'),
            ],
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${p?.mrn ?? ''} · ${p?.age}y ${p?.gender}'),
                  Text(a.currentStay.roomName),
                  Text('Dr: ${store.userName(a.doctorId)}'),
                  if (a.reason.isNotEmpty) Text(a.reason),
                  if (!a.isActive)
                    StatusChip(
                      'Discharged ${fmtDate(a.dischargedAt)}',
                      color: Colors.grey,
                    ),
                  if (p != null && p.allergies.isNotEmpty)
                    StatusChip(
                      'Allergies: ${p.allergies}',
                      color: Colors.red,
                      icon: Icons.warning,
                    ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _Observations(admission: a),
                  _Medications(admission: a),
                  _Notes(admission: a),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _clinical(HospitalStore s) => {
  UserRole.admin,
  UserRole.doctor,
  UserRole.nurse,
}.contains(s.currentUser!.role);

class _Observations extends StatelessWidget {
  const _Observations({required this.admission});

  final Admission admission;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final list = store.vitalsFor(admission.id);
    String n(Object? v) => v?.toString() ?? '–';
    return Scaffold(
      floatingActionButton: admission.isActive && _clinical(store)
          ? FloatingActionButton.extended(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _VitalsDialog(admission: admission),
              ),
              icon: const Icon(Icons.add_chart),
              label: const Text('Record observations'),
            )
          : null,
      body: list.isEmpty
          ? const EmptyState('No observations yet', icon: Icons.monitor_heart)
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 18,
                    columns: const [
                      DataColumn(label: Text('Time')),
                      DataColumn(label: Text('NEWS2')),
                      DataColumn(label: Text('Temp °C'), numeric: true),
                      DataColumn(label: Text('Pulse'), numeric: true),
                      DataColumn(label: Text('RR'), numeric: true),
                      DataColumn(label: Text('BP')),
                      DataColumn(label: Text('SpO₂ %'), numeric: true),
                      DataColumn(label: Text('O₂')),
                      DataColumn(label: Text('ACVPU')),
                      DataColumn(label: Text('Pain'), numeric: true),
                      DataColumn(label: Text('Glucose'), numeric: true),
                      DataColumn(label: Text('By')),
                      DataColumn(label: Text('Notes')),
                    ],
                    rows: [
                      for (final v in list)
                        DataRow(
                          cells: [
                            DataCell(Text(fmtDateTime(v.takenAt))),
                            DataCell(newsChip(v)),
                            DataCell(Text(n(v.temperature))),
                            DataCell(Text(n(v.pulse))),
                            DataCell(Text(n(v.respRate))),
                            DataCell(
                              Text(
                                v.bloodPressure.isEmpty ? '–' : v.bloodPressure,
                              ),
                            ),
                            DataCell(Text(n(v.spo2))),
                            DataCell(Text(v.onOxygen ? 'Yes' : '')),
                            DataCell(Text(v.consciousness.label)),
                            DataCell(Text(n(v.painScore))),
                            DataCell(Text(n(v.bloodSugar))),
                            DataCell(
                              Text(
                                v.recordedBy == null
                                    ? ''
                                    : store.userName(v.recordedBy!),
                              ),
                            ),
                            DataCell(Text(v.notes)),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'NEWS2 response for the latest set: '
                  '${list.first.news2.risk.response}.',
                  style: TextStyle(color: newsColor(list.first.news2.risk)),
                ),
              ],
            ),
    );
  }
}

class _VitalsDialog extends StatefulWidget {
  const _VitalsDialog({required this.admission});

  final Admission admission;

  @override
  State<_VitalsDialog> createState() => _VitalsDialogState();
}

class _VitalsDialogState extends State<_VitalsDialog> {
  final _temp = TextEditingController();
  final _pulse = TextEditingController();
  final _rr = TextEditingController();
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _spo2 = TextEditingController();
  final _pain = TextEditingController();
  final _sugar = TextEditingController();
  final _notes = TextEditingController();
  bool _o2 = false;
  Consciousness _c = Consciousness.alert;

  VitalsReading get _draft => VitalsReading(
    id: '',
    admissionId: '',
    patientId: '',
    takenAt: DateTime.now(),
    temperature: double.tryParse(_temp.text),
    pulse: int.tryParse(_pulse.text),
    respRate: int.tryParse(_rr.text),
    systolic: int.tryParse(_sys.text),
    spo2: int.tryParse(_spo2.text),
    onOxygen: _o2,
    consciousness: _c,
  );

  Widget _field(
    TextEditingController c,
    String label, {
    bool decimal = false,
  }) => SizedBox(
    width: 130,
    child: TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (_) => setState(() {}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final news = _draft.news2;
    return AlertDialog(
      title: const Text('Record observations'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _field(_temp, 'Temp °C', decimal: true),
                  _field(_pulse, 'Pulse /min'),
                  _field(_rr, 'Resp. rate /min'),
                  _field(_sys, 'Systolic BP'),
                  _field(_dia, 'Diastolic BP'),
                  _field(_spo2, 'SpO₂ %'),
                  _field(_pain, 'Pain 0–10'),
                  _field(_sugar, 'Glucose mmol/L', decimal: true),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('On supplemental oxygen'),
                value: _o2,
                onChanged: (v) => setState(() => _o2 = v),
              ),
              DropdownButtonFormField<Consciousness>(
                initialValue: _c,
                decoration: const InputDecoration(
                  labelText: 'Consciousness (ACVPU)',
                ),
                items: [
                  for (final c in Consciousness.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _c = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: newsColor(news.risk).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'NEWS2 ${news.score}${news.complete ? '' : ' (incomplete)'} – '
                  '${news.risk.label} risk. ${news.risk.response}.',
                  style: TextStyle(
                    color: newsColor(news.risk),
                    fontWeight: FontWeight.w600,
                  ),
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
            if (await guarded(
              context,
              () => store.recordVitals(
                admissionId: widget.admission.id,
                temperature: double.tryParse(_temp.text),
                pulse: int.tryParse(_pulse.text),
                respRate: int.tryParse(_rr.text),
                systolic: int.tryParse(_sys.text),
                diastolic: int.tryParse(_dia.text),
                spo2: int.tryParse(_spo2.text),
                onOxygen: _o2,
                consciousness: _c,
                painScore: int.tryParse(_pain.text),
                bloodSugar: double.tryParse(_sugar.text),
                notes: _notes.text,
              ),
              success: news.needsDoctor
                  ? 'Saved – the doctor has been alerted'
                  : 'Observations saved',
            )) {
              nav.pop();
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _Medications extends StatefulWidget {
  const _Medications({required this.admission});

  final Admission admission;

  @override
  State<_Medications> createState() => _MedicationsState();
}

class _MedicationsState extends State<_Medications> {
  DateTime _day = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final a = widget.admission;
    final role = store.currentUser!.role;
    final canOrder = role == UserRole.doctor || role == UserRole.admin;
    final canGive = _clinical(store) && a.isActive;
    final now = DateTime.now();
    final slots = store.marFor(a.id, _day);
    final orders = store.medicationOrdersFor(a.id);
    final prn = orders.where((o) => o.isPrn && o.isActive).toList();

    return Scaffold(
      floatingActionButton: canOrder && a.isActive
          ? FloatingActionButton.extended(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _OrderDialog(admission: a),
              ),
              icon: const Icon(Icons.medication),
              label: const Text('Order medication'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => _day = _day.subtract(const Duration(days: 1)),
                ),
              ),
              Text(
                fmtDate(_day),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () =>
                    setState(() => _day = _day.add(const Duration(days: 1))),
              ),
              TextButton(
                onPressed: () => setState(() => _day = DateTime.now()),
                child: const Text('Today'),
              ),
            ],
          ),
          SectionCard(
            title: 'Scheduled doses',
            icon: Icons.schedule,
            child: slots.isEmpty
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No scheduled doses on this day.'),
                  )
                : Column(
                    children: [
                      for (final sl in slots)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Text(
                            fmtTime(sl.time),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          title: Text(
                            '${sl.order.medicineName} ${sl.order.dose} '
                            '${sl.order.route}',
                          ),
                          subtitle: sl.dose == null
                              ? (sl.order.instructions.isEmpty
                                    ? null
                                    : Text(sl.order.instructions))
                              : Text(
                                  '${sl.dose!.status.label} '
                                  '${fmtTime(sl.dose!.recordedAt)} by '
                                  '${sl.dose!.recordedBy == null ? '' : store.userName(sl.dose!.recordedBy!)}'
                                  '${sl.dose!.notes.isEmpty ? '' : ' – ${sl.dose!.notes}'}',
                                ),
                          trailing: sl.dose != null
                              ? StatusChip(
                                  sl.dose!.status.label,
                                  color: sl.dose!.status == DoseStatus.given
                                      ? Colors.green
                                      : Colors.red,
                                )
                              : Wrap(
                                  spacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (sl.isOverdue(now))
                                      const StatusChip(
                                        'Overdue',
                                        color: Colors.red,
                                      )
                                    else if (sl.isDue(now))
                                      const StatusChip(
                                        'Due',
                                        color: Colors.orange,
                                      ),
                                    if (canGive) ...[
                                      FilledButton(
                                        onPressed: () => guarded(
                                          context,
                                          () => store.recordDose(
                                            orderId: sl.order.id,
                                            scheduledFor: sl.time,
                                            status: DoseStatus.given,
                                          ),
                                          success: 'Dose recorded as given',
                                        ),
                                        child: const Text('Given'),
                                      ),
                                      TextButton(
                                        onPressed: () => _notGiven(
                                          context,
                                          sl.order,
                                          sl.time,
                                        ),
                                        child: const Text('Not given'),
                                      ),
                                    ],
                                  ],
                                ),
                        ),
                    ],
                  ),
          ),
          if (prn.isNotEmpty)
            SectionCard(
              title: 'As needed (PRN)',
              icon: Icons.medication_liquid,
              child: Column(
                children: [
                  for (final o in prn)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${o.medicineName} ${o.dose} ${o.route}'),
                      subtitle: Text(
                        [
                          if (o.instructions.isNotEmpty) o.instructions,
                          switch (store.dosesFor(o.id)) {
                            [final last, ...] =>
                              'Last given ${fmtDateTime(last.recordedAt)}',
                            _ => 'Not given yet',
                          },
                        ].join(' · '),
                      ),
                      trailing: canGive
                          ? FilledButton.tonal(
                              onPressed: () => guarded(
                                context,
                                () => store.recordDose(
                                  orderId: o.id,
                                  status: DoseStatus.given,
                                ),
                                success: 'PRN dose recorded',
                              ),
                              child: const Text('Give dose'),
                            )
                          : null,
                    ),
                ],
              ),
            ),
          SectionCard(
            title: 'Medication orders',
            icon: Icons.list_alt,
            child: orders.isEmpty
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No ward medications ordered.'),
                  )
                : Column(
                    children: [
                      for (final o in orders)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${o.medicineName} ${o.dose} ${o.route} – ${o.frequency}',
                            style: TextStyle(
                              decoration: o.isActive
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                          subtitle: Text(
                            'Ordered ${fmtDateTime(o.startAt)} by '
                            '${o.orderedBy == null ? '' : store.userName(o.orderedBy!)}'
                            '${o.stoppedAt == null ? '' : ' · stopped ${fmtDateTime(o.stoppedAt)}'}',
                          ),
                          trailing: canOrder && o.isActive && a.isActive
                              ? TextButton(
                                  onPressed: () => guarded(
                                    context,
                                    () => store.stopMedicationOrder(o.id),
                                    success: 'Medication stopped',
                                  ),
                                  child: const Text('Stop'),
                                )
                              : null,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _notGiven(
    BuildContext context,
    MedicationOrder o,
    DateTime slot,
  ) async {
    final store = context.read<HospitalStore>();
    var status = DoseStatus.held;
    final reason = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${o.medicineName} at ${fmtTime(slot)} not given'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<DoseStatus>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final st in DoseStatus.values.where(
                    (x) => x != DoseStatus.given,
                  ))
                    DropdownMenuItem(value: st, child: Text(st.label)),
                ],
                onChanged: (v) => status = v!,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
            ],
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
                () => store.recordDose(
                  orderId: o.id,
                  scheduledFor: slot,
                  status: status,
                  notes: reason.text,
                ),
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
}

class _OrderDialog extends StatefulWidget {
  const _OrderDialog({required this.admission});

  final Admission admission;

  @override
  State<_OrderDialog> createState() => _OrderDialogState();
}

class _OrderDialogState extends State<_OrderDialog> {
  Medicine? _medicine;
  final _other = TextEditingController();
  final _dose = TextEditingController();
  final _instructions = TextEditingController();
  String _route = kRoutes.first;
  String _frequency = kMedicationSchedules.keys.first;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final meds = [...store.medicines]..sort((a, b) => a.name.compareTo(b.name));
    final times = kMedicationSchedules[_frequency]!;
    return AlertDialog(
      title: const Text('Order ward medication'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Medicine?>(
                initialValue: _medicine,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Medicine'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Other (type below)'),
                  ),
                  for (final m in meds)
                    DropdownMenuItem(value: m, child: Text(m.displayName)),
                ],
                onChanged: (v) => setState(() => _medicine = v),
              ),
              if (_medicine == null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _other,
                  decoration: const InputDecoration(labelText: 'Medicine name'),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dose,
                      decoration: const InputDecoration(labelText: 'Dose'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _route,
                      decoration: const InputDecoration(labelText: 'Route'),
                      items: [
                        for (final r in kRoutes)
                          DropdownMenuItem(value: r, child: Text(r)),
                      ],
                      onChanged: (v) => setState(() => _route = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: InputDecoration(
                  labelText: 'Frequency',
                  helperText: times.isEmpty
                      ? 'Given when needed'
                      : 'Given at ${times.join(', ')}',
                ),
                items: [
                  for (final f in kMedicationSchedules.keys)
                    DropdownMenuItem(value: f, child: Text(f)),
                ],
                onChanged: (v) => setState(() => _frequency = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _instructions,
                decoration: const InputDecoration(
                  labelText: 'Instructions (e.g. if pain > 4, max 4 g/day)',
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
            if (await guarded(
              context,
              () => store.addMedicationOrder(
                admissionId: widget.admission.id,
                medicineId: _medicine?.id,
                medicineName: _medicine?.displayName ?? _other.text,
                dose: _dose.text,
                route: _route,
                frequency: _frequency,
                instructions: _instructions.text,
              ),
              success: 'Medication ordered; nurses notified',
            )) {
              nav.pop();
            }
          },
          child: const Text('Order'),
        ),
      ],
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes({required this.admission});

  final Admission admission;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final notes = store.notesFor(admission.id);
    return Scaffold(
      floatingActionButton: admission.isActive && _clinical(store)
          ? FloatingActionButton.extended(
              onPressed: () => _add(context),
              icon: const Icon(Icons.note_add),
              label: const Text('Add note'),
            )
          : null,
      body: notes.isEmpty
          ? const EmptyState('No nursing notes yet', icon: Icons.notes)
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                for (final n in notes)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.notes),
                      title: Text(n.text),
                      subtitle: Text(
                        '${n.category} · ${fmtDateTime(n.at)} · '
                        '${n.author == null ? '' : store.userName(n.author!)}',
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final store = context.read<HospitalStore>();
    var category = kNoteCategories.first;
    final text = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nursing note'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in kNoteCategories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => category = v!,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
            ],
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
                () => store.addNursingNote(
                  admissionId: admission.id,
                  category: category,
                  text: text.text,
                ),
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
}
