import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/data/storage.dart';
import 'package:hospital_app/models/models.dart';
import 'package:hospital_app/print/documents.dart';
import 'package:hospital_app/reports/reports.dart';

Future<HospitalStore> _store({String user = 'reception'}) async {
  final s = HospitalStore(storage: MemoryStorage());
  await s.load();
  await s.login(user, '1234');
  return s;
}

/// Two unpaid bills for one patient: consultation fees of two visits.
Future<(Patient, List<Invoice>)> _twoBills(HospitalStore s) async {
  final p = s.patients.firstWhere((p) => p.name == 'Chloe Martin');
  final bills = <Invoice>[];
  for (final doctor in ['USR-doc1', 'USR-doc3']) {
    final c = await s.startConsultation(patientId: p.id, doctorId: doctor);
    bills.add(s.invoiceForConsultation(c.id)!);
  }
  return (p, bills);
}

void main() {
  test(
    'a till must be open to take payments, and only one per cashier',
    () async {
      final s = await _store();
      final (p, bills) = await _twoBills(s);
      expect(
        () => s.takeCounterPayment(
          patientId: p.id,
          invoiceIds: [bills.first.id],
          amount: 10,
          method: 'Cash',
        ),
        throwsA(isA<HospitalException>()),
      );
      await s.openTill(openingFloat: 50);
      expect(() => s.openTill(), throwsA(isA<HospitalException>()));
      expect(s.myOpenTill!.openingFloat, 50);

      final lab = await _store(user: 'lab');
      expect(() => lab.openTill(), throwsA(isA<HospitalException>()));
    },
  );

  test(
    'one cash payment settles several bills, oldest first, with change',
    () async {
      final s = await _store();
      final (p, bills) = await _twoBills(s);
      await s.openTill(openingFloat: 20);
      final due = bills.fold<double>(0, (t, b) => t + b.patientBalance);
      expect(
        s.outstandingFor(p.id).map((b) => b.id),
        containsAll(bills.map((b) => b.id)),
      );

      final r = await s.takeCounterPayment(
        patientId: p.id,
        invoiceIds: bills.map((b) => b.id).toList(),
        amount: due,
        method: 'Cash',
        tendered: due + 15,
      );
      expect(r.receiptNo, startsWith('RCT-'));
      expect(r.payments, hasLength(2));
      expect(r.total, closeTo(due, 0.001));
      expect(r.change, closeTo(15, 0.001));
      expect(bills.every((b) => b.patientBalance.abs() < 0.005), isTrue);
      expect(r.payments.every((x) => x.tillId == s.myOpenTill!.id), isTrue);
      expect(s.expectedCash(s.myOpenTill!), closeTo(20 + due, 0.001));

      final pdf = await counterReceiptPdf(
        s,
        r.receiptNo,
        tendered: r.tendered,
        change: r.change,
      );
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    },
  );

  test('part-payments go to the oldest bill first', () async {
    final s = await _store();
    final (p, bills) = await _twoBills(s);
    await s.openTill();
    final first = bills.first.patientBalance;
    final r = await s.takeCounterPayment(
      patientId: p.id,
      invoiceIds: bills.map((b) => b.id).toList(),
      amount: first + 5,
      method: 'Cash',
      tendered: first + 5,
    );
    expect(r.payments.first.invoiceId, bills.first.id);
    expect(r.payments.first.amount, closeTo(first, 0.001));
    expect(r.payments.last.amount, closeTo(5, 0.001));
    expect(
      bills.last.patientBalance,
      closeTo(bills.last.patientDue - 5, 0.001),
    );
  });

  test('counter payment checks', () async {
    final s = await _store();
    final (p, bills) = await _twoBills(s);
    await s.openTill();
    Future<void> pay(
      double amount,
      String method, {
      double? tendered,
      String ref = '',
    }) => s.takeCounterPayment(
      patientId: p.id,
      invoiceIds: [bills.first.id],
      amount: amount,
      method: method,
      tendered: tendered,
      reference: ref,
    );
    final due = bills.first.patientBalance;
    // More than owed, not enough cash, no reference, insurance at the desk.
    expect(() => pay(due + 1, 'Cash'), throwsA(isA<HospitalException>()));
    expect(
      () => pay(due, 'Cash', tendered: due - 1),
      throwsA(isA<HospitalException>()),
    );
    expect(() => pay(due, 'Card'), throwsA(isA<HospitalException>()));
    expect(
      () => pay(due, 'Insurance', ref: 'x'),
      throwsA(isA<HospitalException>()),
    );
    await pay(due, 'Mobile money', ref: 'MM-123');
    final paid = s.payments.last;
    expect(paid.reference, 'MM-123');
    expect(paid.method, 'Mobile money');
    // Non-cash doesn't change the cash expected in the drawer.
    expect(s.expectedCash(s.myOpenTill!), 0);
  });

  test(
    'closing the till records the count; differences alert accounts',
    () async {
      final s = await _store();
      final (p, bills) = await _twoBills(s);
      final till = await s.openTill(openingFloat: 100);
      await s.takeCounterPayment(
        patientId: p.id,
        invoiceIds: [bills.first.id],
        amount: 30,
        method: 'Cash',
        tendered: 50,
      );
      expect(s.expectedCash(till), 130);
      await s.closeTill(till.id, countedCash: 125, notes: 'Short of change');
      expect(till.isOpen, isFalse);
      expect(till.expectedCash, 130);
      expect(till.variance, -5);
      expect(s.myOpenTill, isNull);
      final alert = s.notifications.last;
      expect(alert.title, 'Till short');
      expect(alert.targetRole, UserRole.accountant);
      expect(
        () => s.closeTill(till.id, countedCash: 1),
        throwsA(isA<HospitalException>()),
      );

      final pdf = await tillReportPdf(s, till);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

      // The collections report has the receipt and the till.
      final report = kReports
          .firstWhere((r) => r.id == 'collections')
          .build(s, DateTime.now(), DateTime.now());
      final tills = report.sheets.firstWhere((x) => x.name == 'Tills');
      expect(tills.rows, hasLength(1));
      final payments = report.sheets.firstWhere((x) => x.name == 'Payments');
      expect(payments.rows.last.contains(s.payments.last.receiptNo), isTrue);
    },
  );

  test('only the cashier or a manager closes a till', () async {
    final s = await _store();
    final till = await s.openTill();
    await s.logout();
    await s.login('pharmacy', '1234');
    expect(
      () => s.closeTill(till.id, countedCash: 0),
      throwsA(isA<HospitalException>()),
    );
    await s.logout();
    await s.login('accounts', '1234');
    await s.closeTill(till.id, countedCash: 0);
    expect(till.isOpen, isFalse);
  });

  test('payments on a bill go into the open till too', () async {
    final s = await _store();
    final (_, bills) = await _twoBills(s);
    final till = await s.openTill();
    await s.recordPayment(bills.first.id, 10);
    expect(s.payments.last.tillId, till.id);
    expect(s.expectedCash(till), 10);
  });
}
