import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';

/// Operation theatre schedule, surgery workflow and theatre charges.
class TheatreScreen extends StatefulWidget {
  const TheatreScreen({super.key});

  @override
  State<TheatreScreen> createState() => _TheatreScreenState();
}

class _TheatreScreenState extends State<TheatreScreen> {
  DateTime _day = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final todays = store.surgeriesOn(_day);
    final upcoming =
        store.surgeries
            .where(
              (s) =>
                  s.status == SurgeryStatus.scheduled ||
                  s.status == SurgeryStatus.inProgress,
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final canSchedule = store.currentUser!.role != UserRole.nurse;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        floatingActionButton: canSchedule
            ? FloatingActionButton.extended(
                onPressed: () => _schedule(context),
                icon: const Icon(Icons.add),
                label: const Text('Schedule surgery'),
              )
            : null,
        body: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Day schedule'),
                Tab(text: 'Upcoming'),
                Tab(text: 'Theatres'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => setState(
                              () =>
                                  _day = _day.subtract(const Duration(days: 1)),
                            ),
                          ),
                          Text(
                            fmtDate(_day),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => setState(
                              () => _day = _day.add(const Duration(days: 1)),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => _day = DateTime.now()),
                            child: const Text('Today'),
                          ),
                        ],
                      ),
                      for (final t in store.theatres)
                        SectionCard(
                          title: t.name,
                          icon: Icons.meeting_room,
                          trailing: Text('${money(t.hourlyRate)}/h'),
                          child: Column(
                            children: [
                              if (!todays.any((s) => s.theatreId == t.id))
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('No surgeries booked'),
                                ),
                              for (final s in todays.where(
                                (s) => s.theatreId == t.id,
                              ))
                                _SurgeryTile(surgery: s),
                            ],
                          ),
                        ),
                    ],
                  ),
                  upcoming.isEmpty
                      ? const EmptyState(
                          'No surgeries scheduled',
                          icon: Icons.healing,
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          children: [
                            for (final s in upcoming)
                              Card(
                                child: _SurgeryTile(surgery: s, showDate: true),
                              ),
                          ],
                        ),
                  const _Theatres(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _schedule(BuildContext context) async {
    final store = context.read<HospitalStore>();
    final patient = await pickPatient(context, store);
    if (patient == null || !context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => _ScheduleDialog(patient: patient, day: _day),
    );
  }
}

class _SurgeryTile extends StatelessWidget {
  const _SurgeryTile({required this.surgery, this.showDate = false});

