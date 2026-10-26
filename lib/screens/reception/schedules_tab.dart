import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Each doctor's weekly working hours, leave and next free slot.
class SchedulesTab extends StatelessWidget {
  const SchedulesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final me = store.currentUser!;
    final doctors = store.doctors.where((d) => d.active).toList();
    if (doctors.isEmpty) {
      return const EmptyState('No doctors yet', icon: Icons.person_off);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final d in doctors) _card(context, store, me, d)],
    );
  }

  Widget _card(
    BuildContext context,
    HospitalStore store,
    StaffUser me,
    StaffUser d,
  ) {
    final s = store.scheduleFor(d.id);
    final hasHours = s != null && !s.isEmpty;
    final next = hasHours ? store.nextAvailableSlot(d.id) : null;
    final leave = store.leaveOn(d.id, DateTime.now());
    final canEdit = me.role == UserRole.admin || me.id == d.id;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.medical_services)),
        title: Text('${d.name} · ${d.specialization ?? 'Doctor'}'),
        subtitle: Text(
          [
            hasHours
                ? '${s.summary} · ${s.slotMinutes} min appointments'
                : 'No working hours set – any time can be booked',
            if (leave != null) 'On leave until ${fmtDate(leave.to)}',
            if (hasHours)
              next == null
                  ? 'Fully booked for the next 60 days'
                  : 'Next free: ${fmtDate(next)} ${fmtTime(next)}',
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: canEdit
            ? IconButton(
                tooltip: 'Edit working hours',
                icon: const Icon(Icons.edit),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => ScheduleEditor(doctor: d),
                ),
              )
            : null,
      ),
    );
  }
}

/// Edits a doctor's appointment length and sessions for each weekday.
class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({super.key, required this.doctor});

  final StaffUser doctor;

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  late final DoctorSchedule? _existing = context
      .read<HospitalStore>()
      .scheduleFor(widget.doctor.id);
  late int _slot = _existing?.slotMinutes ?? 15;
  late final Map<int, List<WorkSession>> _week = {
    for (var d = 1; d <= 7; d++) d: [...?_existing?.sessionsOn(d)],
  };

  static const _slotChoices = [10, 15, 20, 30, 45, 60];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Working hours – ${widget.doctor.name}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _slotChoices.contains(_slot) ? _slot : null,
                decoration: const InputDecoration(
                  labelText: 'Appointment length',
                ),
                items: [
                  for (final m in {..._slotChoices, _slot})
                    DropdownMenuItem(value: m, child: Text('$m minutes')),
                ],
                onChanged: (v) => setState(() => _slot = v!),
              ),
              const SizedBox(height: 8),
              for (var d = 1; d <= 7; d++) _day(d),
              const SizedBox(height: 8),
              Text(
                'Leave approved in HR blocks booking automatically. '
                'Walk-ins are always accepted.',
                style: Theme.of(context).textTheme.bodySmall,
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
        OutlinedButton(
          onPressed: () => setState(() {
            for (var d = 2; d <= 5; d++) {
              _week[d] = [..._week[1]!];
            }
          }),
          child: const Text('Copy Mon to Tue–Fri'),
        ),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            final store = context.read<HospitalStore>();
            if (await guarded(
              context,
              () => store.saveSchedule(
                widget.doctor.id,
                slotMinutes: _slot,
                week: {
                  for (final e in _week.entries)
                    if (e.value.isNotEmpty) e.key: e.value,
                },
              ),
              success: 'Working hours saved',
            )) {
              nav.pop();
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _day(int d) {
    final sessions = _week[d]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 44, child: Text(kWeekdays[d - 1])),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (sessions.isEmpty)
                  Text(
                    'Off',
                    style: TextStyle(color: Theme.of(context).disabledColor),
                  ),
                for (final w in sessions)
                  InputChip(
                    label: Text('$w'),
                    onPressed: () => _edit(d, w),
                    onDeleted: () => setState(() => sessions.remove(w)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Session'),
                  onPressed: () => _edit(d, null),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(int day, WorkSession? current) async {
    TimeOfDay parse(String hhmm) {
      final [h, m] = hhmm.split(':').map(int.parse).toList();
      return TimeOfDay(hour: h, minute: m);
    }

    final start = await showTimePicker(
      context: context,
      helpText: '${kWeekdays[day - 1]}: session starts',
      initialTime: current == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : parse(current.start),
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      helpText: '${kWeekdays[day - 1]}: session ends',
      initialTime: current == null
          ? TimeOfDay(hour: (start.hour + 4).clamp(0, 23), minute: start.minute)
          : parse(current.end),
    );
    if (end == null) return;
    String fmt(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final w = WorkSession(fmt(start), fmt(end));
    if (!w.isValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The session must end after it starts')),
        );
      }
      return;
    }
    setState(() {
      final list = _week[day]!;
      if (current != null) list.remove(current);
      list
        ..add(w)
        ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    });
  }
}
