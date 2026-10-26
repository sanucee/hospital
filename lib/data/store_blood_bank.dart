part of 'hospital_store.dart';

/// The blood bank, run by the laboratory: donors and donations, screening,
/// stock by group and component, doctors' requests, cross-matching and
/// issue. Issued units are billed to the admission (or the visit).
extension BloodBankOperations on HospitalStore {
  BloodDonor? bloodDonorById(String id) =>
      _find(bloodDonors, (d) => d.id == id);

  BloodUnit? bloodUnitById(String id) => _find(bloodUnits, (u) => u.id == id);

  BloodRequest? bloodRequestById(String id) =>
      _find(bloodRequests, (r) => r.id == id);

  /// Units on the shelf and usable now, oldest expiry first.
  List<BloodUnit> usableBloodUnits({
    String? bloodGroup,
    BloodComponent? component,
  }) {
    final now = DateTime.now();
    return bloodUnits
        .where(
          (u) =>
              u.usable(now) &&
              (bloodGroup == null || u.bloodGroup == bloodGroup) &&
              (component == null || u.component == component),
        )
        .toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  }

  /// Usable units per blood group and component.
  Map<String, Map<BloodComponent, int>> get bloodStock {
    final stock = {
      for (final g in kBloodGroups)
        g: {for (final c in BloodComponent.values) c: 0},
    };
    for (final u in usableBloodUnits()) {
      final row = stock[u.bloodGroup];
      if (row != null) row[u.component] = row[u.component]! + 1;
    }
    return stock;
  }

  /// Units still in stock (available or cross-matched) that expire within
  /// [days], or already have.
  List<BloodUnit> expiringBloodUnits({int days = 3}) {
    final cutoff = DateTime.now().add(Duration(days: days));
    return bloodUnits
        .where(
          (u) =>
              (u.status == BloodUnitStatus.available ||
                  u.status == BloodUnitStatus.reserved) &&
              u.expiresAt.isBefore(cutoff),
        )
        .toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  }

  /// Open requests, emergencies first.
  List<BloodRequest> get openBloodRequests =>
      bloodRequests.where((r) => r.isOpen).toList()..sort((a, b) {
        final u = kBloodUrgencies
            .indexOf(b.urgency)
            .compareTo(kBloodUrgencies.indexOf(a.urgency));
        return u != 0 ? u : a.requestedAt.compareTo(b.requestedAt);
      });

  List<BloodRequest> bloodRequestsFor(String patientId) =>
      bloodRequests.where((r) => r.patientId == patientId).toList()
        ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

  /// Usable units that suit [requestId]'s patient, same group first, then
  /// by expiry so the oldest stock is used first.
  List<BloodUnit> compatibleUnits(String requestId) {
    final r = bloodRequestById(requestId)!;
    final group = patientById(r.patientId)?.bloodGroup ?? '';
    return usableBloodUnits(component: r.component)
        .where((u) => bloodCompatible(u.bloodGroup, group, r.component))
        .toList()
      ..sort((a, b) {
        final same = (a.bloodGroup == group ? 0 : 1).compareTo(
          b.bloodGroup == group ? 0 : 1,
        );
        return same != 0 ? same : a.expiresAt.compareTo(b.expiresAt);
      });
  }

  Future<String> _unitNumber() async {
    final n = await _next('bloodUnit');
    return n == null
        ? 'BU-T${_offlineNumber()}'
        : 'BU-${n.toString().padLeft(5, '0')}';
  }

  // ---------------------------------------------------------------------------
  // Donors and stock
  // ---------------------------------------------------------------------------

  Future<BloodDonor> upsertBloodDonor(BloodDonor d) async {
    if (d.name.trim().isEmpty) throw HospitalException('Enter the name');
    if (!kBloodGroups.contains(d.bloodGroup)) {
      throw HospitalException('Choose the blood group');
    }
    if (bloodDonorById(d.id) == null) bloodDonors.add(d);
    await _commit();
    return d;
  }

  /// Takes a donation. The unit waits in quarantine until screened.
  Future<BloodUnit> recordDonation(
    String donorId, {
    BloodComponent component = BloodComponent.wholeBlood,
    int? volumeMl,
  }) async {
    final d = bloodDonorById(donorId)!;
    final now = DateTime.now();
    if (!d.canDonateOn(now)) {
      throw HospitalException(
        '${d.name} can donate again from ${_shortDate(d.nextEligible()!)}',
      );
    }
    final number = await _unitNumber();
    final u = BloodUnit(
      id: newId('BU'),
      unitNumber: number,
      bloodGroup: d.bloodGroup,
      component: component,
      collectedAt: now,
      expiresAt: now.add(component.shelfLife),
      volumeMl: volumeMl ?? component.defaultVolumeMl,
      donorId: d.id,
    );
    bloodUnits.add(u);
    d.lastDonationAt = now;
    await _commit();
    return u;
  }