  final Surgery surgery;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final s = surgery;
    final admission = s.admissionId == null
        ? null
        : store.admissionById(s.admissionId!);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: CircleAvatar(
        child: Text(
          fmtTime(s.scheduledAt),
          style: const TextStyle(fontSize: 11),
        ),
      ),
      title: Text('${s.procedure} – ${store.patientName(s.patientId)}'),
      subtitle: Text(
        [
          if (showDate) fmtDate(s.scheduledAt),
          store.theatreById(s.theatreId)?.name ?? '',
          'Surgeon ${store.userName(s.surgeonId)}',
          if (s.anaesthetist.isNotEmpty) 'Anaesthetist ${s.anaesthetist}',
          '${s.estimatedMinutes} min',
          admission == null
              ? 'Day case'
              : 'Inpatient (${admission.currentStay.roomName})',
        ].join(' · '),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PatientDetailScreen(patientId: s.patientId),
        ),
      ),
      trailing: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusChip(
            s.status.label,
            color: switch (s.status) {
              SurgeryStatus.scheduled => Colors.blueGrey,
              SurgeryStatus.inProgress => Colors.orange,
              SurgeryStatus.completed => Colors.green,
              SurgeryStatus.cancelled => Colors.grey,
            },
          ),
          if (s.status == SurgeryStatus.scheduled) ...[
            IconButton(
              tooltip: 'Start',
              icon: const Icon(Icons.play_arrow, color: Colors.green),
              onPressed: () => guarded(
                context,
                () => store.startSurgery(s.id),
                success: 'Surgery started',
              ),
            ),
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
              onPressed: () =>
                  guarded(context, () => store.cancelSurgery(s.id)),
            ),
          ],
          if (s.status == SurgeryStatus.inProgress)
            FilledButton(
              onPressed: () => _complete(context, s),
              child: const Text('Complete'),
            ),
        ],
      ),
    );
  }

  Future<void> _complete(BuildContext context, Surgery s) async {
    final store = context.read<HospitalStore>();
    final consumables = TextEditingController(text: '0');
    final notes = TextEditingController(text: s.notes);
    final theatre = store.theatreById(s.theatreId);
    final minutes = DateTime.now().difference(s.startedAt!).inMinutes;
    final hours = (minutes / 60).ceil().clamp(1, 1 << 20);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Complete: ${s.procedure}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfoRow('Theatre time', '$minutes min → $hours h billed'),
              InfoRow(
                'Theatre charge',
                money(hours * (theatre?.hourlyRate ?? 0)),
              ),
              InfoRow('Surgeon fee', money(s.surgeonFee)),
              InfoRow('Anaesthesia fee', money(s.anaesthesiaFee)),
              const SizedBox(height: 8),
              TextField(
                controller: consumables,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Consumables (sutures, implants, drapes…)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Operative notes'),
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
                () => store.completeSurgery(
                  s.id,
                  consumablesCost: double.tryParse(consumables.text) ?? 0,
                  notes: notes.text,
                ),
                success: 'Surgery completed; charges added to the bill',
              )) {
                nav.pop();
              }
            },
            child: const Text('Complete & bill'),
          ),
        ],
      ),
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.patient, required this.day});

  final Patient patient;
  final DateTime day;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  final _procedure = TextEditingController();
  final _anaesthetist = TextEditingController();
  final _minutes = TextEditingController(text: '60');
  final _surgeonFee = TextEditingController(text: '0');
  final _anaesthesiaFee = TextEditingController(text: '0');
  final _notes = TextEditingController();
  String? _surgeonId;
  String? _theatreId;
  late DateTime _date = widget.day;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    final store = context.read<HospitalStore>();
    final me = store.currentUser!;
    if (me.role == UserRole.doctor) _surgeonId = me.id;
    _theatreId = store.theatres.firstOrNull?.id;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final admission = store.activeAdmissionFor(widget.patient.id);
    Widget field(
      TextEditingController c,
      String label, {
      bool number = false,
    }) => TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : null,
      decoration: InputDecoration(labelText: label),
    );
    return AlertDialog(
      title: Text('Schedule surgery: ${widget.patient.name}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  admission == null
                      ? 'Not admitted: billed as a day case'
                      : 'Inpatient in ${admission.currentStay.roomName}: '
                            'billed on the admission',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              field(_procedure, 'Procedure'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _surgeonId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Surgeon'),
                      items: [
                        for (final d in store.doctors)
                          DropdownMenuItem(value: d.id, child: Text(d.name)),
                      ],
                      onChanged: (v) => setState(() => _surgeonId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _theatreId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Theatre'),
                      items: [
                        for (final t in store.theatres)
                          DropdownMenuItem(value: t.id, child: Text(t.name)),
                      ],
                      onChanged: (v) => setState(() => _theatreId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(fmtDate(_date)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => _date = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule),
                      label: Text(_time.format(context)),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _time,
                        );
                        if (t != null) setState(() => _time = t);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: field(_minutes, 'Minutes', number: true)),
                ],
              ),
              const SizedBox(height: 12),
              field(_anaesthetist, 'Anaesthetist'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: field(_surgeonFee, 'Surgeon fee', number: true),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: field(
                      _anaesthesiaFee,
                      'Anaesthesia fee',
                      number: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              field(_notes, 'Notes (consent, fasting, blood…)'),
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
          onPressed: _surgeonId == null || _theatreId == null
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  if (await guarded(
                    context,
                    () => store.scheduleSurgery(
                      patientId: widget.patient.id,
                      surgeonId: _surgeonId!,
                      theatreId: _theatreId!,
                      procedure: _procedure.text,
                      scheduledAt: DateTime(
                        _date.year,
                        _date.month,
                        _date.day,
                        _time.hour,
                        _time.minute,
                      ),
                      estimatedMinutes: int.tryParse(_minutes.text) ?? 0,
                      anaesthetist: _anaesthetist.text,
                      surgeonFee: double.tryParse(_surgeonFee.text) ?? 0,
                      anaesthesiaFee:
                          double.tryParse(_anaesthesiaFee.text) ?? 0,
                      notes: _notes.text,
                    ),
                    success: 'Surgery scheduled',
                  )) {
                    nav.pop();
                  }
                },
          child: const Text('Schedule'),
        ),
      ],
    );
  }
}

class _Theatres extends StatelessWidget {
  const _Theatres();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final isAdmin = store.currentUser!.role == UserRole.admin;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        for (final t in store.theatres)
          ListTile(
            leading: const Icon(Icons.meeting_room),
            title: Text(t.name),
            subtitle: Text(
              '${money(t.hourlyRate)} per started hour (1 h minimum)',
            ),
            trailing: isAdmin ? const Icon(Icons.edit) : null,
            onTap: isAdmin ? () => _edit(context, t) : null,
          ),
        if (isAdmin)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add theatre'),
              onPressed: () => _edit(context, null),
            ),
          ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, OperationTheatre? existing) async {
    final store = context.read<HospitalStore>();
    final name = TextEditingController(text: existing?.name);
    final rate = TextEditingController(
      text: existing?.hourlyRate.toStringAsFixed(2),
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add theatre' : 'Edit ${existing.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rate,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hourly rate'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final ok = await guarded(ctx, () async {
                final r = double.tryParse(rate.text);
                if (name.text.trim().isEmpty || r == null) {
                  throw HospitalException('Enter a name and rate');
                }
                final t =
                    (existing == null
                        ? null
                        : store.theatreById(existing.id)) ??
                    OperationTheatre(
                      id: store.newId('OT'),
                      name: '',
                      hourlyRate: 0,
                    );
                t
                  ..name = name.text.trim()
                  ..hourlyRate = r;
                await store.upsertTheatre(t);
              });
              if (ok) nav.pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
