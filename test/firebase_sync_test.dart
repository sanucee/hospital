import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/firebase_backend.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/models/models.dart';

/// Several "devices" (stores) sharing one Firestore database.
void main() {
  late FakeFirebaseFirestore db;

  /// Lets queued snapshot events reach every device.
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

  /// A device signed in as an account previously created via createLogin.
  Future<HospitalStore> device(String email) async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'uid-$email', email: email),
    );
    final store = HospitalStore(backend: backendFor(auth));
    await store.load();
    await store.login(email, 'secret1');
    await settle();
    expect(store.session, SessionStatus.ready, reason: email);
    return store;
  }

  /// Sets up the hospital on an admin device and creates logins for the
  /// demo staff.
  Future<HospitalStore> setUpHospital() async {
    final admin = HospitalStore(backend: backendFor(MockFirebaseAuth()));
    await admin.load();
    await admin.setupHospital(
      name: 'Chief Admin',
      email: 'admin@h.org',
      password: 'secret1',
    );
    await settle();
    for (final (id, email) in [
      ('USR-doc1', 'doctor@h.org'),
      ('USR-lab', 'lab@h.org'),
      ('USR-pha', 'pharmacy@h.org'),
      ('USR-rec', 'reception@h.org'),
      ('USR-nur', 'nurse@h.org'),
      ('USR-acc', 'accounts@h.org'),
    ]) {
      await admin.createLoginFor(id, email: email, password: 'secret1');
    }
    await settle();
    return admin;
  }

  setUp(() => db = FakeFirebaseFirestore());

  test('first-run setup creates the admin, role and shared data', () async {
    final admin = await setUpHospital();
    expect(admin.currentUser!.name, 'Chief Admin');
    expect(admin.currentUser!.role, UserRole.admin);

    final setup = await db.doc('meta/setup').get();
    expect(setup.exists, isTrue);
    final role = await db.doc('roles/${admin.currentUser!.authUid}').get();
    expect(role.data(), {'role': 'admin', 'staffId': 'USR-admin'});
    expect((await db.doc('roles/uid-doctor@h.org').get()).data(), {
      'role': 'doctor',
      'staffId': 'USR-doc1',
    });

    final patients = await db.collection('patients').get();
    expect(patients.docs.length, admin.patients.length);
    // Invoice lines are stored apart from their invoice.
    final lines = await db.collection('invoiceLines').get();
    expect(lines.docs, isNotEmpty);
    expect(
      (await db.collection('invoices').get()).docs.first.data(),
      isNot(contains('lines')),
    );
  });

  test('a second device signs in and sees the same hospital', () async {
    final admin = await setUpHospital();
    final doctor = await device('doctor@h.org');
    expect(doctor.currentUser!.id, 'USR-doc1');
    expect(
      doctor.patients.map((p) => p.id).toSet(),
      admin.patients.map((p) => p.id).toSet(),
    );
    expect(doctor.doctorQueue('USR-doc1').length, 2);
    // Invoices are reassembled with their lines on the other device.
    Invoice pastVisit(HospitalStore s) =>
        s.invoices.singleWhere((i) => i.consultationId != null);
    expect(pastVisit(doctor).total, pastVisit(admin).total);
    expect(pastVisit(doctor).lines.length, 4);
    expect(doctor.activeAdmissions.length, 1);

    // Salaries and finance are visible to the admin but never reach a
    // doctor's device.
    expect(admin.salaries, isNotEmpty);
    expect(admin.expenses, isNotEmpty);
    expect(doctor.salaries, isEmpty);
    expect(doctor.payslips, isEmpty);
    expect(doctor.expenses, isEmpty);
  });

  test('account without a role gets no access', () async {
    await setUpHospital();
    final stranger = HospitalStore(
      backend: backendFor(
        MockFirebaseAuth(
          mockUser: MockUser(uid: 'nobody', email: 'x@y.z'),
        ),
      ),
    );
    await stranger.load();
    await stranger.login('x@y.z', 'whatever');
    await settle();
    expect(stranger.session, SessionStatus.noAccess);
    expect(stranger.currentUser, isNull);
    expect(stranger.patients, isEmpty);
  });

  test(
    'reception → doctor → lab → pharmacy → billing across devices',
    () async {
      await setUpHospital();
      final reception = await device('reception@h.org');
      final doctor = await device('doctor@h.org');
      final lab = await device('lab@h.org');
      final pharmacy = await device('pharmacy@h.org');

      // Reception registers a walk-in on their device.
      final p = await reception.registerPatient(
        name: 'Remote Patient',
        dateOfBirth: DateTime(1980),
        gender: 'Male',
        phone: '555',
      );
      final appt = await reception.walkIn(
        patientId: p.id,
        doctorId: 'USR-doc1',
      );
      await settle();
      expect(appt.tokenNumber, 3);
      expect(
        doctor.doctorQueue('USR-doc1').map((a) => a.id),
        contains(appt.id),
      );
      expect(doctor.unreadCount(doctor.currentUser!), greaterThan(0));

      // Doctor consults and orders tests; the lab sees them.
      final c = await doctor.startConsultation(
        patientId: p.id,
        doctorId: 'USR-doc1',
        appointmentId: appt.id,
      );
      final orders = await doctor.orderLabTests(
        consultationId: c.id,
        testIds: ['LT-fbs'],
        urgent: true,
      );
      final rx = await doctor.prescribe(
        consultationId: c.id,
        items: [
          PrescriptionItem(
            medicineId: 'MED-metf',
            medicineName: 'Metformin',
            dosage: '1',
            frequency: 'Twice daily',
            durationDays: 10,
            quantity: 20,
          ),
        ],
      );
      await settle();
      expect(lab.labQueue.first.id, orders.single.id);
      expect(pharmacy.pharmacyQueue.map((r) => r.id), contains(rx.id));
      expect(
        reception.appointmentById(appt.id)!.status,
        AppointmentStatus.inConsultation,
      );

      // Lab result reaches the doctor.
      await lab.enterLabResult(
        labOrderId: orders.single.id,
        result: '142 mg/dL',
        abnormal: true,
      );
      await settle();
      expect(doctor.unreviewedResults('USR-doc1').single.result, '142 mg/dL');

      // Pharmacy dispenses; every device sees the stock drop and the charges.
      final stockBefore = pharmacy.medicineById('MED-metf')!.stock;
      await pharmacy.dispense(rx.id);
      await settle();
      for (final s in [reception, doctor, lab, pharmacy]) {
        expect(s.medicineById('MED-metf')!.stock, stockBefore - 20);
      }
      final inv = reception.invoiceForConsultation(c.id)!;
      expect(inv.totalFor(BillingDepartment.consultation), 50);
      expect(inv.totalFor(BillingDepartment.laboratory), 6);
      expect(inv.totalFor(BillingDepartment.pharmacy), closeTo(2.4, 1e-9));

      await reception.recordPayment(inv.id, inv.total);
      await settle();
      expect(pharmacy.invoiceForConsultation(c.id)!.isPaid, isTrue);
    },
  );

  test('concurrent edits to the same records are merged, not lost', () async {
    final admin = await setUpHospital();
    final doctor = await device('doctor@h.org');
    final lab = await device('lab@h.org');
    final pharmacy = await device('pharmacy@h.org');

    final patientId = admin.patients.first.id;
    final c = await doctor.startConsultation(
      patientId: patientId,
      doctorId: 'USR-doc1',
    );
    final orders = await doctor.orderLabTests(
      consultationId: c.id,
      testIds: ['LT-cbc', 'LT-esr'],
    );
    PrescriptionItem item(int qty) => PrescriptionItem(
      medicineId: 'MED-para',
      medicineName: 'Paracetamol',
      dosage: '1',
      frequency: 'Once daily',
      durationDays: qty,
      quantity: qty,
    );
    final rx1 = await doctor.prescribe(consultationId: c.id, items: [item(10)]);
    final rx2 = await doctor.prescribe(consultationId: c.id, items: [item(25)]);
    await settle();
    await lab.enterLabResult(labOrderId: orders[0].id, result: 'Normal');
    await settle();
    final stock = admin.medicineById('MED-para')!.stock;

    // Without syncing in between: the pharmacist and the admin each dispense
    // one prescription, the lab cancels a test (removing its charge) and
    // adds remarks, and the doctor marks the first result reviewed.
    await pharmacy.dispense(rx1.id);
    await admin.dispense(rx2.id);
    await lab.cancelLabOrder(orders[1].id);
    lab.labOrders.firstWhere((o) => o.id == orders[0].id).resultRemarks =
        'Repeat in 3 months';
    await lab.saveConsultation(lab.consultationById(c.id)!); // commits
    await doctor.markResultReviewed(orders[0].id);
    await settle();

    for (final s in [admin, doctor, lab, pharmacy]) {
      // Both dispenses deducted (stock is written as an increment).
      expect(s.medicineById('MED-para')!.stock, stock - 35);
      // Lab's remarks and the doctor's review flag both survive.
      final o = s.labOrders.firstWhere((o) => o.id == orders[0].id);
      expect(o.resultRemarks, 'Repeat in 3 months');
      expect(o.reviewedByDoctor, isTrue);
      // Both pharmacy charges are present and the cancelled test is gone.
      final inv = s.invoiceForConsultation(c.id)!;
      expect(inv.totalFor(BillingDepartment.pharmacy), closeTo(3.5, 1e-9));
      expect(inv.totalFor(BillingDepartment.laboratory), 15);
    }
  });

  test(
    'patients registered on different devices share one MRN sequence',
    () async {
      // (The fake database doesn't serialise truly concurrent transactions, so
      // devices take turns here; real Firestore retries conflicting ones.)
      final admin = await setUpHospital();
      final reception = await device('reception@h.org');
      final results = [
        for (var i = 0; i < 3; i++) ...[
          await admin.registerPatient(
            name: 'A$i',
            dateOfBirth: DateTime(2000),
            gender: 'F',
            phone: '1',
          ),
          await reception.registerPatient(
            name: 'R$i',
            dateOfBirth: DateTime(2000),
            gender: 'F',
            phone: '2',
          ),
        ],
      ];
      final mrns = results.map((p) => p.mrn).toSet();
      expect(mrns.length, 6);
      expect(mrns.every((m) => RegExp(r'^MRN-\d{5}$').hasMatch(m)), isTrue);
      expect(results.last.mrn, 'MRN-00011'); // 5 demo patients + 6 new
    },
  );

  test(
    'admissions and discharge billing sync; payroll stays with accounts',
    () async {
      await setUpHospital();
      final reception = await device('reception@h.org');
      final nurse = await device('nurse@h.org');
      final accounts = await device('accounts@h.org');

      final mary = reception.patients.firstWhere(
        (p) => p.name == 'Mary Johnson',
      );
      final a = await reception.admitPatient(
        patientId: mary.id,
        roomId: 'RM-101',
        doctorId: 'USR-doc1',
        reason: 'Pneumonia',
      );
      await settle();
      expect(nurse.activeAdmissionFor(mary.id)?.id, a.id);
      expect(nurse.freeBeds('RM-101'), 0);
      expect(
        nurse.notificationsFor(nurse.currentUser!).first.title,
        'New admission',
      );

      await nurse.dischargePatient(a.id);
      await settle();
      expect(
        accounts.invoiceForAdmission(a.id)!.totalFor(BillingDepartment.room),
        150,
      );

      expect(accounts.salaries, isNotEmpty);
      expect(nurse.salaries, isEmpty);
      await accounts.generatePayroll(DateTime(2031, 1));
      await settle();
      expect(nurse.payslips, isEmpty);
      expect(
        (await db.collection('payslips').get()).docs.length,
        greaterThan(10),
      );
    },
  );

  test(
    'insurer and patient payments, and receiving while dispensing, merge',
    () async {
      final admin = await setUpHospital();
      final reception = await device('reception@h.org');
      final accounts = await device('accounts@h.org');
      final pharmacy = await device('pharmacy@h.org');
      final doctor = await device('doctor@h.org');

      // An insured visit with a claim approved in full.
      final ali = doctor.patients.firstWhere((p) => p.name == 'Ali Hassan');
      final c = await doctor.startConsultation(
        patientId: ali.id,
        doctorId: 'USR-doc1',
      );
      final rx = await doctor.prescribe(
        consultationId: c.id,
        items: [
          PrescriptionItem(
            medicineId: 'MED-para',
            medicineName: 'Paracetamol',
            dosage: '1',
            frequency: 'Once daily',
            durationDays: 10,
            quantity: 10,
          ),
        ],
      );
      await settle();
      final invId = reception.invoiceForConsultation(c.id)!.id;
      final claim = await reception.createClaim(invId);
      await reception.submitClaim(claim.id);
      await reception.decideClaim(
        claim.id,
        approvedAmount: claim.amountClaimed,
      );
      await settle();

      // Same moment: the patient pays at reception, the insurer's remittance is
      // booked by accounts.
      final inv = reception.invoiceForConsultation(c.id)!;
      await reception.recordPayment(inv.id, inv.patientBalance);
      await accounts.recordInsurerPayment(claim.id, claim.amountClaimed);
      await settle();
      for (final s in [reception, accounts, admin]) {
        final i = s.invoiceForConsultation(c.id)!;
        expect(i.isPaid, isTrue);
        expect(s.paymentsFor(i.id).length, 2);
      }

      // Same moment: a delivery is booked in while medicine is dispensed.
      final po = pharmacy.purchaseOrders.firstWhere(
        (p) => p.status == PurchaseStatus.ordered,
      );
      final stockBefore = pharmacy.medicineById('MED-para')!.stock;
      final paraPo = await pharmacy.createPurchaseOrder(
        supplierId: po.supplierId,
        items: [
          PurchaseItem(
            medicineId: 'MED-para',
            medicineName: 'Paracetamol',
            quantity: 100,
            unitCost: 0.05,
          ),
        ],
      );
      await pharmacy.placePurchaseOrder(paraPo.id);
      await settle();
      await pharmacy.receiveGoods(paraPo.id, {0: (100, 'B9', null)});
      await admin.dispense(rx.id);
      await settle();
      for (final s in [pharmacy, admin, doctor]) {
        expect(s.medicineById('MED-para')!.stock, stockBefore + 100 - 10);
      }
    },
  );

  test(
    'everyone appends to the audit log; only the admin can read it',
    () async {
      final admin = await setUpHospital();
      final reception = await device('reception@h.org');
      final nurse = await device('nurse@h.org');

      final mary = reception.patients.firstWhere(
        (p) => p.name == 'Mary Johnson',
      );
      mary.phone = '0811 111 1111';
      await reception.updatePatient(mary);
      final a = nurse.activeAdmissions.first;
      await nurse.recordVitals(admissionId: a.id, pulse: 88, spo2: 97);
      await settle();

      final logged = (await db.collection('auditLog').get()).docs
          .map((d) => d.data())
          .toList();
      expect(
        logged.where(
          (e) => e['userId'] == 'USR-rec' && e['action'] == 'updated',
        ),
        isNotEmpty,
      );
      expect(
        logged.where(
          (e) => e['userId'] == 'USR-nur' && e['collection'] == 'vitals',
        ),
        isNotEmpty,
      );
      // Non-admin devices don't keep the log; the admin's sees it live.
      expect(reception.auditLog, isEmpty);
      expect(
        admin.auditLog.where((e) => e.summary.contains('0811 111 1111')),
        isNotEmpty,
      );
      // Later pushes from the receptionist don't resend or delete entries.
      final before = logged.length;
      await reception.bookAppointment(
        patientId: mary.id,
        doctorId: 'USR-doc1',
        scheduledAt: DateTime.now(),
      );
      await settle();
      expect(
        (await db.collection('auditLog').get()).docs.length,
        greaterThan(before),
      );
      // Nursing records written by the nurse are visible to the doctor.
      final doctor = await device('doctor@h.org');
      expect(doctor.latestVitals(a.id)?.pulse, 88);
    },
  );

  test('signing out clears the data from the device', () async {
    await setUpHospital();
    final doctor = await device('doctor@h.org');
    expect(doctor.patients, isNotEmpty);
    await doctor.logout();
    await settle();
    expect(doctor.session, SessionStatus.signedOut);
    expect(doctor.patients, isEmpty);
    expect(doctor.currentUser, isNull);
  });
}
