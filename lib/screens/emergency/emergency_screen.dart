import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../doctor/consultation_screen.dart';
import '../patient_detail_screen.dart';

Color triageColor(TriageLevel? l) => switch (l) {
  null => Colors.grey,
  TriageLevel.immediate => Colors.red,
  TriageLevel.veryUrgent => Colors.orange,
  TriageLevel.urgent => Colors.amber.shade700,
  TriageLevel.standard => Colors.green,
  TriageLevel.nonUrgent => Colors.blue,
};

/// The emergency department board: arrivals, triage, doctor and
/// disposition.
class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final board = store.emergencyBoard;
    final closed = store.emergencyClosedOn(DateTime.now());
    final now = DateTime.now();
    final overdue = board.where((v) => v.overdue(now)).length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const _ArrivalDialog(),
          ),
          icon: const Icon(Icons.add),
          label: const Text('New arrival'),
        ),
        body: Column(
          children: [
            TabBar(
              tabs: [
                Tab(
                  text:
                      'In department (${board.length})'
                      '${overdue > 0 ? ' · $overdue overdue' : ''}',
                ),
                Tab(text: 'Left today (${closed.length})'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  board.isEmpty
                      ? const EmptyState(
                          'No patients in the emergency department',
                          icon: Icons.emergency,
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          children: [
                            for (final v in board) _VisitCard(visit: v),
                          ],
                        ),
                  closed.isEmpty
                      ? const EmptyState('Nobody has left the department today')
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final v in closed) _VisitCard(visit: v),
                          ],
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit});

  final EmergencyVisit visit;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final v = visit;
    final user = store.currentUser!;
    final p = store.patientById(v.patientId);
    final now = DateTime.now();
    final color = triageColor(v.triageLevel);
    final clinical = {
      UserRole.admin,
      UserRole.doctor,
      UserRole.nurse,
    }.contains(user.role);
    final canTriage =
        clinical &&
        (v.status == EmergencyStatus.waitingTriage ||
            v.status == EmergencyStatus.waitingDoctor);
    final isDoctor = user.role == UserRole.doctor;
    final mine = v.doctorId == user.id;

    final obs = [
      if (v.temperature != null) 'T ${v.temperature}°C',
      if (v.pulse != null) 'HR ${v.pulse}',
      if (v.respRate != null) 'RR ${v.respRate}',
      if (v.systolic != null) 'BP ${v.systolic}/${v.diastolic}',
      if (v.spo2 != null) 'SpO₂ ${v.spo2}%',
      if (v.painScore != null) 'Pain ${v.painScore}/10',
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 8, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusChip(
                          v.triageLevel == null
                              ? 'Not triaged'
                              : '${v.triageLevel!.colour} · ${v.triageLevel!.label}',
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        if (v.overdue(now))
                          const StatusChip(
                            'OVERDUE',
                            color: Colors.red,
                            icon: Icons.timer_off,
                          ),
                        const Spacer(),
                        StatusChip(
                          v.outcome?.label ?? v.status.label,
                          color: v.isOpen ? Colors.blueGrey : Colors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PatientDetailScreen(patientId: v.patientId),
                        ),
                      ),
                      child: Text(
                        '${p?.name ?? 'Unknown'} · ${p?.mrn} · '
                        '${p?.age}y ${p?.gender}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text(v.complaint),
                    Text(
                      'Arrived ${fmtTime(v.arrivedAt)} (${v.arrivalMode}) · '
                      '${v.seenAt == null ? 'waiting' : 'seen after'} '
                      '${_duration(v.waited(now))}'
                      '${v.seeBy != null && v.seenAt == null ? ' · see by ${fmtTime(v.seeBy)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (obs.isNotEmpty) Text(obs.join(' · ')),
                    if (v.triageNotes.isNotEmpty)
                      Text('Triage: ${v.triageNotes}'),
                    if (v.doctorId != null)
                      Text('Doctor: ${store.userName(v.doctorId!)}'),
                    if (v.outcomeNotes.isNotEmpty)
                      Text('Outcome: ${v.outcomeNotes}'),
                    if (v.isOpen)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (canTriage)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.monitor_heart),
                                label: Text(
                                  v.triageLevel == null
                                      ? 'Triage'
                                      : 'Re-triage',
                                ),
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => _TriageDialog(visit: v),
                                ),
                              ),
                            if (isDoctor &&
                                (v.status != EmergencyStatus.beingSeen || mine))
                              FilledButton.icon(
                                icon: const Icon(Icons.medical_services),
                                label: Text(
                                  v.status == EmergencyStatus.beingSeen
                                      ? 'Open consultation'
                                      : 'See patient',
                                ),
                                onPressed: () async {
                                  final nav = Navigator.of(context);
                                  Consultation? c;
                                  final ok = await guarded(
                                    context,
                                    () async =>
                                        c = await store.seeEmergencyPatient(
                                          v.id,
                                          doctorId: user.id,
                                        ),
                                  );
                                  if (ok && c != null) {
                                    nav.push(
                                      MaterialPageRoute(
                                        builder: (_) => ConsultationScreen(
                                          consultationId: c!.id,
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            // Once a doctor has seen the patient, a doctor
                            // closes the visit (it completes the
                            // consultation).
                            if (clinical &&
                                (v.consultationId == null ||
                                    user.role != UserRole.nurse))
                              TextButton.icon(
                                icon: const Icon(Icons.logout),
                                label: const Text('Close visit'),
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => _CloseDialog(visit: v),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _duration(Duration d) => d.inHours > 0
      ? '${d.inHours} h ${d.inMinutes % 60} min'
      : '${d.inMinutes} min';
}

class _ArrivalDialog extends StatefulWidget {
  const _ArrivalDialog();

  @override
  State<_ArrivalDialog> createState() => _ArrivalDialogState();
}

class _ArrivalDialogState extends State<_ArrivalDialog> {
  Patient? _patient;
  bool _unknown = false;
  String _gender = 'Male';
  final _age = TextEditingController(text: '30');
  final _complaint = TextEditingController();
  String _mode = kArrivalModes.first;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    return AlertDialog(
      title: const Text('Emergency arrival'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _unknown,
                title: const Text('Identity not known'),
                subtitle: const Text(
                  'Register now; reception completes the record later',
                ),
                onChanged: (v) => setState(() => _unknown = v),
              ),
              if (_unknown)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _gender,
                        decoration: const InputDecoration(labelText: 'Sex'),
                        items: [
                          for (final g in ['Male', 'Female'])
                            DropdownMenuItem(value: g, child: Text(g)),
                        ],
                        onChanged: (g) => setState(() => _gender = g!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _age,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Estimated age',
                        ),
                      ),
                    ),
                  ],
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_search),
                  title: Text(_patient?.name ?? 'Select patient'),
                  subtitle: _patient == null
                      ? null
                      : Text('${_patient!.mrn} · ${_patient!.age}y'),
                  onTap: () async {
                    final p = await pickPatient(context, store);
                    if (p != null) setState(() => _patient = p);
                  },
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _complaint,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Presenting complaint',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: const InputDecoration(labelText: 'Arrived by'),
                items: [
                  for (final m in kArrivalModes)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (m) => setState(() => _mode = m!),
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
            final ok = await guarded(context, () async {
              if (_complaint.text.trim().isEmpty) {
                throw HospitalException('Enter the presenting complaint');
              }
              var p = _patient;
              if (_unknown) {
                p = await store.registerUnknownPatient(
                  gender: _gender,
                  estimatedAge: int.tryParse(_age.text) ?? 30,
                );
              }
              if (p == null) throw HospitalException('Select the patient');
              await store.registerEmergency(
                patientId: p.id,
                complaint: _complaint.text,
                arrivalMode: _mode,
              );
            }, success: 'Added to the emergency board for triage');
            if (ok) nav.pop();
          },
          child: const Text('Register'),
        ),
      ],
    );
  }
}

class _TriageDialog extends StatefulWidget {
  const _TriageDialog({required this.visit});

  final EmergencyVisit visit;

  @override
  State<_TriageDialog> createState() => _TriageDialogState();
}

class _TriageDialogState extends State<_TriageDialog> {
  late TriageLevel? _level = widget.visit.triageLevel;
  late final _temp = _c(widget.visit.temperature);
  late final _pulse = _c(widget.visit.pulse);
  late final _rr = _c(widget.visit.respRate);
  late final _sys = _c(widget.visit.systolic);
  late final _dia = _c(widget.visit.diastolic);
  late final _spo2 = _c(widget.visit.spo2);
  late final _pain = _c(widget.visit.painScore);
  late final _notes = TextEditingController(text: widget.visit.triageNotes);

  static TextEditingController _c(num? v) =>
      TextEditingController(text: v?.toString() ?? '');

  Widget _field(TextEditingController c, String label) => SizedBox(
    width: 110,
    child: TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, isDense: true),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Triage – ${context.read<HospitalStore>().patientName(widget.visit.patientId)}',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.visit.complaint),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _field(_temp, 'Temp °C'),
                  _field(_pulse, 'Pulse'),
                  _field(_rr, 'Resp rate'),
                  _field(_sys, 'BP systolic'),
                  _field(_dia, 'BP diastolic'),
                  _field(_spo2, 'SpO₂ %'),
                  _field(_pain, 'Pain 0–10'),
                ],
              ),
              const SizedBox(height: 12),
              Text('Category', style: Theme.of(context).textTheme.titleSmall),
              RadioGroup<TriageLevel>(
                groupValue: _level,
                onChanged: (v) => setState(() => _level = v),
                child: Column(
                  children: [
                    for (final l in TriageLevel.values)
                      RadioListTile<TriageLevel>(
                        dense: true,
                        value: l,
                        title: Text('${l.colour} – ${l.label}'),
                        subtitle: Text(
                          l.target == Duration.zero
                              ? 'Seen immediately'
                              : 'Seen within ${l.target.inMinutes} min',
                        ),
                        secondary: CircleAvatar(
                          radius: 8,
                          backgroundColor: triageColor(l),
                        ),
                      ),
                  ],
                ),
              ),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Triage notes'),
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
          onPressed: _level == null
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  int? i(TextEditingController c) =>
                      int.tryParse(c.text.trim());
                  final ok = await guarded(
                    context,
                    () => context.read<HospitalStore>().triageEmergency(
                      widget.visit.id,
                      level: _level!,
                      temperature: double.tryParse(_temp.text.trim()),
                      pulse: i(_pulse),
                      respRate: i(_rr),
                      systolic: i(_sys),
                      diastolic: i(_dia),
                      spo2: i(_spo2),
                      painScore: i(_pain),
                      notes: _notes.text,
                    ),
                    success: 'Triage recorded',
                  );
                  if (ok) nav.pop();
                },
          child: const Text('Save triage'),
        ),
      ],
    );
  }
}

