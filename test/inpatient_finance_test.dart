import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/data/storage.dart';
import 'package:hospital_app/models/models.dart';

Future<HospitalStore> _store() async {
  final s = HospitalStore(storage: MemoryStorage());
  await s.load();
  return s;
}

Patient _patient(HospitalStore s, String name) =>
    s.patients.firstWhere((p) => p.name == name);

void main() {
  group('room charges', () {
    final now = DateTime(2026, 10, 26, 15);

    Admission admission(List<(String, double, DateTime, DateTime?)> stays) =>
        Admission(
          id: 'a',
          patientId: 'p',
          doctorId: 'd',
          admittedAt: stays.first.$3,
          stays: [
            for (final (room, rate, from, to) in stays)
              RoomStay(
                roomId: room,
                roomName: room,
                dailyRate: rate,
                from: from,
                to: to,
              ),
          ],
        );

    test('a same-day stay is charged one day', () {
      final a = admission([('Ward', 40, DateTime(2026, 10, 26, 9), null)]);
      expect(a.billableDays(now), [1]);
      expect(a.roomCharges(now), 40);
    });

    test(
      'each midnight is charged at the rate of the room it was spent in',
      () {
        final a = admission([
          ('Ward', 40, DateTime(2026, 10, 23, 22), DateTime(2026, 10, 25, 8)),
          ('Private', 150, DateTime(2026, 10, 25, 8), null),
        ]);
        expect(a.billableDays(now), [2, 1]);
        expect(a.roomCharges(now), 2 * 40 + 150);
        expect(a.totalDays(now), 3);
      },
    );

    test('discharge bills the stay on the admission invoice', () async {
      final s = await _store();
      final peter = _patient(s, 'Peter Okafor'); // admitted 2 days ago
      final a = s.activeAdmissionFor(peter.id)!;
      await s.dischargePatient(a.id, summary: 'Recovered');
      final inv = s.invoiceForAdmission(a.id)!;
      expect(inv.totalFor(BillingDepartment.room), 80);
      expect(inv.lines.single.description, 'General Ward A – 2 day(s)');
      expect(s.activeAdmissionFor(peter.id), isNull);
      expect(s.occupiedBeds('RM-gwa'), 0);
    });

    test(
      'admission respects bed capacity and one admission per patient',
      () async {
        final s = await _store();
        final mary = _patient(s, 'Mary Johnson');
        final ali = _patient(s, 'Ali Hassan');
        await s.admitPatient(
          patientId: mary.id,
          roomId: 'RM-101',
          doctorId: 'USR-doc1',
        );
        expect(s.freeBeds('RM-101'), 0);
        await expectLater(
          s.admitPatient(
            patientId: ali.id,
            roomId: 'RM-101',
            doctorId: 'USR-doc1',
          ),
          throwsA(isA<HospitalException>()),
        );
        await expectLater(
          s.admitPatient(
            patientId: mary.id,
            roomId: 'RM-gwa',
            doctorId: 'USR-doc1',
          ),
          throwsA(isA<HospitalException>()),
        );
      },
    );

    test('transfer moves the patient and frees the old bed', () async {
      final s = await _store();
      final mary = _patient(s, 'Mary Johnson');
      final a = await s.admitPatient(
        patientId: mary.id,
        roomId: 'RM-gwb',
        doctorId: 'USR-doc1',
      );
      await s.transferRoom(a.id, 'RM-icu');
      expect(a.stays.length, 2);
      expect(s.occupiedBeds('RM-gwb'), 0);
      expect(s.occupiedBeds('RM-icu'), 1);
      // Same-day admission and transfer: one day, at the ICU rate.
      await s.dischargePatient(a.id);
      expect(s.invoiceForAdmission(a.id)!.total, 300);
    });
  });

  group('operation theatre', () {
    test('overlapping bookings in one theatre are refused', () async {
      final s = await _store();
      final booked = s.surgeries.single; // OT-1 tomorrow 09:00 for 90 min
      await expectLater(
        s.scheduleSurgery(
          patientId: _patient(s, 'Mary Johnson').id,
          surgeonId: 'USR-doc2',
          theatreId: 'OT-1',
          procedure: 'Hernia repair',
          scheduledAt: booked.scheduledAt.add(const Duration(minutes: 60)),
        ),
        throwsA(isA<HospitalException>()),
      );
      // Same time in the other theatre is fine.
      await s.scheduleSurgery(
        patientId: _patient(s, 'Mary Johnson').id,
        surgeonId: 'USR-doc2',
        theatreId: 'OT-2',
        procedure: 'Hernia repair',
        scheduledAt: booked.scheduledAt,
      );
    });

    test('completing an inpatient surgery bills the admission', () async {
      final s = await _store();
      final surgery = s.surgeries.single;
      await s.startSurgery(surgery.id);
      await s.completeSurgery(surgery.id, consumablesCost: 50);
      final inv = s.invoiceForAdmission(surgery.admissionId!)!;
      // 1 h minimum × 200 + surgeon 400 + anaesthesia 150 + consumables 50.
      expect(inv.totalFor(BillingDepartment.surgery), 800);
      expect(inv.lines.length, 4);
      expect(surgery.status, SurgeryStatus.completed);
    });

    test('a day case gets its own invoice', () async {
      final s = await _store();
      final mary = _patient(s, 'Mary Johnson');
      final surgery = await s.scheduleSurgery(
        patientId: mary.id,
        surgeonId: 'USR-doc2',
        theatreId: 'OT-2',
        procedure: 'Excision of cyst',
        scheduledAt: DateTime.now(),
        surgeonFee: 120,
      );
      expect(surgery.admissionId, isNull);
      await s.startSurgery(surgery.id);
      await s.completeSurgery(surgery.id);
      final inv = s.invoiceForSurgery(surgery.id)!;
      expect(inv.patientId, mary.id);
      expect(inv.total, 120 + 120); // 1 h of OT 2 + surgeon fee
    });

    test('a patient cannot be discharged mid-surgery', () async {
      final s = await _store();
      final surgery = s.surgeries.single;
      await s.startSurgery(surgery.id);
      await expectLater(
        s.dischargePatient(surgery.admissionId!),
        throwsA(isA<HospitalException>()),
      );
    });
  });

  group('payroll and leave', () {
    test(
      'generates payslips once per month and deducts unpaid leave',
      () async {
        final s = await _store();
        final month = DateTime(2030, 6); // 30 days
        await s.setSalary(
          'USR-nur',
          basic: 1500,
          allowances: 300,
          deductions: 100,
        );
        final leave = await s.requestLeave(
          staffId: 'USR-nur',
          type: LeaveType.unpaid,
          from: DateTime(2030, 5, 30),
          to: DateTime(2030, 6, 2), // 2 of these days fall in June
        );
        await s.decideLeave(leave.id, approve: true);
        await s.setStaffActive('USR-sup2', false);

        final created = await s.generatePayroll(month);
        final staffWithPay = s.activeStaff
            .where((u) => (s.salaryFor(u.id)?.basic ?? 0) > 0)
            .length;
        expect(created, staffWithPay);
        expect(
          s.payslipsFor(month).any((p) => p.staffId == 'USR-sup2'),
          isFalse,
        );

        final nurse = s
            .payslipsFor(month)
            .firstWhere((p) => p.staffId == 'USR-nur');
        expect(nurse.unpaidLeaveDays, 2);
        expect(nurse.leaveDeduction, 100); // 1500 / 30 × 2
        expect(nurse.net, 1500 + 300 - 100 - 100);

        await expectLater(
          s.generatePayroll(month),
          throwsA(isA<HospitalException>()),
        );
        await s.markPayslipPaid(nurse.id);
        final f = s.financeFor(month);
        expect(f.payrollPaid, nurse.net);
        expect(f.payrollPending, greaterThan(0));
      },
    );

    test(
      'leave requests notify the admin and the decision the requester',
      () async {
        final s = await _store();
        final l = await s.requestLeave(
          staffId: 'USR-pha',
          type: LeaveType.sick,
          from: DateTime.now(),
          to: DateTime.now(),
        );
        final admin = s.userById('USR-admin')!;
        expect(s.notificationsFor(admin).first.title, 'Leave request');
        await s.decideLeave(l.id, approve: false);
        final pharmacist = s.userById('USR-pha')!;
        expect(s.notificationsFor(pharmacist).first.title, 'Leave declined');
        expect(s.pendingLeaves.contains(l), isFalse);
      },
    );
  });

  group('finance', () {
    test('monthly summary counts billing, payments and expenses', () async {
      final s = await _store();
      final now = DateTime.now();
      final before = s.financeFor(now);

      final c = await s.startConsultation(
        patientId: _patient(s, 'Mary Johnson').id,
        doctorId: 'USR-doc2',
      );
      final inv = s.invoiceForConsultation(c.id)!;
      await s.recordPayment(inv.id, 30, method: 'Card');
      await s.recordPayment(inv.id, 50, method: 'Cash');
      await s.addExpense(
        date: now,
        category: 'Utilities',
        description: 'Water',
        amount: 120,
      );

      final after = s.financeFor(now);
      expect(
        after.billedByDepartment[BillingDepartment.consultation]! -
            before.billedByDepartment[BillingDepartment.consultation]!,
        closeTo(80, 1e-9),
      );
      expect(after.collected - before.collected, closeTo(80, 1e-9));
      expect(after.collectedByMethod['Card'], 30);
      expect(after.expenses - before.expenses, closeTo(120, 1e-9));
      expect(s.paymentsFor(inv.id).length, 2);
      expect(inv.isPaid, isTrue);
    });
  });

  group('staff', () {
    test('support staff and inactive staff cannot sign in', () async {
      final s = await _store();
      await expectLater(s.login('', ''), throwsA(isA<HospitalException>()));
      await s.login('admin', '1234');
      await s.setStaffActive('USR-nur', false);
      await s.logout();
      await expectLater(
        s.login('nurse', '1234'),
        throwsA(isA<HospitalException>()),
      );
      await s.login('accounts', '1234');
      expect(s.currentUser!.role, UserRole.accountant);
    });
  });
}
