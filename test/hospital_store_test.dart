import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/data/storage.dart';
import 'package:hospital_app/models/models.dart';

Future<HospitalStore> _store([MemoryStorage? storage]) async {
  final s = HospitalStore(storage: storage ?? MemoryStorage());
  await s.load();
  return s;
}

void main() {
  test('seeds demo data on first load', () async {
    final s = await _store();
    expect(s.users, isNotEmpty);
    expect(s.doctors.length, 3);
    expect(s.labTests, isNotEmpty);
    expect(s.medicines, isNotEmpty);
    expect(s.doctorQueue('USR-doc1').length, 2);
  });

  test('login is case-insensitive on username and checks password', () async {
    final s = await _store();
    await expectLater(
        s.login('DOCTOR', 'wrong'), throwsA(isA<HospitalException>()));
    await s.login('DOCTOR', '1234');
    expect(s.currentUser!.role, UserRole.doctor);
  });

  test('full patient journey connects reception, doctor, lab, pharmacy and '
      'billing', () async {
    final s = await _store();

    // Reception registers and checks in a walk-in.
    await s.login('reception', '1234');
    final p = await s.registerPatient(
      name: 'Test Patient',
      dateOfBirth: DateTime(1990, 1, 1),
      gender: 'Female',
      phone: '123',
    );
    final appt = await s.walkIn(patientId: p.id, doctorId: 'USR-doc1');
    expect(appt.status, AppointmentStatus.checkedIn);
    expect(appt.tokenNumber, 3); // two seeded patients already waiting
    expect(s.doctorQueue('USR-doc1').map((a) => a.id), contains(appt.id));
    final doctor = s.userById('USR-doc1')!;
    expect(s.unreadCount(doctor), 1);

    // Doctor consults, orders tests and prescribes.
    await s.login('doctor', '1234');
    final c = await s.startConsultation(
        patientId: p.id, doctorId: doctor.id, appointmentId: appt.id);
    expect(appt.status, AppointmentStatus.inConsultation);
    final invoice = s.invoiceForConsultation(c.id)!;
    expect(invoice.totalFor(BillingDepartment.consultation), 50);

    final orders = await s.orderLabTests(
        consultationId: c.id, testIds: ['LT-cbc', 'LT-mp'], urgent: true);
    expect(orders.length, 2);
    expect(s.labQueue.take(2).map((o) => o.id), containsAll(orders.map((o) => o.id)));
    expect(invoice.totalFor(BillingDepartment.laboratory), 23);

    final stockBefore = s.medicineById('MED-para')!.stock;
    final rx = await s.prescribe(consultationId: c.id, items: [
      PrescriptionItem(
        medicineId: 'MED-para',
        medicineName: 'Paracetamol',
        dosage: '1 tablet',
        frequency: 'Three times daily',
        durationDays: 5,
        quantity: 15,
      ),
    ]);
    expect(s.pharmacyQueue.map((r) => r.id), contains(rx.id));
    final lab = s.users.firstWhere((u) => u.role == UserRole.labTechnician);
    final pharmacist = s.users.firstWhere((u) => u.role == UserRole.pharmacist);
    expect(s.notificationsFor(lab).first.title, 'URGENT lab request');
    expect(s.notificationsFor(pharmacist).first.title, 'New prescription');

    // Lab processes one test, cancels the other.
    await s.login('lab', '1234');
    await s.collectSample(orders[0].id);
    expect(orders[0].status, LabOrderStatus.sampleCollected);
    await s.enterLabResult(
        labOrderId: orders[0].id, result: 'WBC 14.2', abnormal: true);
    await s.cancelLabOrder(orders[1].id);
    expect(invoice.totalFor(BillingDepartment.laboratory), 15);
    expect(s.unreviewedResults(doctor.id).map((o) => o.id), [orders[0].id]);
    expect(s.notificationsFor(doctor).first.title, 'ABNORMAL lab result');

    // Pharmacy dispenses; stock drops and the bill grows.
    await s.login('pharmacy', '1234');
    await s.dispense(rx.id);
    expect(rx.status, PrescriptionStatus.dispensed);
    expect(s.medicineById('MED-para')!.stock, stockBefore - 15);
    expect(invoice.totalFor(BillingDepartment.pharmacy), closeTo(1.5, 1e-9));

    // Doctor completes the visit with a follow-up.
    await s.login('doctor', '1234');
    c.diagnosis = 'Infection';
    c.followUpDate = DateTime.now().add(const Duration(days: 7));
    await s.completeConsultation(c.id);
    expect(appt.status, AppointmentStatus.completed);
    expect(
        s.appointments.where((a) =>
            a.patientId == p.id && a.status == AppointmentStatus.scheduled),
        hasLength(1));

    // Reception collects payment.
    expect(invoice.total, closeTo(66.5, 1e-9));
    await s.recordPayment(invoice.id, 66.5);
    expect(invoice.isPaid, isTrue);
  });

  test('dispensing more than stock fails without side effects', () async {
    final s = await _store();
    final c = await s.startConsultation(
        patientId: s.patients.first.id, doctorId: 'USR-doc1');
    final cipro = s.medicineById('MED-cipro')!; // seeded with 15 units
    final rx = await s.prescribe(consultationId: c.id, items: [
      PrescriptionItem(
          medicineId: 'MED-para',
          medicineName: 'Paracetamol',
          dosage: '1',
          frequency: 'Once daily',
          durationDays: 1,
          quantity: 2),
      PrescriptionItem(
          medicineId: cipro.id,
          medicineName: 'Cipro',
          dosage: '1',
          frequency: 'Twice daily',
          durationDays: 10,
          quantity: 20),
    ]);
    final paraBefore = s.medicineById('MED-para')!.stock;
    await expectLater(s.dispense(rx.id), throwsA(isA<HospitalException>()));
    expect(s.medicineById('MED-para')!.stock, paraBefore);
    expect(rx.items[0].dispensedQuantity, 0);

    // Partial dispense of what is available.
    await s.dispense(rx.id, quantities: {0: 2, 1: 15});
    expect(rx.status, PrescriptionStatus.partiallyDispensed);
    expect(cipro.stock, 0);
    expect(rx.items[1].outstanding, 5);
    expect(s.pharmacyQueue, contains(rx));

    await s.restock(cipro.id, 100);
    await s.dispense(rx.id);
    expect(rx.status, PrescriptionStatus.dispensed);
  });

  test('state survives a reload from storage', () async {
    final storage = MemoryStorage();
    final s = await _store(storage);
    final p = await s.registerPatient(
        name: 'Persisted',
        dateOfBirth: DateTime(2000),
        gender: 'Male',
        phone: '9');
    final c =
        await s.startConsultation(patientId: p.id, doctorId: 'USR-doc2');
    await s.orderLabTests(consultationId: c.id, testIds: ['LT-ecg']);

    final reloaded = await _store(storage);
    expect(reloaded.patientById(p.id)!.name, 'Persisted');
    expect(reloaded.labOrdersFor(patientId: p.id).single.testName, 'ECG');
    expect(reloaded.invoiceForConsultation(c.id)!.total, 110);

    // Sequence numbers continue rather than restarting.
    final p2 = await reloaded.registerPatient(
        name: 'Next', dateOfBirth: DateTime(2000), gender: 'Male', phone: '1');
    expect(p2.mrn, isNot(p.mrn));
  });

  test('payments cannot exceed balance', () async {
    final s = await _store();
    final c = await s.startConsultation(
        patientId: s.patients.first.id, doctorId: 'USR-doc1');
    final inv = s.invoiceForConsultation(c.id)!;
    await expectLater(
        s.recordPayment(inv.id, 51), throwsA(isA<HospitalException>()));
    await s.applyDiscount(inv.id, 10);
    await s.recordPayment(inv.id, 40);
    expect(inv.isPaid, isTrue);
  });
}