  /// Adds units bought from a blood service, already screened.
  Future<List<BloodUnit>> receiveBloodUnits({
    required String bloodGroup,
    required BloodComponent component,
    required int count,
    required String source,
    DateTime? collectedAt,
  }) async {
    if (!kBloodGroups.contains(bloodGroup)) {
      throw HospitalException('Choose the blood group');
    }
    if (count < 1 || count > 50) throw HospitalException('Enter 1 to 50 units');
    if (source.trim().isEmpty) throw HospitalException('Enter the source');
    final now = DateTime.now();
    final collected = collectedAt ?? now;
    if (!collected.add(component.shelfLife).isAfter(now)) {
      throw HospitalException('Those units have already expired');
    }
    final created = <BloodUnit>[];
    for (var i = 0; i < count; i++) {
      final u = BloodUnit(
        id: newId('BU'),
        unitNumber: await _unitNumber(),
        bloodGroup: bloodGroup,
        component: component,
        collectedAt: collected,
        expiresAt: collected.add(component.shelfLife),
        volumeMl: component.defaultVolumeMl,
        source: source.trim(),
        status: BloodUnitStatus.available,
        screenedAt: now,
        screenedBy: currentUser?.id,
      );
      bloodUnits.add(u);
      created.add(u);
    }
    await _commit();
    return created;
  }

  /// Records the infection screen: passed units go into stock, failed ones
  /// are discarded.
  Future<void> screenBloodUnit(
    String unitId, {
    required bool passed,
    String reason = '',
  }) async {
    final u = bloodUnitById(unitId)!;
    if (u.status != BloodUnitStatus.quarantine) {
      throw HospitalException('Unit ${u.unitNumber} is already screened');
    }
    if (!passed && reason.trim().isEmpty) {
      throw HospitalException('Enter the reason it failed');
    }
    u
      ..screenedAt = DateTime.now()
      ..screenedBy = currentUser?.id
      ..status = passed ? BloodUnitStatus.available : BloodUnitStatus.discarded
      ..discardReason = passed ? '' : reason.trim();
    await _commit();
  }

