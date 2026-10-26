import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';
import 'phone_booking.dart';
import 'reminders_tab.dart';
import 'schedules_tab.dart';

/// Appointments by day, doctors' working hours and patient reminders.
class AppointmentsScreen extends StatelessWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final role = store.currentUser!.role;
    final reminders = role == UserRole.admin || role == UserRole.receptionist;
    final due = reminders ? store.remindersDue().length : 0;
    return DefaultTabController(
      length: reminders ? 3 : 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              const Tab(text: 'Day list'),
              const Tab(text: 'Doctor schedules'),
              if (reminders)
                Tab(text: 'Reminders${due > 0 ? ' ($due to send)' : ''}'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const _DayList(),
                const SchedulesTab(),
                if (reminders) const RemindersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayList extends StatefulWidget {
  const _DayList();

  @override
  State<_DayList> createState() => _DayListState();
}

class _DayListState extends State<_DayList> {
  DateTime _day = DateTime.now();
  String? _doctorFilter;
  BookingChannel? _channelFilter;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final user = store.currentUser!;
    final isDoctor = user.role == UserRole.doctor;
    final canManage = !isDoctor;
    final list = store
        .appointmentsOn(_day, doctorId: isDoctor ? user.id : _doctorFilter)
        .where((a) => _channelFilter == null || a.channel == _channelFilter)
        .toList();

    return Scaffold(
      floatingActionButton: canManage
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'walkin',
                  onPressed: () => _book(context, walkIn: true),
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('Walk-in'),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'phone',
                  onPressed: () =>
                      _book(context, channel: BookingChannel.phone),
                  icon: const Icon(Icons.phone_in_talk),
                  label: const Text('Phone booking'),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'book',
                  onPressed: () => _book(context),
                  icon: const Icon(Icons.event_available),
                  label: const Text('Book at counter'),
                ),
              ],
            )
          : null,
      body: Column(
        children: [
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
                    () => _day = _day.subtract(const Duration(days: 1)),
                  ),
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
                        value: null,
                        child: Text('All doctors'),
                      ),
                      for (final d in store.doctors)
                        DropdownMenuItem(value: d.id, child: Text(d.name)),
                    ],
                    onChanged: (v) => setState(() => _doctorFilter = v),
                  ),
                DropdownButton<BookingChannel?>(
                  value: _channelFilter,
                  hint: const Text('Any booking channel'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Any booking channel'),
                    ),
                    for (final c in BookingChannel.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (v) => setState(() => _channelFilter = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    'No appointments for this day',
                    icon: Icons.event_busy,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 220),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final a = list[i];
                      final p = store.patientById(a.patientId);
                      final pendingReminders = store
                          .remindersFor(a.id)
                          .where((r) => r.status == ReminderStatus.pending)
                          .length;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              a.tokenNumber == null
                                  ? fmtTime(a.scheduledAt)
                                  : '#${a.tokenNumber}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          title: Text(p?.name ?? 'Unknown'),
                          subtitle: Text(
                            '${fmtTime(a.scheduledAt)} · ${store.userName(a.doctorId)}'
                            '${a.reason.isEmpty ? '' : ' · ${a.reason}'}'
                            '\n${_bookedHow(store, a)}'
                            '${pendingReminders > 0 ? ' · $pendingReminders reminder(s) queued' : ''}',
                          ),
                          isThreeLine: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PatientDetailScreen(patientId: a.patientId),
                            ),
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusChip.appointment(a.status),
                              if (canManage &&
                                  a.status == AppointmentStatus.scheduled) ...[
                                IconButton(
                                  tooltip: 'Check in',
                                  icon: const Icon(
                                    Icons.how_to_reg,
                                    color: Colors.green,
                                  ),
                                  onPressed: () => guarded(
                                    context,
                                    () => store.checkIn(a.id),
                                    success:
                                        '${p?.name} sent to ${store.userName(a.doctorId)}',
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Reschedule',
                                  icon: const Icon(Icons.edit_calendar),
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) =>
                                        _BookDialog.reschedule(appointment: a),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cancel',
                                  icon: const Icon(
                                    Icons.cancel_outlined,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => guarded(
                                    context,
                                    () => store.cancelAppointment(a.id),
                                  ),
                                ),
                              ],
                            ],
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

  static String _bookedHow(HospitalStore s, Appointment a) => [
    switch (a.channel) {
      BookingChannel.phone =>
        'By phone${a.callerName.isEmpty ? '' : ' (caller: ${a.callerName})'}',
      _ => a.channel.label,
    },
    if (a.bookedBy != null) 'taken by ${s.userName(a.bookedBy!)}',
    fmtDateTime(a.bookedAt),
  ].join(' · ');

  Future<void> _book(
    BuildContext context, {
    bool walkIn = false,
    BookingChannel channel = BookingChannel.counter,
  }) async {
    final store = context.read<HospitalStore>();
    final patient = channel == BookingChannel.phone
        ? await pickCaller(context, store)
        : await pickPatient(context, store);
    if (patient == null || !context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => _BookDialog(
        patient: patient,
        walkIn: walkIn,
        day: _day,
        channel: channel,
      ),
    );
  }
}

/// Books a new appointment, a walk-in, or moves an existing appointment.
class _BookDialog extends StatefulWidget {
  const _BookDialog({
    required Patient this.patient,
    required this.walkIn,
    required this.day,
    this.channel = BookingChannel.counter,
  }) : appointment = null;

  const _BookDialog.reschedule({required Appointment this.appointment})
    : patient = null,
      walkIn = false,
      day = null,
      channel = BookingChannel.counter;

  final Patient? patient;
  final Appointment? appointment;
  final bool walkIn;
  final DateTime? day;

  /// Counter or phone, for new bookings.
  final BookingChannel channel;

