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

bool _notified(HospitalStore s, UserRole role, String title) =>
    s.notifications.any((n) => n.targetRole == role && n.title.contains(title));

void main() {
  group('emergency department', () {
    test('arrival, triage, doctor and admission', () async {
      final s = await _store();
      await s.login('reception', '1234');
      final john = _patient(s, 'John Adeyemi');
      final v = await s.registerEmergency(
        patientId: john.id,
        complaint: 'Chest pain',
        arrivalMode: 'Ambulance',
      );
      expect(v.status, EmergencyStatus.waitingTriage);
      expect(_notified(s, UserRole.nurse, 'Emergency arrival'), isTrue);
      await expectLater(
        s.registerEmergency(patientId: john.id, complaint: 'Again'),
        throwsA(isA<HospitalException>()),
      );

      await s.login('nurse', '1234');
      await s.triageEmergency(
        v.id,
        level: TriageLevel.veryUrgent,
        pulse: 118,
        systolic: 92,
        diastolic: 60,
        spo2: 91,
      );
      expect(v.status, EmergencyStatus.waitingDoctor);
      expect(v.seeBy, v.triagedAt!.add(const Duration(minutes: 10)));
      expect(_notified(s, UserRole.doctor, 'ORANGE'), isTrue);
      // Higher categories come first (Mary is the demo "urgent" patient).
      final mary = s.emergencyBoard.firstWhere((e) => e.id != v.id);
      expect(mary.triageLevel, TriageLevel.urgent);
      expect(s.emergencyBoard.first.id, v.id);

      await s.login('doctor', '1234');
      final doctor = s.currentUser!;
      final c = await s.seeEmergencyPatient(v.id, doctorId: doctor.id);
      expect(v.status, EmergencyStatus.beingSeen);
      expect(c.vitals.bloodPressure, '92/60');
      expect(c.complaints, 'Chest pain');
      final inv = s.invoiceForConsultation(c.id)!;
      expect(inv.totalFor(BillingDepartment.emergency), s.profile.emergencyFee);
      // Seeing again returns the same consultation.
      expect((await s.seeEmergencyPatient(v.id, doctorId: doctor.id)).id, c.id);

      await expectLater(
        s.closeEmergency(v.id, outcome: EmergencyOutcome.admitted),
        throwsA(isA<HospitalException>()),
      );
      await s.closeEmergency(
        v.id,
        outcome: EmergencyOutcome.admitted,
        roomId: 'RM-icu',
        notes: 'Acute coronary syndrome',
      );
      expect(v.isOpen, isFalse);
      final a = s.activeAdmissionFor(john.id)!;
      expect(v.admissionId, a.id);
      expect(a.doctorId, doctor.id);
      expect(s.consultationById(c.id)!.isOpen, isFalse);
      expect(s.consultationById(c.id)!.diagnosis, 'Acute coronary syndrome');
    });

    test('unknown patients and leaving without being seen', () async {
      final s = await _store();
      await s.login('nurse', '1234');
      final p = await s.registerUnknownPatient(
        gender: 'Female',
        estimatedAge: 40,
      );
      expect(p.name, startsWith('Unknown female'));
      expect(p.age, anyOf(39, 40));
      final v = await s.registerEmergency(
        patientId: p.id,
        complaint: 'Collapse',
      );
      await s.closeEmergency(
        v.id,
        outcome: EmergencyOutcome.leftWithoutBeingSeen,
      );
      expect(v.outcome, EmergencyOutcome.leftWithoutBeingSeen);
      expect(s.emergencyClosedOn(DateTime.now()), contains(v));
    });

    test('overdue once the triage target passes', () {
      final arrived = DateTime(2026, 10, 26, 10);
      final v = EmergencyVisit(
        id: 'v',
        patientId: 'p',
        arrivedAt: arrived,
        complaint: 'x',
        status: EmergencyStatus.waitingDoctor,
        triageLevel: TriageLevel.urgent,
        triagedAt: arrived,
      );
      expect(v.overdue(arrived.add(const Duration(minutes: 59))), isFalse);
      expect(v.overdue(arrived.add(const Duration(minutes: 61))), isTrue);
      final json = EmergencyVisit.fromJson(v.toJson()).toJson();
      expect(json, v.toJson());
    });
  });

  group('radiology', () {
    test('request, bill, perform, report and review', () async {
      final s = await _store();
      await s.login('doctor', '1234');
      final doctor = s.currentUser!;
      final mary = _patient(s, 'Mary Johnson');
      final c = await s.startConsultation(
        patientId: mary.id,
        doctorId: doctor.id,
      );
      final orders = await s.orderImaging(
        consultationId: c.id,
        studyIds: ['IS-cxr', 'IS-usabd'],
        urgent: true,
        clinicalNotes: 'Cough for 2 weeks',
      );
      expect(orders, hasLength(2));
      final inv = s.invoiceForConsultation(c.id)!;
      expect(inv.totalFor(BillingDepartment.radiology), 40 + 60);
      expect(_notified(s, UserRole.radiographer, 'URGENT imaging'), isTrue);
      expect(s.imagingQueue.take(2).every((o) => o.urgent), isTrue);

      await s.login('radiology', '1234');
      final xray = orders.first;
      await expectLater(
        s.reportImaging(xray.id, findings: '', impression: 'Normal'),
        throwsA(isA<HospitalException>()),
      );
      await s.markImagingPerformed(xray.id);
      expect(xray.radiographerId, s.currentUser!.id);
      await s.reportImaging(
        xray.id,
        findings: 'Right lower zone consolidation',
        impression: 'Right lower lobe pneumonia',
        abnormal: true,
      );
      expect(xray.status, ImagingStatus.reported);
      expect(
        s.notifications.any(
          (n) =>
              n.targetUserId == doctor.id &&
              n.title == 'ABNORMAL imaging report',
        ),
        isTrue,
      );

      // The ultrasound isn't needed after all.
      await s.cancelImagingOrder(orders.last.id);
      expect(inv.totalFor(BillingDepartment.radiology), 40);
      await expectLater(
        s.cancelImagingOrder(xray.id),
        throwsA(isA<HospitalException>()),
      );

      await s.login('doctor', '1234');
      expect(s.unreviewedImaging(doctor.id), [xray]);
      await s.markImagingReviewed(xray.id);
      expect(s.unreviewedImaging(doctor.id), isEmpty);
    });

    test('booking a time', () async {
      final s = await _store();
      await s.login('doctor', '1234');
      final c = await s.startConsultation(
        patientId: _patient(s, 'Ali Hassan').id,
        doctorId: s.currentUser!.id,
      );
      final o = (await s.orderImaging(
        consultationId: c.id,
        studyIds: ['IS-mrbrain'],
      )).single;
      final at = DateTime.now().add(const Duration(days: 2));
      await s.scheduleImaging(o.id, at);
      expect(o.status, ImagingStatus.scheduled);
      expect(o.scheduledAt, at);
    });
  });

  group('blood bank', () {
    test('ABO and Rh compatibility', () {
      const rc = BloodComponent.redCells;
      const ffp = BloodComponent.plasma;
      expect(bloodCompatible('O-', 'AB+', rc), isTrue);
      expect(bloodCompatible('O-', 'A-', rc), isTrue);
      expect(bloodCompatible('O+', 'A-', rc), isFalse);
      expect(bloodCompatible('A+', 'O+', rc), isFalse);
      expect(bloodCompatible('B-', 'AB-', rc), isTrue);
      expect(bloodCompatible('AB+', 'AB+', rc), isTrue);
      // Plasma is the other way round: AB is the universal donor.
      expect(bloodCompatible('AB+', 'O-', ffp), isTrue);
      expect(bloodCompatible('O+', 'A+', ffp), isFalse);
      expect(bloodCompatible('A-', 'A+', ffp), isTrue);
      // Whole blood needs the same ABO group.
      expect(bloodCompatible('O+', 'A+', BloodComponent.wholeBlood), isFalse);
      expect(bloodCompatible('A-', 'A+', BloodComponent.wholeBlood), isTrue);
      expect(bloodCompatible('X', 'A+', rc), isFalse);
    });

    test('donation, screening and the donation interval', () async {
      final s = await _store();
      await s.login('lab', '1234');
      final emeka = s.bloodDonors.firstWhere((d) => d.name == 'Emeka Nnamdi');
      final bisi = s.bloodDonors.firstWhere((d) => d.name == 'Bisi Alade');
      await expectLater(
        s.recordDonation(bisi.id),
        throwsA(isA<HospitalException>()),
      ); // donated 20 days ago
      final before = s.usableBloodUnits(bloodGroup: 'O-').length;
      final u = await s.recordDonation(emeka.id);
      expect(u.status, BloodUnitStatus.quarantine);
      expect(u.unitNumber, startsWith('BU-'));
      expect(u.expiresAt, u.collectedAt.add(const Duration(days: 35)));
      expect(emeka.canDonateOn(DateTime.now()), isFalse);
      expect(s.usableBloodUnits(bloodGroup: 'O-').length, before);
      await s.screenBloodUnit(u.id, passed: true);
      expect(s.usableBloodUnits(bloodGroup: 'O-').length, before + 1);

      final quarantined = s.bloodUnits.firstWhere(
        (x) => x.status == BloodUnitStatus.quarantine,
      );
      await expectLater(
        s.screenBloodUnit(quarantined.id, passed: false),
        throwsA(isA<HospitalException>()),
      );
      await s.screenBloodUnit(
        quarantined.id,
        passed: false,
        reason: 'HBsAg reactive',
      );
      expect(quarantined.status, BloodUnitStatus.discarded);
    });

    test('request, cross-match, issue and bill to the admission', () async {
      final s = await _store();
      await s.login('doctor', '1234');
      final peter = _patient(s, 'Peter Okafor'); // inpatient, group unknown
      final r = await s.requestBlood(
        patientId: peter.id,
        doctorId: s.currentUser!.id,
        component: BloodComponent.redCells,
        units: 2,
        urgency: 'Urgent',
        indication: 'Hb 6.8 g/dL after surgery',
      );
      expect(r.admissionId, s.activeAdmissionFor(peter.id)!.id);
      expect(_notified(s, UserRole.labTechnician, 'URGENT blood'), isTrue);

      await s.login('lab', '1234');
      final oPos = s.usableBloodUnits(
        bloodGroup: 'O+',
        component: BloodComponent.redCells,
      );
      await expectLater(
        s.crossmatchBlood(r.id, [oPos[0].id, oPos[1].id]),
        throwsA(isA<HospitalException>()),
      ); // group not known yet
      await s.setPatientBloodGroup(peter.id, 'A-');
      // A- may only get Rh-negative cells: the O+ units are refused.
      await expectLater(
        s.crossmatchBlood(r.id, [oPos[0].id, oPos[1].id]),
        throwsA(isA<HospitalException>()),
      );
      final compatible = s.compatibleUnits(r.id);
      expect(compatible.map((u) => u.bloodGroup).toSet(), {'O-'});
      await s.crossmatchBlood(r.id, [for (final u in compatible) u.id]);
      expect(r.status, BloodRequestStatus.reserved);
      expect(
        compatible.every((u) => u.status == BloodUnitStatus.reserved),
        isTrue,
      );
      expect(s.compatibleUnits(r.id), isEmpty);

      await s.issueBlood(r.id);
      expect(r.status, BloodRequestStatus.issued);
      expect(compatible.every((u) => u.patientId == peter.id), isTrue);
      final inv = s.invoiceForAdmission(r.admissionId!)!;
      expect(
        inv.totalFor(BillingDepartment.bloodBank),
        2 * BloodComponent.redCells.fee,
      );
    });

    test('cancelling or discarding returns reserved units', () async {
      final s = await _store();
      await s.login('doctor', '1234');
      final ali = _patient(s, 'Ali Hassan'); // B+
      final r = await s.requestBlood(
        patientId: ali.id,
        doctorId: s.currentUser!.id,
        component: BloodComponent.redCells,
        units: 1,
        indication: 'Anaemia',
      );
      await s.login('lab', '1234');
      final unit = s.compatibleUnits(r.id).first;
      expect(unit.bloodGroup, 'B+'); // same group preferred
      await s.crossmatchBlood(r.id, [unit.id]);
      await s.discardBloodUnit(unit.id, 'Bag leaking');
      expect(unit.status, BloodUnitStatus.discarded);
      expect(r.status, BloodRequestStatus.pending);
      expect(r.unitIds, isEmpty);

      final other = s.compatibleUnits(r.id).first;
      await s.crossmatchBlood(r.id, [other.id]);
      await s.cancelBloodRequest(r.id, reason: 'Transfused elsewhere');
      expect(other.status, BloodUnitStatus.available);
      expect(other.requestId, isNull);
    });

    test('stock table counts only usable units', () async {
      final s = await _store();
      final stock = s.bloodStock;
      expect(stock['O+']![BloodComponent.redCells], 4);
      expect(stock['AB+']![BloodComponent.plasma], 2);
      // The fresh A+ donation is still in quarantine.
      expect(stock['A+']![BloodComponent.wholeBlood], 0);
      // Platelets keep 5 days; the demo unit is 3 days old.
      expect(s.expiringBloodUnits().map((u) => u.component), [
        BloodComponent.platelets,
      ]);
    });
  });

  group('general store', () {
    test('requisition, partial issue and stock card', () async {
      final s = await _store();
      await s.login('nurse', '1234');
      final r = await s.createRequisition(
        department: 'Wards',
        quantities: {'ST-syr5': 100, 'ST-sheets': 20, 'ST-bleach': 0},
      );
      expect(r.number, startsWith('REQ-'));
      expect(r.lines, hasLength(2));
      expect(_notified(s, UserRole.storekeeper, 'Store requisition'), isTrue);
      await expectLater(
        s.createRequisition(department: 'Wards', quantities: {}),
        throwsA(isA<HospitalException>()),
      );

      await s.login('stores', '1234');
      final syringes = s.storeItemById('ST-syr5')!;
      final sheets = s.storeItemById('ST-sheets')!;
      await s.issueRequisition(r.id, quantities: {0: 100, 1: 5});
      expect(r.status, RequisitionStatus.partlyIssued);
      expect(syringes.stock, 1400);
      expect(sheets.stock, 115);
      await s.issueRequisition(r.id);
      expect(r.status, RequisitionStatus.issued);
      expect(sheets.stock, 100);
      final card = s.stockCard(sheets.id);
      expect(card.map((m) => m.quantity), [-15, -5]);
      expect(card.first.balance, 100);
      // Not for a patient: nothing billed.
      expect(
        s.invoices.any(
          (i) => i.lines.any((l) => l.department == BillingDepartment.supplies),
        ),
        isFalse,
      );
    });

    test('short stock fails without changing anything', () async {
      final s = await _store();
      await s.login('nurse', '1234');
      final r = await s.createRequisition(
        department: 'Wards',
        quantities: {'ST-gloves': 5, 'ST-cannula': 500},
      );
      await s.login('stores', '1234');
      await expectLater(
        s.issueRequisition(r.id),
        throwsA(isA<HospitalException>()),
      );
      expect(s.storeItemById('ST-gloves')!.stock, 60);
      expect(r.lines.first.issuedQuantity, 0);
      expect(r.status, RequisitionStatus.pending);
    });

    test('billable items issued for a patient go on their bill', () async {
      final s = await _store();
      await s.login('nurse', '1234');
      final peter = _patient(s, 'Peter Okafor');
      final r = await s.createRequisition(
        department: 'Wards',
        patientId: peter.id,
        quantities: {'ST-cannula': 2, 'ST-gauze': 1},
      );
      await s.login('stores', '1234');
      await s.issueRequisition(r.id);
      final inv = s.invoiceForAdmission(s.activeAdmissionFor(peter.id)!.id)!;
      // Cannulas are billable; gauze isn't.
      expect(inv.totalFor(BillingDepartment.supplies), 2 * 2.5);
      // 88 left is below the reorder level of 100.
      expect(_notified(s, UserRole.storekeeper, 'Store item low'), isTrue);
    });

    test('receiving, counting, rejecting and withdrawing', () async {
      final s = await _store();
      await s.login('stores', '1234');
      final bleach = s.storeItemById('ST-bleach')!;
      await s.receiveStoreStock(
        bleach.id,
        24,
        unitCost: 6.5,
        reference: 'CleanCo DN-88',
      );
      expect(bleach.stock, 36);
      expect(bleach.unitCost, 6.5);
      await s.countStoreStock(bleach.id, 34, reason: 'Two bottles leaking');
      expect(bleach.stock, 34);
      expect(s.stockCard(bleach.id).map((m) => m.kind), [
        StockMovementKind.adjusted,
        StockMovementKind.received,
      ]);
      expect(s.stockCard(bleach.id).first.quantity, -2);

      await s.login('nurse', '1234');
      final a = await s.createRequisition(
        department: 'Wards',
        quantities: {'ST-paper': 3},
      );
      final b = await s.createRequisition(
        department: 'Wards',
        quantities: {'ST-paper': 1},
      );
      await s.cancelRequisition(b.id);
      expect(b.status, RequisitionStatus.cancelled);
      await s.login('stores', '1234');
      await s.rejectRequisition(a.id, 'Use the office supply');
      expect(a.status, RequisitionStatus.rejected);
      expect(s.openRequisitions.map((r) => r.id), isNot(contains(a.id)));
    });
  });

  test('new records survive a save and reload', () async {
    final storage = MemoryStorage();
    final s = HospitalStore(storage: storage);
    await s.load();
    await s.login('nurse', '1234');
    await s.registerEmergency(
      patientId: _patient(s, 'Chloe Martin').id,
      complaint: 'Febrile convulsion',
    );
    await s.createRequisition(
      department: 'Emergency',
      quantities: {'ST-syr5': 10},
    );
    final again = HospitalStore(storage: storage);
    await again.load();
    expect(again.emergencyVisits, hasLength(s.emergencyVisits.length));
    expect(again.requisitions, hasLength(s.requisitions.length));
    expect(again.bloodUnits, hasLength(s.bloodUnits.length));
    expect(again.imagingStudies, hasLength(s.imagingStudies.length));
    expect(
      again.storeItems.map((i) => i.stock),
      s.storeItems.map((i) => i.stock),
    );
  });
}
