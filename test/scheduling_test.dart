import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/data/storage.dart';
import 'package:hospital_app/models/models.dart';

Future<HospitalStore> _store({String user = 'reception'}) async {
  final s = HospitalStore(storage: MemoryStorage());
  await s.load();
  await s.login(user, '1234');
  return s;
}

/// A Monday at least a week ahead, so every slot is in the future.
DateTime _monday() {
  final d = DateTime.now().add(const Duration(days: 8));
  final m = d.subtract(Duration(days: d.weekday - 1));
  return DateTime(m.year, m.month, m.day);
}

DateTime _at(DateTime day, int h, [int m = 0]) =>
    DateTime(day.year, day.month, day.day, h, m);

Patient _patient(HospitalStore s, String name) =>
    s.patients.firstWhere((p) => p.name == name);

void main() {
  group('doctor schedules', () {
    test('slots follow working hours and the appointment length', () async {
      final s = await _store();
      final mon = _monday();
      // Dr. Obi: 09:00–13:00 and 14:00–17:00 in 15-minute slots.
      final slots = s.availableSlots('USR-doc1', mon);
      expect(slots.length, 16 + 12);
      expect(slots.first, _at(mon, 9));
      expect(slots.last, _at(mon, 16, 45));
      expect(slots.contains(_at(mon, 13)), isFalse); // lunch
      // Not working at weekends.
      expect(
        s.availableSlots('USR-doc1', mon.add(const Duration(days: 5))),
        isEmpty,
      );
      // Dr. Mehta uses 20-minute slots from 10:00 to 16:00.
      expect(s.availableSlots('USR-doc2', mon).length, 18);
    });

    test(
      'booking is refused outside hours, on taken slots and days off',
      () async {
        final s = await _store();
        final mon = _monday();
        final mary = _patient(s, 'Mary Johnson').id;
        final ali = _patient(s, 'Ali Hassan').id;
        Future<void> book(String p, DateTime t) => s.bookAppointment(
          patientId: p,
          doctorId: 'USR-doc1',
          scheduledAt: t,
        );

        await book(mary, _at(mon, 9));
        expect(
          s.availableSlots('USR-doc1', mon).contains(_at(mon, 9)),
          isFalse,
        );
        for (final bad in [
          _at(mon, 9), // taken
          _at(mon, 9, 10), // overlaps the 09:00 appointment
          _at(mon, 8), // before hours
          _at(mon, 12, 50), // runs past 13:00
          _at(mon.add(const Duration(days: 6)), 10), // Sunday
        ]) {
          await expectLater(
            book(ali, bad),
            throwsA(isA<HospitalException>()),
            reason: '$bad',
          );
        }
        await book(ali, _at(mon, 9, 15));
        // Cancelling frees the slot again.
        final first = s.appointments.firstWhere(
          (a) => a.patientId == mary && a.scheduledAt == _at(mon, 9),
        );
        await s.cancelAppointment(first.id);
        expect(s.availableSlots('USR-doc1', mon).first, _at(mon, 9));
      },
    );

    test('walk-ins are not bound by the schedule', () async {
      final s = await _store();
      final a = await s.walkIn(
        patientId: _patient(s, 'Peter Okafor').id,
        doctorId: 'USR-doc2',
      );
      expect(a.status, AppointmentStatus.checkedIn);
    });

    test('approved leave blocks the days and flags booked patients', () async {
      final s = await _store(user: 'admin');
      final mon = _monday();
      final appt = await s.bookAppointment(
        patientId: _patient(s, 'Mary Johnson').id,
        doctorId: 'USR-doc1',
        scheduledAt: _at(mon, 10),
      );
      final leave = await s.requestLeave(
        staffId: 'USR-doc1',
        type: LeaveType.annual,
        from: mon,
        to: mon.add(const Duration(days: 1)),
      );
      await s.decideLeave(leave.id, approve: true);
      expect(s.availableSlots('USR-doc1', mon), isEmpty);
      expect(s.appointmentsDuring(leave).single.id, appt.id);
      await expectLater(
        s.bookAppointment(
          patientId: _patient(s, 'Ali Hassan').id,
          doctorId: 'USR-doc1',
          scheduledAt: _at(mon, 11),
        ),
        throwsA(isA<HospitalException>()),
      );
      final reception = s.userById('USR-rec')!;
      expect(
        s.notificationsFor(reception).first.title,
        'Appointments to rebook',
      );
      // The next free slot skips the leave.
      expect(
        s.nextAvailableSlot('USR-doc1', from: mon),
        _at(mon.add(const Duration(days: 2)), 9),
      );
    });

    test('rescheduling checks the new slot and refreshes reminders', () async {
      final s = await _store();
      final mon = _monday();
      final mary = _patient(s, 'Mary Johnson').id;
      final a = await s.bookAppointment(
        patientId: mary,
        doctorId: 'USR-doc1',
        scheduledAt: _at(mon, 9),
      );
      await s.bookAppointment(
        patientId: _patient(s, 'Ali Hassan').id,
        doctorId: 'USR-doc1',
        scheduledAt: _at(mon, 10),
      );
      await expectLater(
        s.rescheduleAppointment(a.id, _at(mon, 10)),
        throwsA(isA<HospitalException>()),
      );
      await s.rescheduleAppointment(a.id, _at(mon, 14, 30));
      expect(a.scheduledAt, _at(mon, 14, 30));
      final pending = s
          .remindersFor(a.id)
          .where((r) => r.status == ReminderStatus.pending)
          .toList();
      expect(pending.length, 2);
      expect(pending.last.sendAt, _at(mon, 12, 30)); // 2 hours before
      expect(
        s.remindersFor(a.id).where((r) => r.status == ReminderStatus.cancelled),
        hasLength(2),
      );
    });

    test('follow-ups take the doctor’s next free slot', () async {
      final s = await _store(user: 'doctor');
      final mon = _monday();
      final c = await s.startConsultation(
        patientId: _patient(s, 'Mary Johnson').id,
        doctorId: 'USR-doc1',
      );
      c
        ..diagnosis = 'Asthma'
        ..followUpDate = _at(mon.add(const Duration(days: 5)), 10); // Saturday
      await s.completeConsultation(c.id);
      final follow = s.appointments.lastWhere(
        (a) => a.reason == 'Follow-up: Asthma',
      );
      // Dr. Obi doesn't work weekends: the following Monday at 09:00.
      expect(follow.scheduledAt, _at(mon.add(const Duration(days: 7)), 9));
    });

    test(
      'only the doctor or an admin edits a schedule, and it must be valid',
      () async {
        final s = await _store(user: 'doctor'); // Dr. Obi
        await expectLater(
          s.saveSchedule(
            'USR-doc2',
            slotMinutes: 15,
            week: {
              1: const [WorkSession('09:00', '12:00')],
            },
          ),
          throwsA(isA<HospitalException>()),
        );
        await expectLater(
          s.saveSchedule(
            'USR-doc1',
            slotMinutes: 15,
            week: {
              1: const [
                WorkSession('09:00', '12:00'),
                WorkSession('11:00', '13:00'),
              ],
            },
          ),
          throwsA(isA<HospitalException>()),
        );
        await s.saveSchedule(
          'USR-doc1',
          slotMinutes: 30,
          week: {
            1: const [
              WorkSession('14:00', '16:00'),
              WorkSession('08:00', '10:00'),
            ],
            3: const [WorkSession('08:00', '10:00')],
          },
        );
        final sch = s.scheduleFor('USR-doc1')!;
        expect(sch.sessionsOn(1).first.start, '08:00'); // sorted
        expect(s.availableSlots('USR-doc1', _monday()).length, 8);
        expect(sch.summary, 'Mon 08:00–10:00, 14:00–16:00 · Wed 08:00–10:00');
      },
    );
  });

  group('appointment reminders', () {
    test('booking queues SMS reminders 24 h and 2 h before', () async {
      final s = await _store();
      final mon = _monday();
      final mary = _patient(s, 'Mary Johnson'); // 0802 444 5566
      final a = await s.bookAppointment(
        patientId: mary.id,
        doctorId: 'USR-doc1',
        scheduledAt: _at(mon, 9, 30),
        reason: 'Review',
      );
      final rs = s.remindersFor(a.id);
      expect(rs.map((r) => r.sendAt), [
        _at(mon.subtract(const Duration(days: 1)), 9, 30),
        _at(mon, 7, 30),
      ]);
      expect(rs.first.channel, ReminderChannel.sms);
      expect(rs.first.to, '+2348024445566');
      expect(rs.first.message, contains('Mary Johnson'));
      expect(rs.first.message, contains('Dr. Amaka Obi'));
      expect(rs.first.message, contains('09:30'));
      expect(rs.first.message, contains(s.profile.name));

      expect(
        s.remindersDue(_at(mon, 7)).where((r) => r.appointmentId == a.id),
        hasLength(1),
      );
      expect(
        s.remindersDue(_at(mon, 8)).where((r) => r.appointmentId == a.id),
        hasLength(2),
      );
      await s.markReminderSent(rs.first.id);
      expect(rs.first.status, ReminderStatus.sent);
      expect(rs.first.sentBy, 'USR-rec');
    });

    test('reminders are withdrawn on cancel and check-in', () async {
      final s = await _store();
      final mon = _monday();
      Future<Appointment> book(int h) => s.bookAppointment(
        patientId: _patient(s, 'Ali Hassan').id,
        doctorId: 'USR-doc1',
        scheduledAt: _at(mon, h),
      );
      final a = await book(9);
      final b = await book(10);
      await s.cancelAppointment(a.id);
      await s.checkIn(b.id);
      for (final id in [a.id, b.id]) {
        expect(
          s.remindersFor(id).every((r) => r.status == ReminderStatus.cancelled),
          isTrue,
        );
      }
    });

    test('appointments booked late only get reminders still ahead', () async {
      final s = await _store(user: 'admin');
      final soon = s.nextAvailableSlot(
        'USR-doc1',
        from: DateTime.now().add(const Duration(hours: 3)),
      )!;
      final a = await s.bookAppointment(
        patientId: _patient(s, 'Mary Johnson').id,
        doctorId: 'USR-doc1',
        scheduledAt: soon,
      );
      expect(
        s.remindersFor(a.id).every((r) => r.sendAt.isAfter(DateTime.now())),
        isTrue,
      );
    });

    test('email is used when there is no phone number', () async {
      final s = await _store();
      final p = await s.registerPatient(
        name: 'Email Only',
        dateOfBirth: DateTime(1990),
        gender: 'Female',
        phone: '',
      );
      p.email = 'eo@example.com';
      final a = await s.bookAppointment(
        patientId: p.id,
        doctorId: 'USR-doc1',
        scheduledAt: _at(_monday(), 11),
      );
      final r = s.remindersFor(a.id).first;
      expect(r.channel, ReminderChannel.email);
      final link = s.reminderLink(r);
      expect(link.scheme, 'mailto');
      expect(link.path, 'eo@example.com');
      expect(link.query, contains('body='));
    });

    test('phone numbers and send links', () async {
      final s = await _store();
      expect(s.internationalPhone('0803 111 2233'), '+2348031112233');
      expect(s.internationalPhone('+44 20 7946 0000'), '+442079460000');
      expect(s.internationalPhone('0044 20 7946 0000'), '+442079460000');
      final a = await s.bookAppointment(
        patientId: _patient(s, 'John Adeyemi').id,
        doctorId: 'USR-doc1',
        scheduledAt: _at(_monday(), 15),
      );
      final r = s.remindersFor(a.id).first;
      final sms = s.reminderLink(r);
      expect(sms.scheme, 'sms');
      expect(sms.path, '+2348031112233');
      expect(sms.queryParameters['body'], r.message);
      final wa = s.reminderLink(r, via: ReminderChannel.whatsapp);
      expect(wa.host, 'wa.me');
      expect(wa.path, '/2348031112233');
      expect(wa.queryParameters['text'], r.message);
    });

    test('the template can be changed', () async {
      final s = await _store(user: 'admin');
      s.profile
        ..reminderTemplate = '{patient}: {doctor} on {date} at {time}'
        ..reminderHours = [48];
      final a = await s.bookAppointment(
        patientId: _patient(s, 'Mary Johnson').id,
        doctorId: 'USR-doc3',
        scheduledAt: _at(_monday(), 9),
      );
      final r = s.remindersFor(a.id).single;
      expect(
        r.message,
        startsWith('Mary Johnson: Dr. Sofia Lindqvist on Mon '),
      );
      expect(r.message, endsWith(' at 09:00'));
    });
  });
}
