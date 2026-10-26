import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/data/storage.dart';
import 'package:hospital_app/models/models.dart';
import 'package:hospital_app/print/documents.dart';
import 'package:hospital_app/reports/reports.dart';
import 'package:hospital_app/reports/xlsx.dart';

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

  group('refunds', () {
    /// Reception takes [amount] cash for one of Chloe's bills.
    Future<(Payment, Invoice)> paid(HospitalStore s, double amount) async {
      final (p, bills) = await _twoBills(s);
      s.myOpenTill ?? await s.openTill(openingFloat: 50);
      final r = await s.takeCounterPayment(
        patientId: p.id,
        invoiceIds: [bills.first.id],
        amount: amount,
        method: 'Cash',
        tendered: amount,
      );
      return (r.payments.single, bills.first);
    }

    test('a cashier asks, accounts approve, the cashier pays out', () async {
      final s = await _store();
      final (payment, bill) = await paid(s, 40);
      expect(s.refundableOn(payment), 40);
      final r = await s.requestRefund(
        payment.id,
        amount: 15,
        reason: 'Test cancelled',
      );
      expect(r.status, RefundStatus.pending);
      expect(s.notifications.last.title, 'Refund to approve');
      expect(s.refundableOn(payment), 25);
      expect(() => s.payRefund(r.id), throwsA(isA<HospitalException>()));
      expect(
        () => s.decideRefund(r.id, approve: true),
        throwsA(isA<HospitalException>()),
      );

      await s.logout();
      await s.login('accounts', '1234');
      await s.decideRefund(r.id, approve: true, note: 'OK');
      expect(r.status, RefundStatus.approved);
      expect(r.decidedBy, 'USR-acc');

      await s.logout();
      await s.login('reception', '1234');
      final till = s.myOpenTill!;
      final before = s.expectedCash(till);
      final paidBefore = bill.amountPaid;
      await s.payRefund(r.id);
      expect(r.status, RefundStatus.paid);
      expect(r.number, startsWith('RFD-'));
      expect(bill.amountPaid, closeTo(paidBefore - 15, 0.001));
      expect(s.expectedCash(till), closeTo(before - 15, 0.001));
      expect(s.tillRefunds(till.id), {'Cash': 15});
      final out = s.payments.last;
      expect(out.isRefund, isTrue);
      expect(out.amount, -15);
      expect(() => s.payRefund(r.id), throwsA(isA<HospitalException>()));

      final pdf = await refundVoucherPdf(s, r);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    });

    test('limits: not more than paid, a reason, approval rules', () async {
      final s = await _store();
      final (payment, _) = await paid(s, 20);
      expect(
        () => s.requestRefund(payment.id, amount: 25, reason: 'Paid twice'),
        throwsA(isA<HospitalException>()),
      );
      expect(
        () => s.requestRefund(payment.id, amount: 5, reason: ''),
        throwsA(isA<HospitalException>()),
      );
      final a = await s.requestRefund(
        payment.id,
        amount: 20,
        reason: 'Paid twice',
      );
      // Nothing left to refund on that payment.
      expect(
        () => s.requestRefund(payment.id, amount: 1, reason: 'Again'),
        throwsA(isA<HospitalException>()),
      );
      await s.logout();
      await s.login('accounts', '1234');
      await s.decideRefund(a.id, approve: false, note: 'Not paid twice');
      expect(a.status, RefundStatus.rejected);
      // Rejected refunds free the amount again.
      expect(s.refundableOn(payment), 20);
      // Accounts' own requests are approved at once, but not by themselves
      // later: there is nothing pending.
      final own = await s.requestRefund(
        payment.id,
        amount: 5,
        reason: 'Goodwill',
      );
      expect(own.status, RefundStatus.approved);
      expect(own.decidedBy, 'USR-acc');
    });

    test(
      'cash refunds need an open till with enough cash; others a reference',
      () async {
        final s = await _store();
        final (payment, _) = await paid(s, 30);
        await s.logout();
        await s.login('accounts', '1234');
        final cash = await s.requestRefund(
          payment.id,
          amount: 10,
          reason: 'Cancelled scan',
        );
        final card = await s.requestRefund(
          payment.id,
          amount: 5,
          reason: 'Overcharged',
          method: 'Mobile money',
        );
        expect(() => s.payRefund(cash.id), throwsA(isA<HospitalException>()));
        await s.openTill(openingFloat: 5);
        expect(() => s.payRefund(cash.id), throwsA(isA<HospitalException>()));
        expect(() => s.payRefund(card.id), throwsA(isA<HospitalException>()));
        await s.payRefund(card.id, reference: 'MM-REV-9');
        expect(card.reference, 'MM-REV-9');
        expect(s.payments.last.tillId, s.myOpenTill!.id);
      },
    );
  });

  test('day-end: takings, refunds, tills and open-till warning', () async {
    final s = await _store();
    final (p, bills) = await _twoBills(s);
    final till = await s.openTill(openingFloat: 100);
    await s.takeCounterPayment(
      patientId: p.id,
      invoiceIds: [bills.first.id],
      amount: 30,
      method: 'Cash',
      tendered: 30,
    );
    await s.takeCounterPayment(
      patientId: p.id,
      invoiceIds: [bills.last.id],
      amount: 20,
      method: 'Card',
      reference: 'C-1',
    );
    final refund = await s.requestRefund(
      s.payments
          .firstWhere((x) => x.method == 'Cash' && x.tillId == till.id)
          .id,
      amount: 10,
      reason: 'Cancelled test',
    );
    await s.logout();
    await s.login('accounts', '1234');
    await s.decideRefund(refund.id, approve: true);
    await s.logout();
    await s.login('reception', '1234');
    await s.payRefund(refund.id);

    var d = s.dayEnd(DateTime.now());
    expect(d.collected['Cash'], 30);
    expect(d.collected['Card'], 20);
    expect(d.refunded, {'Cash': 10});
    expect(d.totalCollected, 50);
    expect(d.netCash, 20);
    expect(d.net, 40);
    expect(d.refunds, [refund]);
    expect(d.openTills, [till]);

    await s.closeTill(till.id, countedCash: 118);
    d = s.dayEnd(DateTime.now());
    expect(d.openTills, isEmpty);
    expect(d.variance, -2);

    final pdf = await dayEndPdf(s, DateTime.now());
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final report = kReports
        .firstWhere((r) => r.id == 'dayend')
        .build(s, DateTime.now(), DateTime.now());
    expect(report.sheets.first.rows, hasLength(1));
    expect(report.sheets.last.rows, hasLength(1));
    // Collections and finance net the refund automatically.
    final collections = kReports
        .firstWhere((r) => r.id == 'collections')
        .build(s, DateTime.now(), DateTime.now());
    expect(
      (collections.sheets.first.totals!.last as Money).value,
      closeTo(40, 0.001),
    );
  });
}