  @override
  State<_BookDialog> createState() => _BookDialogState();
}

class _BookDialogState extends State<_BookDialog> {
  late String? _doctorId = widget.appointment?.doctorId;
  late DateTime _date = widget.appointment?.scheduledAt ?? widget.day!;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  DateTime? _slot;
  late final _reason = TextEditingController(text: widget.appointment?.reason);
  final _caller = TextEditingController();

  /// Phone bookings confirm by SMS by default; at the counter the patient
  /// is standing there.
  late bool _confirm = widget.channel == BookingChannel.phone;

  bool get _rescheduling => widget.appointment != null;
  bool get _phone => widget.channel == BookingChannel.phone;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final patientName = _rescheduling
        ? store.patientName(widget.appointment!.patientId)
        : widget.patient!.name;
    final schedule = _doctorId == null ? null : store.scheduleFor(_doctorId!);
    final useSlots = schedule != null && !schedule.isEmpty && !widget.walkIn;

    return AlertDialog(
      title: Text(
        _rescheduling
            ? 'Reschedule $patientName'
            : widget.walkIn
            ? 'Walk-in: $patientName'
            : _phone
            ? 'Phone booking for $patientName'
            : 'Book for $patientName',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _doctorId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Doctor'),
                items: [
                  for (final d in store.doctors.where((d) => d.active))
                    DropdownMenuItem(
                      value: d.id,
                      child: Text(
                        '${d.name} – ${d.specialization ?? ''}'
                        ' (${money(d.consultationFee)})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _doctorId = v;
                  _slot = null;
                }),
              ),
              if (schedule != null && !widget.walkIn)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${schedule.summary} · ${schedule.slotMinutes}-minute '
                    'appointments',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (!widget.walkIn) ...[
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
                            initialDate: _date.isBefore(DateTime.now())
                                ? DateTime.now()
                                : _date,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 1),
                            ),
                            lastDate: DateTime(2100),
                            selectableDayPredicate: !useSlots
                                ? null
                                : (d) =>
                                      schedule
                                          .sessionsOn(d.weekday)
                                          .isNotEmpty &&
                                      store.leaveOn(_doctorId!, d) == null,
                          );
                          if (d != null) {
                            setState(() {
                              _date = d;
                              _slot = null;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (useSlots)
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.fast_forward),
                          label: const Text('Next available'),
                          onPressed: () {
                            final next = store.nextAvailableSlot(_doctorId!);
                            if (next == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'No free slot in the next 60 days',
                                  ),
                                ),
                              );
                              return;
                            }
                            setState(() {
                              _date = next;
                              _slot = next;
                            });
                          },
                        ),
                      )
                    else
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
                  ],
                ),
                if (useSlots) ...[const SizedBox(height: 12), _slots(store)],
              ],
              if (!_rescheduling) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason for visit',
                  ),
                ),
              ],
              if (_phone) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('caller-name'),
                  controller: _caller,
                  decoration: const InputDecoration(
                    labelText: 'Caller, if not the patient',
                    hintText: 'e.g. Anne Martin (mother)',
                  ),
                ),
              ],
              if (!_rescheduling && !widget.walkIn)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirm,
                  onChanged: (v) => setState(() => _confirm = v!),
                  title: const Text('Send a booking confirmation'),
                  subtitle: Text(
                    widget.patient!.phone.trim().isNotEmpty
                        ? 'By SMS to ${widget.patient!.phone}'
                        : widget.patient!.email.trim().isNotEmpty
                        ? 'By email to ${widget.patient!.email}'
                        : 'No phone or email on file',
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
          onPressed: _doctorId == null || (useSlots && _slot == null)
              ? null
              : () => _save(store, useSlots),
          child: Text(
            _rescheduling
                ? 'Move appointment'
                : widget.walkIn
                ? 'Check in now'
                : 'Book',
          ),
        ),
      ],
    );
  }

  Widget _slots(HospitalStore store) {
    final leave = store.leaveOn(_doctorId!, _date);
    if (leave != null) {
      return Text(
        '${store.userName(_doctorId!)} is on leave on this day.',
        style: const TextStyle(color: Colors.red),
      );
    }
    final slots = store.availableSlots(
      _doctorId!,
      _date,
      ignoreAppointmentId: widget.appointment?.id,
    );
    if (slots.isEmpty) {
      return const Text(
        'No free times on this day. Pick another date or use Next available.',
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in slots)
          ChoiceChip(
            label: Text(fmtTime(t)),
            selected: _slot == t,
            onSelected: (_) => setState(() => _slot = t),
          ),
      ],
    );
  }

  Future<void> _save(HospitalStore store, bool useSlots) async {
    final nav = Navigator.of(context);
    final at =
        _slot ??
        DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    final ok = await guarded(
      context,
      () async {
        if (_rescheduling) {
          await store.rescheduleAppointment(
            widget.appointment!.id,
            at,
            doctorId: _doctorId,
          );
        } else if (widget.walkIn) {
          await store.walkIn(
            patientId: widget.patient!.id,
            doctorId: _doctorId!,
            reason: _reason.text.trim(),
          );
        } else {
          await store.bookAppointment(
            patientId: widget.patient!.id,
            doctorId: _doctorId!,
            scheduledAt: at,
            reason: _reason.text.trim(),
            channel: widget.channel,
            callerName: _caller.text,
            sendConfirmation: _confirm,
          );
        }
      },
      success: _rescheduling
          ? 'Moved to ${fmtDate(at)} ${fmtTime(at)}; reminders updated'
          : widget.walkIn
          ? 'Checked in to ${store.userName(_doctorId!)}'
          : 'Booked for ${fmtDate(at)} ${fmtTime(at)}',
    );
    if (ok) nav.pop();
  }
}
