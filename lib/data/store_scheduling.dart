part of 'hospital_store.dart';

/// Doctors' working hours, bookable slots and appointment reminders.
extension SchedulingOperations on HospitalStore {
  // ---------------------------------------------------------------------------
  // Schedules
  // ---------------------------------------------------------------------------

  DoctorSchedule? scheduleFor(String doctorId) {
    for (final s in schedules) {
      if (s.doctorId == doctorId) return s;
    }
    return null;
  }

  /// Replaces a doctor's weekly hours. Only the doctor themself or an
  /// administrator may change them.
  Future<void> saveSchedule(
    String doctorId, {
    required int slotMinutes,
    required Map<int, List<WorkSession>> week,
  }) async {
    final me = currentUser;
    if (me != null && me.role != UserRole.admin && me.id != doctorId) {
      throw HospitalException('You can only change your own schedule');
    }
    if (slotMinutes < 5 || slotMinutes > 240) {
      throw HospitalException('Appointment length must be 5 to 240 minutes');
    }
    for (final MapEntry(key: d, value: sessions) in week.entries) {
      final sorted = [...sessions]
        ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
      for (var i = 0; i < sorted.length; i++) {
        if (!sorted[i].isValid) {
          throw HospitalException(
            '${kWeekdays[d - 1]}: "${sorted[i]}" is not a valid time range',
          );
        }
        if (i > 0 && sorted[i].startMinutes < sorted[i - 1].endMinutes) {
          throw HospitalException('${kWeekdays[d - 1]}: sessions overlap');
        }
      }
      week[d] = sorted;
    }
    final s = scheduleFor(doctorId) ?? DoctorSchedule(doctorId: doctorId);
    if (!schedules.contains(s)) schedules.add(s);
    s
      ..slotMinutes = slotMinutes
      ..week.clear()
      ..week.addAll(week);
    await _commit();
  }

  /// Approved leave covering [day].
  LeaveRequest? leaveOn(String staffId, DateTime day) {
    final d = _dayOnly(day);
    for (final l in leaves) {
      if (l.staffId == staffId &&
          l.status == LeaveStatus.approved &&
          !d.isBefore(_dayOnly(l.from)) &&
          !d.isAfter(_dayOnly(l.to))) {
        return l;
      }
    }
    return null;
  }

  /// Bookable start times on [day]: within working hours, not on leave,
  /// not already booked, and not in the past.
  List<DateTime> availableSlots(
    String doctorId,
    DateTime day, {
    String? ignoreAppointmentId,
    DateTime? now,
  }) {
    final s = scheduleFor(doctorId);
    if (s == null || leaveOn(doctorId, day) != null) return [];
    final current = now ?? DateTime.now();
    final booked = _bookedRanges(doctorId, day, ignoreAppointmentId);
    final len = Duration(minutes: s.slotMinutes);
    final base = _dayOnly(day);
    return [
      for (final w in s.sessionsOn(day.weekday))
        for (
          var m = w.startMinutes;
          m + s.slotMinutes <= w.endMinutes;
          m += s.slotMinutes
        )
          if (base.add(Duration(minutes: m)) case final t
              when t.isAfter(current) &&
                  !booked.any(
                    (b) => t.isBefore(b.$2) && b.$1.isBefore(t.add(len)),
                  ))
            t,
    ];
  }

  /// The doctor's first free slot from [from] onwards, looking [days] ahead.
  DateTime? nextAvailableSlot(
    String doctorId, {
    DateTime? from,
    int days = 60,
  }) {
    final start = from ?? DateTime.now();
    for (var i = 0; i < days; i++) {
      final day = _dayOnly(start).add(Duration(days: i));
      final slots = availableSlots(
        doctorId,
        day,
        now: i == 0 && start.isAfter(DateTime.now()) ? start : null,
      );
      if (slots.isNotEmpty) return slots.first;
    }
    return null;
  }

