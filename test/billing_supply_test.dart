import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/data/storage.dart';
import 'package:hospital_app/models/models.dart';
import 'package:hospital_app/print/documents.dart';

Future<HospitalStore> _store() async {
  final s = HospitalStore(storage: MemoryStorage());
  await s.load();
  return s;
}

Patient _patient(HospitalStore s, String name) =>
    s.patients.firstWhere((p) => p.name == name);

void main() {
  group('insurance billing', () {
    test('an insured patient’s bill is split by the policy', () async {
      final s = await _store();
      final ali = _patient(s, 'Ali Hassan'); // AXA: 80%, limit 2000
      final c = await s.startConsultation(
        patientId: ali.id,
        doctorId: 'USR-doc2', // fee 80
      );
      final inv = s.invoiceForConsultation(c.id)!;
      expect(inv.insurerId, 'INS-axa');
      expect(inv.insurerShare, 64);
      expect(inv.patientDue, 16);

      // The patient can only pay their own share at the desk.
      await expectLater(
        s.recordPayment(inv.id, 20),
        throwsA(isA<HospitalException>()),
      );
      await s.recordPayment(inv.id, 16, method: 'Card');
      expect(inv.patientBalance, 0);
      expect(inv.isPaid, isFalse); // insurer hasn't paid yet
    });

    test('coverage limit caps the insurer share', () async {
      final s = await _store();
      final mary = _patient(s, 'Mary Johnson');
      mary.insurerId = 'INS-acme'; // 100%, limit 500
      final a = await s.admitPatient(
        patientId: mary.id,
        roomId: 'RM-icu', // 300/day
        doctorId: 'USR-doc1',
      );
      final inv = s.invoiceForAdmission(a.id)!;
      inv.lines.add(
        InvoiceLine(
          id: 'x',
          department: BillingDepartment.room,
          description: 'ICU',
          quantity: 3,
          unitPrice: 300,
        ),
      );
      expect(inv.insurerShare, 500);
      expect(inv.patientDue, 400);
    });

    test(
      'claim lifecycle: partial approval moves the shortfall to the patient',
      () async {
        final s = await _store();
        final ali = _patient(s, 'Ali Hassan');
        final c = await s.startConsultation(
          patientId: ali.id,
          doctorId: 'USR-doc2',
        );
        await s.orderLabTests(
          consultationId: c.id,
          testIds: ['LT-lipid'],
        ); // 25
        final inv = s.invoiceForConsultation(c.id)!; // total 105, AXA 80% = 84
        final claim = await s.createClaim(inv.id);
        expect(claim.amountClaimed, 84);
        expect(claim.number, startsWith('CLM-'));
        await expectLater(
          s.createClaim(inv.id),
          throwsA(isA<HospitalException>()),
        );

        await s.submitClaim(claim.id, reference: 'AXA-REF-1');
        await s.decideClaim(claim.id, approvedAmount: 60);
        expect(claim.status, ClaimStatus.approved);
        expect(inv.insurerCovered, 60);
        expect(inv.patientDue, 45); // 105 - 60

        await s.recordInsurerPayment(claim.id, 60);
        expect(claim.status, ClaimStatus.paid);
        expect(inv.insurerBalance, 0);
        await s.recordPayment(inv.id, 45, method: 'Cash');
        expect(inv.isPaid, isTrue);

        final collected = s.financeFor(DateTime.now()).collectedByMethod;
        expect(collected['Insurance'], 60);
        expect(s.paymentsFor(inv.id).where((p) => p.fromInsurer).length, 1);
      },
    );

    test('a rejected claim leaves the whole bill to the patient', () async {
      final s = await _store();
      final ali = _patient(s, 'Ali Hassan');
      final c = await s.startConsultation(
        patientId: ali.id,
        doctorId: 'USR-doc2',
      );
      final inv = s.invoiceForConsultation(c.id)!;
      final claim = await s.createClaim(inv.id);
      await s.submitClaim(claim.id);
      await s.decideClaim(claim.id, approvedAmount: 0);
      expect(claim.status, ClaimStatus.rejected);
      expect(inv.patientDue, inv.total);
      // A rejected claim no longer blocks changing the insurer.
      await s.setInvoiceInsurer(inv.id, null);
      expect(inv.insurerShare, 0);
    });

    test('claims wait for discharge so room charges are included', () async {
      final s = await _store();
      final ali = _patient(s, 'Ali Hassan');
      final a = await s.admitPatient(
        patientId: ali.id,
        roomId: 'RM-101',
        doctorId: 'USR-doc1',
      );
      final inv = s.invoiceForAdmission(a.id)!;
      await expectLater(
        s.createClaim(inv.id),
        throwsA(isA<HospitalException>()),
      );
      await s.dischargePatient(a.id);
      final claim = await s.createClaim(inv.id);
      expect(claim.amountClaimed, 150 * 0.8);
    });

    test('expired policies are not applied', () async {
      final s = await _store();
      final ali = _patient(s, 'Ali Hassan');
      ali.policyExpiry = DateTime.now().subtract(const Duration(days: 1));
      final c = await s.startConsultation(
        patientId: ali.id,
        doctorId: 'USR-doc1',
      );
      expect(s.invoiceForConsultation(c.id)!.insurerId, isNull);
    });
  });

  group('pharmacy purchasing', () {
    test('low-stock medicines are suggested for reorder', () async {
      final s = await _store();
      final ids = s.reorderSuggestions().map((i) => i.medicineId).toSet();
      expect(ids, containsAll(['MED-cipro', 'MED-ors'])); // seeded low
      final cipro = s.reorderSuggestions().firstWhere(
        (i) => i.medicineId == 'MED-cipro',
      );
      expect(cipro.quantity, 30 * 2 - 15);
      expect(cipro.unitCost, s.medicineById('MED-cipro')!.costPrice);
    });

    test('receiving in parts adds stock, costs and batch details', () async {
      final s = await _store();
      final para = s.medicineById('MED-para')!;
      final before = para.stock;
      final po = await s.createPurchaseOrder(
        supplierId: 'SUP-med',
        items: [
          PurchaseItem(
            medicineId: para.id,
            medicineName: para.displayName,
            quantity: 1000,
            unitCost: 0.05,
          ),
        ],
      );
      await expectLater(
        s.receiveGoods(po.id, {0: (100, 'B1', null)}),
        throwsA(isA<HospitalException>()), // not ordered yet
      );
      await s.placePurchaseOrder(po.id);
      final soon = DateTime.now().add(const Duration(days: 200));
      await s.receiveGoods(po.id, {0: (400, 'B1', soon)}, deliveryNote: 'DN-1');
      expect(po.status, PurchaseStatus.partiallyReceived);
      expect(para.stock, before + 400);
      expect(para.costPrice, 0.05);
      expect(para.expiryDate, soon); // earlier than the existing stock
      await expectLater(
        s.receiveGoods(po.id, {0: (601, 'B2', null)}),
        throwsA(isA<HospitalException>()),
      );
      await s.receiveGoods(po.id, {0: (600, 'B2', null)});
      expect(po.status, PurchaseStatus.received);
      expect(po.receipts.length, 2);
      expect(po.receipts.first.lines.single.batchNumber, 'B1');
      await expectLater(
        s.cancelPurchaseOrder(po.id),
        throwsA(isA<HospitalException>()),
      );
    });

    test(
      'paying a supplier records the delivered value as an expense',
      () async {
        final s = await _store();
        final bill = s.unpaidSupplierBills.single; // seeded delivered order
        final spentBefore = s.financeFor(DateTime.now()).expenses;
        await s.paySupplier(bill.id);
        expect(bill.isPaid, isTrue);
        final e = s.expenses.firstWhere((e) => e.id == bill.expenseId);
        expect(e.amount, bill.receivedValue);
        expect(e.vendor, 'MedSupply Ltd');
        expect(
          s.financeFor(DateTime.now()).expenses - spentBefore,
          closeTo(bill.receivedValue, 1e-9),
        );
        expect(s.unpaidSupplierBills, isEmpty);
        await expectLater(
          s.paySupplier(bill.id),
          throwsA(isA<HospitalException>()),
        );
      },
    );
  });

  group('printable documents', () {
    bool isPdf(Uint8List b) =>
        b.length > 500 && String.fromCharCodes(b.take(5)) == '%PDF-';

    test('every document type renders', () async {
      final s = await _store();
      final john = _patient(s, 'John Adeyemi');
      final inv = s.invoices.firstWhere((i) => i.patientId == john.id);
      final rx = s.prescriptions.first;

      // A discharged admission, a claim and a payslip to print.
      final peter = s.activeAdmissions.first;
      await s.dischargePatient(
        peter.id,
        summary: 'Recovered – review in 2 weeks',
      );
      final ali = _patient(s, 'Ali Hassan');
      final c = await s.startConsultation(
        patientId: ali.id,
        doctorId: 'USR-doc2',
      );
      final claim = await s.createClaim(s.invoiceForConsultation(c.id)!.id);

      final docs = {
        'invoice': await invoicePdf(s, inv),
        'receipt': await paymentReceiptPdf(s, s.paymentsFor(inv.id).first),
        'claim': await claimPdf(s, claim),
        'prescription': await prescriptionPdf(s, rx),
        'lab report': await labReportPdf(s, s.labOrdersFor(patientId: john.id)),
        'discharge': await dischargeSummaryPdf(s, peter),
        'payslip': await payslipPdf(s, s.payslips.first),
        'purchase order': await purchaseOrderPdf(s, s.purchaseOrders.first),
      };
      for (final MapEntry(key: name, value: bytes) in docs.entries) {
        expect(isPdf(bytes), isTrue, reason: name);
      }
    });
  });
}