class _CloseDialog extends StatefulWidget {
  const _CloseDialog({required this.visit});

  final EmergencyVisit visit;

  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  EmergencyOutcome? _outcome;
  String? _roomId;
  final _notes = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final seen = widget.visit.consultationId != null;
    final outcomes = [
      for (final o in EmergencyOutcome.values)
        if (seen
            ? o != EmergencyOutcome.leftWithoutBeingSeen
            : o == EmergencyOutcome.leftWithoutBeingSeen ||
                  o == EmergencyOutcome.died ||
                  o == EmergencyOutcome.referred)
          o,
    ];
    return AlertDialog(
      title: const Text('Close emergency visit'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<EmergencyOutcome>(
              initialValue: _outcome,
              decoration: const InputDecoration(labelText: 'Outcome'),
              items: [
                for (final o in outcomes)
                  DropdownMenuItem(value: o, child: Text(o.label)),
              ],
              onChanged: (o) => setState(() => _outcome = o),
            ),
            if (_outcome == EmergencyOutcome.admitted) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _roomId,
                decoration: const InputDecoration(labelText: 'Ward / room'),
                items: [
                  for (final r in store.rooms)
                    DropdownMenuItem(
                      value: r.id,
                      enabled: store.freeBeds(r.id) > 0,
                      child: Text(
                        '${r.name} – ${store.freeBeds(r.id)} free bed(s)',
                      ),
                    ),
                ],
                onChanged: (r) => setState(() => _roomId = r),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: seen
                    ? 'Diagnosis / outcome notes'
                    : 'Notes (e.g. where referred)',
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
          onPressed: _outcome == null
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  final ok = await guarded(
                    context,
                    () => store.closeEmergency(
                      widget.visit.id,
                      outcome: _outcome!,
                      notes: _notes.text,
                      roomId: _roomId,
                    ),
                    success: _outcome == EmergencyOutcome.admitted
                        ? 'Patient admitted'
                        : 'Visit closed',
                  );
                  if (ok) nav.pop();
                },
          child: const Text('Close visit'),
        ),
      ],
    );
  }
}