  List<(DateTime, DateTime)> _bookedRanges(
    String doctorId,
    DateTime day,
    String? ignoreId,
  ) {
    final len = Duration(minutes: scheduleFor(doctorId)?.slotMinutes ?? 15);
    return [
      for (final a in appointmentsOn(day, doctorId: doctorId))
        if (a.id != ignoreId &&
            a.status != AppointmentStatus.cancelled &&
            a.status != AppointmentStatus.completed)
          (a.scheduledAt, a.scheduledAt.add(len)),
    ];
  }

  /// Throws unless [at] is a bookable time for the doctor. Doctors without
  /// a schedule accept any time.
  void _checkBookable(String doctorId, DateTime at, {String? ignoreId}) {
    final s = scheduleFor(doctorId);
    if (s == null || s.isEmpty) return;
    final name = userName(doctorId);
    if (leaveOn(doctorId, at) != null) {
      throw HospitalException('$name is on leave on ${_fmtDay(at)}');
    }
    final minute = at.hour * 60 + at.minute;
    final inHours = s
        .sessionsOn(at.weekday)
        .any(
          (w) =>
              minute >= w.startMinutes &&
              minute + s.slotMinutes <= w.endMinutes,
        );
    if (!inHours) {
      throw HospitalException(
        '$name does not see patients at that time '
        '(${kWeekdays[at.weekday - 1]}: '
        '${s.sessionsOn(at.weekday).isEmpty ? 'not working' : s.sessionsOn(at.weekday).join(', ')})',
      );
    }
    final len = Duration(minutes: s.slotMinutes);
    if (_bookedRanges(
      doctorId,
      at,
      ignoreId,
    ).any((b) => at.isBefore(b.$2) && b.$1.isBefore(at.add(len)))) {
      throw HospitalException('$name already has a patient at ${_fmtTime(at)}');
    }
  }

  Future<void> rescheduleAppointment(
    String appointmentId,
    DateTime at, {
    String? doctorId,
  }) async {
    final a = appointmentById(appointmentId)!;
    if (a.status != AppointmentStatus.scheduled) {
      throw HospitalException('Only booked appointments can be rescheduled');
    }
    final doctor = doctorId ?? a.doctorId;
    _checkBookable(doctor, at, ignoreId: a.id);
    a
      ..doctorId = doctor
      ..scheduledAt = at;
    _cancelReminders(a.id);
    _createReminders(a);
    _notify(
      title: 'Appointment moved',
      body:
          '${patientName(a.patientId)} is now booked for '
          '${_fmtDay(at)} ${_fmtTime(at)}',
      userId: doctor,
      patientId: a.patientId,
    );
    await _commit();
  }

  /// Booked appointments that fall inside a doctor's leave.
  List<Appointment> appointmentsDuring(LeaveRequest l) => appointments
      .where(
        (a) =>
            a.doctorId == l.staffId &&
            a.status == AppointmentStatus.scheduled &&
            !_dayOnly(a.scheduledAt).isBefore(_dayOnly(l.from)) &&
            !_dayOnly(a.scheduledAt).isAfter(_dayOnly(l.to)),
      )
      .toList();

  // ---------------------------------------------------------------------------
  // Reminders
  // ---------------------------------------------------------------------------

