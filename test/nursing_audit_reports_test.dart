import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/data/storage.dart';
import 'package:hospital_app/models/models.dart';
import 'package:hospital_app/reports/reports.dart';
import 'package:hospital_app/reports/xlsx.dart';

Future<HospitalStore> _store({String? user = 'admin'}) async {
  final s = HospitalStore(storage: MemoryStorage());
  await s.load();
  if (user != null) await s.login(user, '1234');
  return s;
}

VitalsReading _v({
  double? temp,
  int? pulse,
  int? rr,
  int? sys,
  int? spo2,
  bool o2 = false,
  Consciousness c = Consciousness.alert,
}) => VitalsReading(
  id: 'v',
  admissionId: 'a',
  patientId: 'p',
  takenAt: DateTime(2026),
  temperature: temp,
  pulse: pulse,
  respRate: rr,
  systolic: sys,
  spo2: spo2,
  onOxygen: o2,
  consciousness: c,
);

Map<String, String> _unzip(List<int> bytes) => {
  for (final f in ZipDecoder().decodeBytes(bytes).files)
    f.name: utf8.decode(f.content as List<int>),
};

void main() {
  group('NEWS2', () {
    test('normal observations score 0', () {
      final n = _v(temp: 37, pulse: 72, rr: 16, sys: 120, spo2: 98).news2;
      expect(n.score, 0);
      expect(n.complete, isTrue);
      expect(n.risk, News2Risk.low);
    });

    test('a septic picture scores high', () {
      // RR 24 (2), SpO2 93 (2), BP 98 (2), HR 118 (2), T 39.4 (2) = 10.
      final n = _v(temp: 39.4, pulse: 118, rr: 24, sys: 98, spo2: 93).news2;
      expect(n.score, 10);
      expect(n.risk, News2Risk.high);
    });

    test('one parameter scoring 3 is at least low-medium', () {
      final n = _v(
        temp: 37,
        pulse: 72,
        rr: 16,
        sys: 120,
        spo2: 98,
        c: Consciousness.newConfusion,
      ).news2;
      expect(n.score, 3);
      expect(n.risk, News2Risk.lowMedium);
    });

    test('oxygen adds 2 and missing values mark it incomplete', () {
      final n = _v(spo2: 96, o2: true).news2;
      expect(n.score, 2);
      expect(n.complete, isFalse);
    });
  });

  group('nursing care', () {
    test('a high score alerts the doctor and the nurses', () async {
      final s = await _store();
      final a = s.activeAdmissions.first; // Peter, under Dr. Obi
      final v = await s.recordVitals(
        admissionId: a.id,
        temperature: 39.4,
        pulse: 118,
        respRate: 24,
        systolic: 98,
        spo2: 93,
      );
      expect(v.news2.score, 10);
      expect(
        s.notificationsFor(s.userById('USR-doc1')!).first.title,
        'Deteriorating patient',
      );
      expect(
        s.notificationsFor(s.userById('USR-nur')!).first.title,
        'Deteriorating patient',
      );
      expect(s.patientsAtRisk.single.$1.id, a.id);
      expect(s.latestVitals(a.id), v);
    });

    test('observations need a value and an active admission', () async {
      final s = await _store();
      final a = s.activeAdmissions.first;
      await expectLater(
        s.recordVitals(admissionId: a.id),
        throwsA(isA<HospitalException>()),
      );
      await s.dischargePatient(a.id);
      await expectLater(
        s.recordVitals(admissionId: a.id, pulse: 80),
        throwsA(isA<HospitalException>()),
      );
    });

    test('scheduled doses follow the order start and stop', () {
      final o = MedicationOrder(
        id: 'o',
        admissionId: 'a',
        patientId: 'p',
        medicineName: 'Ceftriaxone',
        dose: '1 g',
        route: 'IV',
        frequency: 'Three times daily',
        times: const ['08:00', '14:00', '20:00'],
        startAt: DateTime(2026, 5, 1, 10, 30),
      );
      // Started at 10:30, so the 08:00 dose that day is not due.
      expect(o.slotsOn(DateTime(2026, 5, 1)).map((d) => d.hour), [14, 20]);
      expect(o.slotsOn(DateTime(2026, 5, 2)).length, 3);
      o.stoppedAt = DateTime(2026, 5, 2, 15);
      expect(o.slotsOn(DateTime(2026, 5, 2)).map((d) => d.hour), [8, 14]);
      expect(o.slotsOn(DateTime(2026, 5, 3)), isEmpty);
    });

    test('the medication chart records each dose once', () async {
      final s = await _store();
      final a = s.activeAdmissions.first;
      final o = await s.addMedicationOrder(
        admissionId: a.id,
        medicineName: 'Paracetamol',
        dose: '1 g',
        route: 'Oral',
        frequency: 'Every 6 hours',
      );
      final prn = await s.addMedicationOrder(
        admissionId: a.id,
        medicineName: 'Ondansetron',
        dose: '4 mg',
        route: 'IV',
        frequency: 'As needed (PRN)',
      );
      // Look at tomorrow so every slot is after the order's start.
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      // Only this order's slots (the demo patient has other medicines).
      List<MarSlot> mine() =>
          s.marFor(a.id, tomorrow).where((x) => x.order.id == o.id).toList();
      final slots = mine();
      expect(slots.length, 4);

      final slot = slots[1].time;
      await s.recordDose(
        orderId: o.id,
        scheduledFor: slot,
        status: DoseStatus.given,
      );
      await expectLater(
        s.recordDose(
          orderId: o.id,
          scheduledFor: slot,
          status: DoseStatus.given,
        ),
        throwsA(isA<HospitalException>()),
      );
      await expectLater(
        s.recordDose(
          orderId: o.id,
          scheduledFor: slots[2].time,
          status: DoseStatus.refused,
        ),
        throwsA(isA<HospitalException>()), // reason required
      );
      await s.recordDose(
        orderId: o.id,
        scheduledFor: slots[2].time,
        status: DoseStatus.refused,
        notes: 'Nauseous',
      );
      expect(
        s.notificationsFor(s.userById('USR-doc1')!).first.title,
        'Dose refused',
      );
      await s.recordDose(orderId: prn.id, status: DoseStatus.given);
      final after = mine();
      expect(after[1].dose?.status, DoseStatus.given);
      expect(
        after[0].isOverdue(slots[0].time.add(const Duration(hours: 2))),
        isTrue,
      );
      expect(
        after[1].isOverdue(slots[1].time.add(const Duration(hours: 2))),
        isFalse,
      );

      await s.stopMedicationOrder(o.id);
      expect(mine(), isEmpty);
    });

    test('nursing notes are kept per admission', () async {
      final s = await _store();
      final a = s.activeAdmissions.first;
      await s.addNursingNote(
        admissionId: a.id,
        category: 'Handover',
        text: 'Pain controlled, NBM from midnight',
      );
      final note = s.notesFor(a.id).first; // newest first
      expect(note.category, 'Handover');
      expect(note.author, 'USR-admin');
    });
  });

  group('audit log', () {
    test('records sign-in and every change with old and new values', () async {
      final s = await _store(user: null);
      expect(s.auditLog, isEmpty, reason: 'demo data is not audited');
      await s.login('reception', '1234');
      expect(s.auditLog.single.action, 'signed in');

      final mary = s.patients.firstWhere((p) => p.name == 'Mary Johnson');
      mary.phone = '0800 000 0000';
      await s.updatePatient(mary);
      final edit = s.auditLog.last;
      expect(edit.action, 'updated');
      expect(edit.collection, 'patients');
      expect(edit.userName, 'Grace Reception');
      expect(edit.patientId, mary.id);
      expect(edit.summary, contains('phone: 0802 444 5566 → 0800 000 0000'));

      final appt = await s.bookAppointment(
        patientId: mary.id,
        doctorId: 'USR-doc2',
        scheduledAt: s.nextAvailableSlot('USR-doc2')!,
      );
      await s.cancelAppointment(appt.id);
      final actions = s.auditLog.map((e) => '${e.action} ${e.collection}');
      expect(
        actions,
        containsAll(['created appointments', 'updated appointments']),
      );
      // Notifications are not audited.
      expect(s.auditLog.any((e) => e.collection == 'notifications'), isFalse);
    });

    test('passwords are never written to the log', () async {
      final s = await _store();
      await s.addStaff(
        name: 'New Nurse',
        username: 'newnurse',
        password: 'hunter2',
        role: UserRole.nurse,
      );
      expect(s.auditLog.any((e) => e.summary.contains('hunter2')), isFalse);
      expect(s.auditLog.last.summary, contains('Created staff member'));
    });

    test('deletions are recorded', () async {
      final s = await _store();
      final e = await s.addExpense(
        date: DateTime.now(),
        category: 'Other',
        description: 'Flowers',
        amount: 12,
      );
      await s.deleteExpense(e.id);
      expect(s.auditLog.last.action, 'deleted');
      expect(s.auditLog.last.summary, contains('"Flowers" 12.00'));
    });
  });

  group('Excel export', () {
    test('writes a valid workbook with escaped text and typed cells', () {
      final bytes = buildXlsx([
        XlsxSheet(
          name: 'A/B: test?',
          headers: List.generate(28, (i) => 'H$i'),
          rows: [
            [
              'Fish & <chips>',
              Money(12.5),
              3,
              DateTime(2026, 1, 2, 12),
              true,
              null,
            ],
          ],
          totals: ['Total', Money(12.5)],
        ),
        XlsxSheet(name: 'A B  test ', headers: ['x'], rows: []),
      ]);
      final files = _unzip(bytes);
      expect(
        files.keys,
        containsAll([
          '[Content_Types].xml',
          'xl/workbook.xml',
          'xl/styles.xml',
          'xl/worksheets/sheet1.xml',
          'xl/worksheets/sheet2.xml',
        ]),
      );
      final wb = files['xl/workbook.xml']!;
      expect(wb, contains('name="A B  test"'));
      expect(wb, contains('name="A B  test (2)"')); // de-duplicated
      final sheet = files['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('Fish &amp; &lt;chips&gt;'));
      expect(sheet, contains('<c r="B2" s="3"><v>12.5</v></c>'));
      expect(sheet, contains('<c r="C2"><v>3</v></c>'));
      expect(sheet, contains('<c r="D2" s="2"><v>46024.500000</v></c>'));
      expect(sheet, contains('>Yes<'));
      expect(sheet, contains('r="AB1"')); // 28th column
      expect(sheet, contains('<autoFilter ref="A1:AB2"/>'));
      expect(sheet, contains('<c r="B3" s="4"><v>12.5</v></c>')); // bold total
    });

    test('every report builds for an administrator', () async {
      final s = await _store();
      final a = s.activeAdmissions.first;
      await s.recordVitals(admissionId: a.id, pulse: 90, spo2: 97);
      final from = DateTime.now().subtract(const Duration(days: 90));
      final to = DateTime.now();
      for (final d in kReports) {
        final r = d.build(s, from, to);
        final files = _unzip(
          reportXlsx(r, hospital: s.profile.name, generatedBy: 'Admin'),
        );
        expect(
          files['xl/workbook.xml'],
          contains('name="Summary"'),
          reason: d.id,
        );
        expect(
          files.keys.where((k) => k.startsWith('xl/worksheets/')).length,
          r.sheets.length + 1,
          reason: d.id,
        );
      }
    });

    test('collections report totals the payments in the period', () async {
      final s = await _store();
      final mary = s.patients.firstWhere((p) => p.name == 'Mary Johnson');
      final c = await s.startConsultation(
        patientId: mary.id,
        doctorId: 'USR-doc2',
      );
      final inv = s.invoiceForConsultation(c.id)!;
      await s.recordPayment(inv.id, 30, method: 'Card');
      await s.recordPayment(inv.id, 50, method: 'Cash');
      final today = DateTime.now();
      final r = kReports
          .firstWhere((d) => d.id == 'collections')
          .build(s, today, today);
      final payments = r.sheets.first;
      expect(payments.rows.length, 2);
      expect((payments.totals![7] as Money).value, 80);
      expect(r.summary.firstWhere((x) => x.$1 == 'Card').$2, isA<Money>());
    });

    test('roles only see their reports', () {
      Set<String> idsFor(UserRole r) => {
        for (final d in kReports)
          if (d.roles.contains(r)) d.id,
      };
      expect(idsFor(UserRole.admin).length, kReports.length);
      expect(idsFor(UserRole.labTechnician), {'lab'});
      expect(idsFor(UserRole.pharmacist), {'stock'});
      expect(idsFor(UserRole.nurse), {'admissions'});
      expect(idsFor(UserRole.receptionist).contains('payroll'), isFalse);
      expect(idsFor(UserRole.accountant).contains('audit'), isFalse);
    });
  });
}
