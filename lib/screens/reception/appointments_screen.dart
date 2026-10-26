import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  DateTime _day = DateTime.now();
  String? _doctorFilter;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final user = store.currentUser!;
    final isDoctor = user.role == UserRole.doctor;
    final canManage = !isDoctor;
    final list = store.appointmentsOn(_day,
        doctorId: isDoctor ? user.id : _doctorFilter);

    return Scaffold(
      floatingActionButton: canManage
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              FloatingActionButton.extended(
                heroTag: 'walkin',
                onPressed: () => _book(context, walkIn: true),
                icon: const Icon(Icons.directions_walk),
                label: const Text('Walk-in'),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'book',
                onPressed: () => _book(context),
                icon: const Icon(Icons.event_available),
                label: const Text('Book appointment'),
              ),
            ])
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                    () => _day = _day.subtract(const Duration(days: 1))),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text(fmtDate(_day)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => _day = d);
                },
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
              if (!isDoctor)
                DropdownButton<String?>(
                  value: _doctorFilter,
                  hint: const Text('All doctors'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All doctors')),
                    for (final d in store.doctors)
                      DropdownMenuItem(value: d.id, child: Text(d.name)),
                  ],
                  onChanged: (v) => setState(() => _doctorFilter = v),
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState('No appointments for this day',
                  icon: Icons.event_busy)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 160),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final a = list[i];
                    final p = store.patientById(a.patientId);
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(a.tokenNumber == null
                              ? fmtTime(a.scheduledAt)
                              : '#${a.tokenNumber}',
                              style: const TextStyle(fontSize: 11)),
                        ),
                        title: Text(p?.name ?? 'Unknown'),
                        subtitle: Text(
                            '${fmtTime(a.scheduledAt)} · ${store.userName(a.doctorId)}'
                            '${a.reason.isEmpty ? '' : ' · ${a.reason}'}'),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => PatientDetailScreen(
                                    patientId: a.patientId))),
                        trailing: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusChip.appointment(a.status),
                            if (canManage &&
                                a.status == AppointmentStatus.scheduled) ...[
                              IconButton(
                                tooltip: 'Check in',
                                icon: const Icon(Icons.how_to_reg,
                                    color: Colors.green),
                                onPressed: () => guarded(
                                    context, () => store.checkIn(a.id),
                                    success:
                                        '${p?.name} sent to ${store.userName(a.doctorId)}'),
                              ),
                              IconButton(
                                tooltip: 'Cancel',
                                icon: const Icon(Icons.cancel_outlined,
                                    color: Colors.red),
                                onPressed: () => guarded(context,
                                    () => store.cancelAppointment(a.id)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Future<void> _book(BuildContext context, {bool walkIn = false}) async {
    final store = context.read<HospitalStore>();
    final patient = await pickPatient(context, store);
    if (patient == null || !context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => _BookDialog(patient: patient, walkIn: walkIn, day: _day),
    );
  }
}

class _BookDialog extends StatefulWidget {
  const _BookDialog(
      {required this.patient, required this.walkIn, required this.day});

  final Patient patient;
  final bool walkIn;
  final DateTime day;

  @override
  State<_BookDialog> createState() => _BookDialogState();
}

class _BookDialogState extends State<_BookDialog> {
  String? _doctorId;
  late DateTime _date = widget.day;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  final _reason = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    return AlertDialog(
      title: Text(widget.walkIn
          ? 'Walk-in: ${widget.patient.name}'
          : 'Book for ${widget.patient.name}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _doctorId,
            decoration: const InputDecoration(labelText: 'Doctor'),
            items: [
              for (final d in store.doctors)
                DropdownMenuItem(
                  value: d.id,
                  child: Text('${d.name} – ${d.specialization ?? ''}'
                      ' (${money(d.consultationFee)})'),
                ),
            ],
            onChanged: (v) => setState(() => _doctorId = v),
          ),
          if (!widget.walkIn) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(fmtDate(_date)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 1)),
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
                        context: context, initialTime: _time);
                    if (t != null) setState(() => _time = t);
                  },
                ),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason for visit'),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _doctorId == null
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  final ok = await guarded(context, () async {
                    if (widget.walkIn) {
                      await store.walkIn(
                          patientId: widget.patient.id,
                          doctorId: _doctorId!,
                          reason: _reason.text.trim());
                    } else {
                      await store.bookAppointment(
                        patientId: widget.patient.id,
                        doctorId: _doctorId!,
                        scheduledAt: DateTime(_date.year, _date.month,
                            _date.day, _time.hour, _time.minute),
                        reason: _reason.text.trim(),
                      );
                    }
                  },
                      success: widget.walkIn
                          ? 'Checked in to ${store.userName(_doctorId!)}'
                          : 'Appointment booked');
                  if (ok) nav.pop();
                },
          child: Text(widget.walkIn ? 'Check in now' : 'Book'),
        ),
      ],
    );
  }
}