  /// Local numbers ("0803 111 2233") to international form ("+2348031112233").
  String internationalPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('00')) return '+${digits.substring(2)}';
    if (digits.startsWith('0')) {
      return '+${profile.countryCode}${digits.substring(1)}';
    }
    return '+${profile.countryCode}$digits';
  }

  String reminderText(Appointment a) {
    final values = {
      '{patient}': patientName(a.patientId),
      '{doctor}': userName(a.doctorId),
      '{date}': _fmtDay(a.scheduledAt),
      '{time}': _fmtTime(a.scheduledAt),
      '{hospital}': profile.name,
      '{phone}': profile.phone,
      '{reason}': a.reason,
    };
    var text = profile.reminderTemplate;
    for (final MapEntry(key: k, value: v) in values.entries) {
      text = text.replaceAll(k, v);
    }
    return text;
  }

  /// Queues a reminder for each configured lead time still in the future.
  /// Uses SMS when the patient has a phone number, otherwise email.
  void _createReminders(Appointment a) {
    final p = patientById(a.patientId);
    if (p == null) return;
    final (channel, to) = p.phone.trim().isNotEmpty
        ? (ReminderChannel.sms, internationalPhone(p.phone))
        : p.email.trim().isNotEmpty
        ? (ReminderChannel.email, p.email.trim())
        : (null, '');
    if (channel == null) return;
    final now = DateTime.now();
    for (final h in profile.reminderHours.toSet()) {
      final sendAt = a.scheduledAt.subtract(Duration(hours: h));
      if (!sendAt.isAfter(now)) continue;
      reminders.add(
        AppointmentReminder(
          id: newId('REM'),
          appointmentId: a.id,
          patientId: a.patientId,
          channel: channel,
          to: to,
          message: reminderText(a),
          sendAt: sendAt,
        ),
      );
    }
  }

  void _cancelReminders(String appointmentId) {
    for (final r in reminders) {
      if (r.appointmentId == appointmentId &&
          r.status == ReminderStatus.pending) {
        r.status = ReminderStatus.cancelled;
      }
    }
  }

  List<AppointmentReminder> remindersFor(String appointmentId) =>
      reminders.where((r) => r.appointmentId == appointmentId).toList()
        ..sort((a, b) => a.sendAt.compareTo(b.sendAt));

  List<AppointmentReminder> remindersDue([DateTime? at]) {
    final now = at ?? DateTime.now();
    return reminders.where((r) => r.isDue(now)).toList()
      ..sort((a, b) => a.sendAt.compareTo(b.sendAt));
  }

  List<AppointmentReminder> get upcomingReminders {
    final now = DateTime.now();
    return reminders
        .where(
          (r) => r.status == ReminderStatus.pending && r.sendAt.isAfter(now),
        )
        .toList()
      ..sort((a, b) => a.sendAt.compareTo(b.sendAt));
  }

  /// A link that opens the device's SMS, WhatsApp or email app with the
  /// message filled in.
  Uri reminderLink(AppointmentReminder r, {ReminderChannel? via}) {
    final channel = via ?? r.channel;
    final p = patientById(r.patientId);
    return switch (channel) {
      ReminderChannel.sms => Uri(
        scheme: 'sms',
        path: r.channel == ReminderChannel.sms
            ? r.to
            : internationalPhone(p?.phone ?? ''),
        queryParameters: {'body': r.message},
      ),
      ReminderChannel.whatsapp => Uri.https(
        'wa.me',
        '/${(r.channel == ReminderChannel.email ? internationalPhone(p?.phone ?? '') : r.to).replaceAll('+', '')}',
        {'text': r.message},
      ),
      ReminderChannel.email => Uri(
        scheme: 'mailto',
        path: r.channel == ReminderChannel.email ? r.to : p?.email ?? '',
        query:
            'subject=${Uri.encodeComponent('Appointment reminder – ${profile.name}')}'
            '&body=${Uri.encodeComponent(r.message)}',
      ),
    };
  }

  Future<void> markReminderSent(String reminderId) async {
    final r = reminders.firstWhere((r) => r.id == reminderId);
    if (r.status == ReminderStatus.sent) return;
    r
      ..status = ReminderStatus.sent
      ..sentAt = DateTime.now()
      ..sentBy = currentUser?.id
      ..error = '';
    await _commit();
  }

  Future<void> skipReminder(String reminderId) async {
    final r = reminders.firstWhere((r) => r.id == reminderId);
    if (r.status != ReminderStatus.pending &&
        r.status != ReminderStatus.failed) {
      throw HospitalException('Already ${r.status.name}');
    }
    r.status = ReminderStatus.cancelled;
    await _commit();
  }

  static String _fmtDay(DateTime d) =>
      '${kWeekdays[d.weekday - 1]} ${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';

  static String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