  /// Takes a unit out of stock (expired, damaged...). A cross-matched unit
  /// is released from its request, which goes back to the queue.
  Future<void> discardBloodUnit(String unitId, String reason) async {
    final u = bloodUnitById(unitId)!;
    if (u.status == BloodUnitStatus.issued ||
        u.status == BloodUnitStatus.discarded) {
      throw HospitalException('Unit is ${u.status.label.toLowerCase()}');
    }
    if (reason.trim().isEmpty) throw HospitalException('Enter the reason');
    final r = u.requestId == null ? null : bloodRequestById(u.requestId!);
    if (r != null && r.status == BloodRequestStatus.reserved) {
      r
        ..unitIds.remove(u.id)
        ..status = BloodRequestStatus.pending;
      _releaseUnits(r);
    }
    u
      ..status = BloodUnitStatus.discarded
      ..discardReason = reason.trim()
      ..requestId = null;
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Requests
  // ---------------------------------------------------------------------------

  Future<BloodRequest> requestBlood({
    required String patientId,
    required String doctorId,
    required BloodComponent component,
    required int units,
    String urgency = 'Routine',
    String indication = '',
    String? consultationId,
  }) async {
    if (units < 1 || units > 10) {
      throw HospitalException('Request 1 to 10 units');
    }
    if (indication.trim().isEmpty) {
      throw HospitalException('Enter the reason for transfusion');
    }
    final r = BloodRequest(
      id: newId('BR'),
      patientId: patientId,
      doctorId: doctorId,
      component: component,
      units: units,
      requestedAt: DateTime.now(),
      urgency: urgency,
      indication: indication.trim(),
      consultationId: consultationId,
      admissionId: activeAdmissionFor(patientId)?.id,
    );
    bloodRequests.add(r);
    final group = patientById(patientId)?.bloodGroup ?? '';
    _notify(
      title: urgency == 'Routine'
          ? 'Blood request'
          : '${urgency.toUpperCase()} blood request',
      body:
          '$units × ${component.label} for ${patientName(patientId)} '
          '(${group.isEmpty ? 'group not known' : group}) from '
          '${userName(doctorId)}',
      role: UserRole.labTechnician,
      patientId: patientId,
    );
    await _commit();
    return r;
  }

  /// Records the patient's blood group after grouping in the lab.
  Future<void> setPatientBloodGroup(String patientId, String group) async {
    if (!kBloodGroups.contains(group)) {
      throw HospitalException('Choose a valid blood group');
    }
    patientById(patientId)!.bloodGroup = group;
    await _commit();
  }

  /// Reserves compatible units for the request after the cross-match.
  Future<void> crossmatchBlood(String requestId, List<String> unitIds) async {
    final r = bloodRequestById(requestId)!;
    if (r.status != BloodRequestStatus.pending) {
      throw HospitalException('Request is ${r.status.label.toLowerCase()}');
    }
    final group = patientById(r.patientId)?.bloodGroup ?? '';
    if (!kBloodGroups.contains(group)) {
      throw HospitalException("Record the patient's blood group first");
    }
    final ids = unitIds.toSet();
    if (ids.length != r.units) {
      throw HospitalException('Select ${r.units} unit(s)');
    }
    final now = DateTime.now();
    for (final id in ids) {
      final u = bloodUnitById(id);
      if (u == null || !u.usable(now)) {
        throw HospitalException('Unit ${u?.unitNumber ?? id} is not available');
      }
      if (u.component != r.component) {
        throw HospitalException('Unit ${u.unitNumber} is ${u.component.label}');
      }
      if (!bloodCompatible(u.bloodGroup, group, r.component)) {
        throw HospitalException(
          'Unit ${u.unitNumber} (${u.bloodGroup}) is not compatible with '
          '$group',
        );
      }
    }
    for (final id in ids) {
      bloodUnitById(id)!
        ..status = BloodUnitStatus.reserved
        ..requestId = r.id;
    }
    r
      ..unitIds.clear()
      ..unitIds.addAll(ids)
      ..status = BloodRequestStatus.reserved
      ..crossmatchedBy = currentUser?.id
      ..crossmatchedAt = now;
    _notify(
      title: 'Blood ready',
      body:
          '${r.units} × ${r.component.label} cross-matched for '
          '${patientName(r.patientId)}',
      userId: r.doctorId,
      patientId: r.patientId,
    );
    await _commit();
  }

  /// Hands the cross-matched units over to the ward and bills them.
  Future<void> issueBlood(String requestId) async {
    final r = bloodRequestById(requestId)!;
    if (r.status != BloodRequestStatus.reserved) {
      throw HospitalException('Cross-match the request first');
    }
    final now = DateTime.now();
    for (final id in r.unitIds) {
      final u = bloodUnitById(id);
      if (u == null ||
          u.status != BloodUnitStatus.reserved ||
          u.requestId != r.id) {
        throw HospitalException('Unit ${u?.unitNumber ?? id} is not reserved');
      }
      if (u.isExpired(now)) {
        throw HospitalException(
          'Unit ${u.unitNumber} has expired; discard it and cross-match again',
        );
      }
    }
    // The bill: the admission's, else the visit's, else a new one.
    final admissionId = r.admissionId ?? activeAdmissionFor(r.patientId)?.id;
    Invoice? invoice = admissionId == null
        ? null
        : invoiceForAdmission(admissionId);
    if (invoice == null && r.consultationId != null) {
      final c = consultationById(r.consultationId!);
      if (c != null) invoice = _invoiceFor(c);
    }
    if (invoice == null) {
      final number = await _next('invoice');
      invoice = _newInvoice(
        patientId: r.patientId,
        admissionId: admissionId,
        number: number,
      );
    }
    final numbers = <String>[];
    for (final id in r.unitIds) {
      final u = bloodUnitById(id)!
        ..status = BloodUnitStatus.issued
        ..issuedAt = now
        ..issuedBy = currentUser?.id
        ..patientId = r.patientId;
      numbers.add(u.unitNumber);
    }
    invoice.lines.add(
      InvoiceLine(
        id: newId('LINE'),
        department: BillingDepartment.bloodBank,
        description: '${r.component.label} (${numbers.join(', ')})',
        quantity: r.unitIds.length,
        unitPrice: r.component.fee,
        sourceId: r.id,
      ),
    );
    r
      ..status = BloodRequestStatus.issued
      ..issuedAt = now
      ..issuedBy = currentUser?.id;
    final msg =
        '${numbers.length} × ${r.component.label} issued for '
        '${patientName(r.patientId)}: ${numbers.join(', ')}';
    _notify(
      title: 'Blood issued',
      body: msg,
      userId: r.doctorId,
      patientId: r.patientId,
    );
    if (admissionId != null) {
      _notify(
        title: 'Blood issued',
        body: msg,
        role: UserRole.nurse,
        patientId: r.patientId,
      );
    }
    await _commit();
  }

  Future<void> cancelBloodRequest(
    String requestId, {
    String reason = '',
  }) async {
    final r = bloodRequestById(requestId)!;
    if (!r.isOpen) {
      throw HospitalException('Request is ${r.status.label.toLowerCase()}');
    }
    _releaseUnits(r);
    r
      ..status = BloodRequestStatus.cancelled
      ..cancelReason = reason.trim()
      ..unitIds.clear();
    await _commit();
  }

  /// Returns any units reserved for [r] to stock.
  void _releaseUnits(BloodRequest r) {
    for (final u in bloodUnits) {
      if (u.requestId == r.id && u.status == BloodUnitStatus.reserved) {
        u
          ..status = BloodUnitStatus.available
          ..requestId = null;
      }
    }
    if (r.status == BloodRequestStatus.pending) r.unitIds.clear();
  }
}

String _shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
