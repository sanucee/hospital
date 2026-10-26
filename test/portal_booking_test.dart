import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/firebase_backend.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/data/storage.dart';
import 'package:hospital_app/models/models.dart';

Future<HospitalStore> _store({String? user = 'reception'}) async {
  final s = HospitalStore(storage: MemoryStorage());
  await s.load();
  if (user != null) await s.login(user, '1234');
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

/// Signs a patient in to the portal on a local store.
Future<Patient> _portal(HospitalStore s, String name) async {
  final p = _patient(s, name);
  await s.portalSignIn(mrn: p.mrn, dateOfBirth: p.dateOfBirth);
  return p;
}

void main() {
  group('booking channels', () {
    test('phone bookings record the caller and send a confirmation', () async {
      final s = await _store();
      final chloe = _patient(s, 'Chloe Martin');
      final at = _at(_monday(), 9, 30);
      final a = await s.bookAppointment(
        patientId: chloe.id,
        doctorId: 'USR-doc1',
        scheduledAt: at,
        channel: BookingChannel.phone,
        callerName: ' Anne Martin (mother) ',
        sendConfirmation: true,
      );
      expect(a.channel, BookingChannel.phone);
      expect(a.callerName, 'Anne Martin (mother)');
      expect(a.bookedBy, 'USR-rec');
      final reminders = s.remindersFor(a.id);
      // Confirmation now, then 24 h and 2 h before.
      expect(reminders, hasLength(3));
      expect(reminders.first.isDue(DateTime.now()), isTrue);
      expect(reminders.first.message, contains('is booked'));
      expect(reminders.first.to, '+2348052223344');
      expect(s.bookedSlots.where((b) => b.appointmentId == a.id), hasLength(1));
    });

    test('counter bookings send no confirmation unless asked', () async {
      final s = await _store();
      final a = await s.bookAppointment(
        patientId: _patient(s, 'Ali Hassan').id,
        doctorId: 'USR-doc1',
        scheduledAt: _at(_monday(), 10),
      );
      expect(a.channel, BookingChannel.counter);
      expect(s.remindersFor(a.id), hasLength(2));
      expect(
        s.remindersFor(a.id).every((r) => !r.isDue(DateTime.now())),
        isTrue,
      );
    });

    test(
      'walk-ins and follow-ups are labelled; walk-ins hold no slot',
      () async {
        final s = await _store();
        final w = await s.walkIn(
          patientId: _patient(s, 'John Adeyemi').id,
          doctorId: 'USR-doc2',
        );
        expect(w.channel, BookingChannel.walkIn);
        expect(s.bookedSlots.where((b) => b.appointmentId == w.id), isEmpty);
      },
    );

    test('cancelling frees the slot and rescheduling moves it', () async {
      final s = await _store();
      final mon = _monday();
      final a = await s.bookAppointment(
        patientId: _patient(s, 'Ali Hassan').id,
        doctorId: 'USR-doc1',
        scheduledAt: _at(mon, 11),
      );
      await s.rescheduleAppointment(a.id, _at(mon, 11, 30));
      expect(
        s.bookedSlots.where((b) => b.appointmentId == a.id).single.start,
        _at(mon, 11, 30),
      );
      await s.cancelAppointment(a.id);
      expect(s.bookedSlots.where((b) => b.appointmentId == a.id), isEmpty);
      expect(s.availableSlots('USR-doc1', mon), contains(_at(mon, 11, 30)));
    });

    test('a slot taken on another device blocks booking without the '
        'appointment itself', () async {
      final s = await _store();
      final mon = _monday();
      s.bookedSlots.add(
        BookedSlot(
          doctorId: 'USR-doc1',
          start: _at(mon, 9),
          minutes: 15,
          appointmentId: 'APT-unseen',
        ),
      );
      expect(s.availableSlots('USR-doc1', mon), isNot(contains(_at(mon, 9))));
      expect(
        () => s.bookAppointment(
          patientId: _patient(s, 'Ali Hassan').id,
          doctorId: 'USR-doc1',
          scheduledAt: _at(mon, 9),
        ),
        throwsA(isA<HospitalException>()),
      );
    });
  });

  group('patient portal (on this device)', () {
    test('patients sign in with MRN and date of birth', () async {
      final s = await _store(user: null);
      final john = _patient(s, 'John Adeyemi');
      expect(
        () => s.portalSignIn(
          mrn: john.mrn,
          dateOfBirth: john.dateOfBirth.add(const Duration(days: 1)),
        ),
        throwsA(isA<HospitalException>()),
      );
      await s.portalSignIn(
        mrn: john.mrn.toLowerCase(),
        dateOfBirth: john.dateOfBirth,
      );
      expect(s.currentPatient, john);
      expect(s.currentUser, isNull);
      expect(s.auditLog.last.summary, contains('patient portal'));
      await s.portalSignOut();
      expect(s.currentPatient, isNull);
    });

    test('online booking: own slot, confirmation, reception told', () async {
      final s = await _store(user: null);
      final ali = await _portal(s, 'Ali Hassan');
      expect(s.bookableDoctors.map((d) => d.id), contains('USR-doc2'));
      final at = _at(_monday(), 10);
      final a = await s.portalBook(doctorId: 'USR-doc2', at: at, reason: 'BP');
      expect(a.channel, BookingChannel.online);
      expect(a.bookedBy, isNull);
      expect(a.patientId, ali.id);
      expect(s.remindersFor(a.id).first.message, contains('is booked'));
      expect(s.notifications.last.targetRole, UserRole.receptionist);
      expect(s.notifications.last.title, 'Online booking');
      expect(s.onlineBookingsToday, contains(a));
      expect(s.auditLog.last.userName, 'Ali Hassan (patient portal)');

      // The slot is gone for everyone.
      expect(s.availableSlots('USR-doc2', at), isNot(contains(at)));
      await s.portalSignOut();
      await _portal(s, 'Chloe Martin');
      expect(
        () => s.portalBook(doctorId: 'USR-doc2', at: at),
        throwsA(isA<HospitalException>()),
      );
    });

    test('online booking limits', () async {
      final s = await _store(user: null);
      await _portal(s, 'Mary Johnson');
      final mon = _monday();
      // Not in the next half hour, not outside hours, one a day per doctor.
      expect(
        () => s.portalBook(
          doctorId: 'USR-doc1',
          at: DateTime.now().add(const Duration(minutes: 5)),
        ),
        throwsA(isA<HospitalException>()),
      );
      expect(
        () => s.portalBook(doctorId: 'USR-doc1', at: _at(mon, 13)),
        throwsA(isA<HospitalException>()),
      );
      await s.portalBook(doctorId: 'USR-doc1', at: _at(mon, 9));
      expect(
        () => s.portalBook(doctorId: 'USR-doc1', at: _at(mon, 10)),
        throwsA(isA<HospitalException>()),
      );
      await s.portalBook(doctorId: 'USR-doc2', at: _at(mon, 10));
      await s.portalBook(doctorId: 'USR-doc3', at: _at(mon, 11));
      expect(
        () => s.portalBook(
          doctorId: 'USR-doc1',
          at: _at(mon.add(const Duration(days: 1)), 9),
        ),
        throwsA(
          isA<HospitalException>().having(
            (e) => e.message,
            'message',
            contains('3 upcoming'),
          ),
        ),
      );
      // Doctors without working hours aren't bookable online.
      s.schedules.removeWhere((x) => x.doctorId == 'USR-doc3');
      expect(s.bookableDoctors.map((d) => d.id), isNot(contains('USR-doc3')));
    });

    test('patients cancel only their own bookings', () async {
      final s = await _store(user: null);
      await _portal(s, 'Ali Hassan');
      final mine = await s.portalBook(
        doctorId: 'USR-doc1',
        at: _at(_monday(), 9),
      );
      final someoneElses = s.appointments.firstWhere(
        (a) =>
            a.patientId != mine.patientId &&
            a.status == AppointmentStatus.scheduled,
      );
      expect(
        () => s.portalCancel(someoneElses.id),
        throwsA(isA<HospitalException>()),
      );
      await s.portalCancel(mine.id);
      expect(mine.status, AppointmentStatus.cancelled);
      expect(
        s
            .remindersFor(mine.id)
            .every((r) => r.status == ReminderStatus.cancelled),
        isTrue,
      );
      expect(s.bookedSlots.where((b) => b.appointmentId == mine.id), isEmpty);
      expect(s.notifications.last.title, 'Online cancellation');
    });

    test('only reviewed results are released', () async {
      final s = await _store(user: null);
      final john = await _portal(s, 'John Adeyemi');
      final done = s.labOrders
          .where(
            (o) =>
                o.patientId == john.id && o.status == LabOrderStatus.completed,
          )
          .toList();
      expect(done, isNotEmpty);
      for (final o in done) {
        o.reviewedByDoctor = false;
      }
      expect(s.myResults, isEmpty);
      done.first.reviewedByDoctor = true;
      expect(s.myResults, [done.first]);
      expect(s.myInvoices, isNotEmpty);
      expect(s.myInvoices.every((i) => i.patientId == john.id), isTrue);
    });

    test('new patients register online once', () async {
      final s = await _store(user: null);
      final before = s.patients.length;
      await s.portalRegister(
        name: 'Zara Bello',
        dateOfBirth: DateTime(1999, 4, 2),
        gender: 'Female',
        phone: '0811 000 1111',
      );
      expect(s.patients.length, before + 1);
      expect(s.currentPatient!.name, 'Zara Bello');
      expect(s.notifications.last.title, 'New online registration');
      await s.portalSignOut();
      expect(
        () => s.portalRegister(
          name: 'Zara B.',
          dateOfBirth: DateTime(1999, 4, 2),
          gender: 'Female',
          phone: '+234 811 000 1111',
        ),
        throwsA(isA<HospitalException>()),
      );
    });

    test('patients update their own contact details', () async {
      final s = await _store(user: null);
      final p = await _portal(s, 'Chloe Martin');
      await s.portalUpdateContact(
        phone: '0805 999 0000',
        email: 'chloe@example.com',
        address: '1 New Road',
      );
      expect(p.email, 'chloe@example.com');
      expect(
        () => s.portalUpdateContact(phone: '', email: '', address: ''),
        throwsA(isA<HospitalException>()),
      );
    });

    test('portal accounts are a Firebase feature', () async {
      final s = await _store();
      expect(
        () => s.createPortalLogin(
          _patient(s, 'Ali Hassan').id,
          email: 'a@b.c',
          password: 'secret1',
        ),
        throwsA(isA<HospitalException>()),
      );
    });
  });

  group('patient portal with Firebase', () {
    late FakeFirebaseFirestore db;

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    FirebaseBackend backendFor(MockFirebaseAuth auth) => FirebaseBackend(
      db: db,
      auth: auth,
      createAuthUser: (email, _) async => 'uid-$email',
    );

    Future<HospitalStore> device(String email) async {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'uid-$email', email: email),
      );
      final store = HospitalStore(backend: backendFor(auth));
      await store.load();
      await store.login(email, 'secret1');
      await settle();
      return store;
    }

    setUp(() => db = FakeFirebaseFirestore());

    test('a patient sees only their own records and books online', () async {
      final admin = HospitalStore(backend: backendFor(MockFirebaseAuth()));
      await admin.load();
      await admin.setupHospital(
        name: 'Chief Admin',
        email: 'admin@h.org',
        password: 'secret1',
      );
      await settle();
      await admin.createLoginFor(
        'USR-rec',
        email: 'reception@h.org',
        password: 'secret1',
      );
      final reception = await device('reception@h.org');
      final ali = _patient(reception, 'Ali Hassan');
      await reception.createPortalLogin(
        ali.id,
        email: 'ali@mail.com',
        password: 'secret1',
      );
      expect((await db.doc('roles/uid-ali@mail.com').get()).data(), {
        'role': 'patient',
        'patientId': ali.id,
      });
      // Reception books someone else at Monday 09:00.
      final mon = _monday();
      await reception.bookAppointment(
        patientId: _patient(reception, 'Mary Johnson').id,
        doctorId: 'USR-doc1',
        scheduledAt: _at(mon, 9),
      );
      await settle();

      final portal = await device('ali@mail.com');
      expect(portal.session, SessionStatus.ready);
      expect(portal.currentPatient!.id, ali.id);
      expect(portal.currentUser, isNull);
      // Only Ali's own records reach the device...
      expect(portal.patients.map((p) => p.id), [ali.id]);
      expect(portal.appointments.every((a) => a.patientId == ali.id), isTrue);
      expect(portal.invoices.every((i) => i.patientId == ali.id), isTrue);
      expect(portal.notifications, isEmpty);
      expect(portal.salaries, isEmpty);
      // ...plus the doctor directory, built without staff records.
      expect(portal.doctors.map((d) => d.name), contains('Dr. Amaka Obi'));
      expect(portal.doctors.every((d) => d.phone.isEmpty), isTrue);

      // Mary's 09:00 is taken although her appointment isn't visible.
      expect(
        portal.availableSlots('USR-doc1', mon),
        isNot(contains(_at(mon, 9))),
      );
      final booked = await portal.portalBook(
        doctorId: 'USR-doc1',
        at: _at(mon, 9, 15),
      );
      await settle();

      // Reception sees the online booking and is notified.
      final seen = reception.appointmentById(booked.id)!;
      expect(seen.channel, BookingChannel.online);
      expect(
        reception.notificationsFor(reception.currentUser!).first.title,
        'Online booking',
      );
      expect(
        (await db.collection('auditLog').get()).docs.map(
          (d) => d.data()['userId'],
        ),
        contains(ali.id),
      );
      // Leave shows on the portal through the directory.
      await admin.decideLeave(
        (await admin.requestLeave(
          staffId: 'USR-doc1',
          type: LeaveType.annual,
          from: mon.add(const Duration(days: 1)),
          to: mon.add(const Duration(days: 1)),
        )).id,
        approve: true,
      );
      await settle();
      expect(
        portal.leaveOn('USR-doc1', mon.add(const Duration(days: 1))),
        isNotNull,
      );
      expect(
        portal.availableSlots('USR-doc1', mon.add(const Duration(days: 1))),
        isEmpty,
      );
    });

    test('a new patient registers online and is signed in', () async {
      final admin = HospitalStore(backend: backendFor(MockFirebaseAuth()));
      await admin.load();
      await admin.setupHospital(
        name: 'Chief Admin',
        email: 'admin@h.org',
        password: 'secret1',
      );
      await settle();
      final portal = HospitalStore(backend: backendFor(MockFirebaseAuth()));
      await portal.load();
      await portal.portalRegister(
        name: 'Zara Bello',
        dateOfBirth: DateTime(1999, 4, 2),
        gender: 'Female',
        phone: '0811 000 1111',
        email: 'zara@mail.com',
        password: 'secret1',
      );
      await settle();
      expect(portal.session, SessionStatus.ready);
      expect(portal.currentPatient!.name, 'Zara Bello');
      expect(portal.currentPatient!.mrn, startsWith('MRN-W'));
      await settle();
      expect(admin.patients.map((p) => p.name), contains('Zara Bello'));
    });
  });
}
