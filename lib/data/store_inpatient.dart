part of 'hospital_store.dart';

/// Wards, admissions and the operation theatre. Room and theatre charges go
/// on the same kind of invoice as everything else, so billing and the
/// finance reports pick them up automatically.
extension InpatientOperations on HospitalStore {
  // ---------------------------------------------------------------------------
  // Rooms
  // ---------------------------------------------------------------------------

  Room? roomById(String id) {
    for (final r in rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<Admission> get activeAdmissions =>
      admissions.where((a) => a.isActive).toList()
        ..sort((a, b) => a.admittedAt.compareTo(b.admittedAt));

  int occupiedBeds(String roomId) => admissions
      .where((a) => a.isActive && a.currentStay.roomId == roomId)
      .length;

  int freeBeds(String roomId) =>
      (roomById(roomId)?.beds ?? 0) - occupiedBeds(roomId);

  int get totalBeds => rooms.fold(0, (s, r) => s + r.beds);

  Admission? activeAdmissionFor(String patientId) {
    for (final a in admissions) {
      if (a.patientId == patientId && a.isActive) return a;
    }
    return null;
  }

  Admission? admissionById(String id) {
    for (final a in admissions) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<Admission> admissionsFor(String patientId) =>
      admissions.where((a) => a.patientId == patientId).toList()
        ..sort((a, b) => b.admittedAt.compareTo(a.admittedAt));

  Invoice? invoiceForAdmission(String admissionId) {
    for (final i in invoices) {
      if (i.admissionId == admissionId) return i;
    }
    return null;
  }

  Future<Room> upsertRoom(Room r) async {
    if (r.beds < 1) throw HospitalException('A room needs at least one bed');
    if (r.dailyRate < 0) throw HospitalException('Rate cannot be negative');
    if (r.beds < occupiedBeds(r.id)) {
      throw HospitalException(
        '${r.name} has ${occupiedBeds(r.id)} patients; transfer some first',
      );
    }
    if (roomById(r.id) == null) rooms.add(r);
    await _commit();
    return r;
  }

  // ---------------------------------------------------------------------------
  // Admissions
  // ---------------------------------------------------------------------------

  void _checkBedFree(String roomId) {
    final room = roomById(roomId);
    if (room == null) throw HospitalException('Room not found');
    if (freeBeds(roomId) <= 0) {
      throw HospitalException('${room.name} has no free bed');
    }
  }

  Future<Admission> admitPatient({
    required String patientId,
    required String roomId,
    required String doctorId,
    String reason = '',
  }) async {
    if (activeAdmissionFor(patientId) != null) {
      throw HospitalException('${patientName(patientId)} is already admitted');
    }
    _checkBedFree(roomId);
    final invoiceNo = await _next('invoice');
    // Re-check: another device may have filled the bed meanwhile.
    _checkBedFree(roomId);
    final room = roomById(roomId)!;
    final now = DateTime.now();
    final a = Admission(
      id: newId('ADM'),
      patientId: patientId,
      doctorId: doctorId,
      admittedAt: now,
      reason: reason.trim(),
      stays: [
        RoomStay(
          roomId: room.id,
          roomName: room.name,
          dailyRate: room.dailyRate,
          from: now,
        ),
      ],
    );
    admissions.add(a);
    _newInvoice(patientId: patientId, admissionId: a.id, number: invoiceNo);
    final msg =
        '${patientName(patientId)} admitted to ${room.name}'
        '${a.reason.isEmpty ? '' : ' – ${a.reason}'}';
    _notify(
      title: 'New admission',
      body: msg,
      role: UserRole.nurse,
      patientId: patientId,
    );
    if (doctorId != currentUser?.id) {
      _notify(
        title: 'Patient admitted under you',
        body: msg,
        userId: doctorId,
        patientId: patientId,
      );
    }
    await _commit();
    return a;
  }

  /// Moves an admitted patient to another room. Days in each room are billed
  /// at that room's rate.
  Future<void> transferRoom(String admissionId, String roomId) async {
    final a = admissionById(admissionId)!;
    if (!a.isActive) throw HospitalException('Patient was discharged');
    if (a.currentStay.roomId == roomId) {
      throw HospitalException('Patient is already in that room');
    }
    _checkBedFree(roomId);
    final room = roomById(roomId)!;
    final now = DateTime.now();
    a.currentStay.to = now;
    a.stays.add(
      RoomStay(
        roomId: room.id,
        roomName: room.name,
        dailyRate: room.dailyRate,
        from: now,
      ),
    );
    _notify(
      title: 'Patient transferred',
      body: '${patientName(a.patientId)} moved to ${room.name}',
      role: UserRole.nurse,
      patientId: a.patientId,
    );
    await _commit();
  }

  /// Discharges the patient and bills each room stay (days × daily rate).
  /// Fails while one of the patient's surgeries is still in theatre.
  Future<void> dischargePatient(
    String admissionId, {
    String summary = '',
  }) async {
    final a = admissionById(admissionId)!;
    if (!a.isActive) throw HospitalException('Already discharged');
    if (surgeries.any(
      (s) => s.admissionId == a.id && s.status == SurgeryStatus.inProgress,
    )) {
      throw HospitalException(
        'A surgery for this patient is still in progress',
      );
    }
    final now = DateTime.now();
    a
      ..dischargedAt = now
      ..dischargeSummary = summary.trim()
      ..currentStay.to = now;
    final invoice =
        invoiceForAdmission(a.id) ??
        _newInvoice(patientId: a.patientId, admissionId: a.id);
    final days = a.billableDays(now);
    for (var i = 0; i < a.stays.length; i++) {
      final s = a.stays[i];
      if (days[i] == 0) continue;
      invoice.lines.add(
        InvoiceLine(
          id: newId('LINE'),
          department: BillingDepartment.room,
          description: '${s.roomName} – ${days[i]} day(s)',
          quantity: days[i],
          unitPrice: s.dailyRate,
          sourceId: a.id,
        ),
      );
    }
    _notify(
      title: 'Patient discharged',
      body:
          '${patientName(a.patientId)} – room charges '
          '${a.roomCharges(now).toStringAsFixed(2)} added to the bill',
      role: UserRole.receptionist,
      patientId: a.patientId,
    );
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Operation theatre
  // ---------------------------------------------------------------------------

  OperationTheatre? theatreById(String id) {
    for (final t in theatres) {
      if (t.id == id) return t;
    }
    return null;
  }

  Surgery? surgeryById(String id) {
    for (final s in surgeries) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<Surgery> surgeriesOn(DateTime day) =>
      surgeries
          .where(
            (s) =>
                HospitalStore._sameDay(s.scheduledAt, day) &&
                s.status != SurgeryStatus.cancelled,
          )
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  List<Surgery> surgeriesFor(String patientId) =>
      surgeries.where((s) => s.patientId == patientId).toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  Invoice? invoiceForSurgery(String surgeryId) {
    for (final i in invoices) {
      if (i.surgeryId == surgeryId) return i;
    }
    return null;
  }

  Future<OperationTheatre> upsertTheatre(OperationTheatre t) async {
    if (t.hourlyRate < 0) throw HospitalException('Rate cannot be negative');
    if (theatreById(t.id) == null) theatres.add(t);
    await _commit();
    return t;
  }

  /// Another booking in [theatreId] overlapping the given slot, if any.
  Surgery? theatreClash(
    String theatreId,
    DateTime start,
    int minutes, {
    String? ignoreId,
  }) {
    final end = start.add(Duration(minutes: minutes));
    for (final s in surgeries) {
      if (s.id == ignoreId || s.theatreId != theatreId) continue;
      if (s.status == SurgeryStatus.cancelled ||
          s.status == SurgeryStatus.completed) {
        continue;
      }
      if (s.scheduledAt.isBefore(end) && start.isBefore(s.plannedEnd)) {
        return s;
      }
    }
    return null;
  }

  Future<Surgery> scheduleSurgery({
    required String patientId,
    required String surgeonId,
    required String theatreId,
    required String procedure,
    required DateTime scheduledAt,
    int estimatedMinutes = 60,
    String anaesthetist = '',
    double surgeonFee = 0,
    double anaesthesiaFee = 0,
    String notes = '',
  }) async {
    if (procedure.trim().isEmpty) {
      throw HospitalException('Enter the procedure');
    }
    if (estimatedMinutes <= 0) {
      throw HospitalException('Duration must be positive');
    }
    final clash = theatreClash(theatreId, scheduledAt, estimatedMinutes);
    if (clash != null) {
      throw HospitalException(
        '${theatreById(theatreId)?.name ?? 'Theatre'} is booked for '
        '${clash.procedure} (${patientName(clash.patientId)}) at that time',
      );
    }
    final s = Surgery(
      id: newId('SUR'),
      patientId: patientId,
      surgeonId: surgeonId,
      theatreId: theatreId,
      procedure: procedure.trim(),
      scheduledAt: scheduledAt,
      estimatedMinutes: estimatedMinutes,
      admissionId: activeAdmissionFor(patientId)?.id,
      anaesthetist: anaesthetist.trim(),
      surgeonFee: surgeonFee,
      anaesthesiaFee: anaesthesiaFee,
      notes: notes.trim(),
    );
    surgeries.add(s);
    final msg =
        '${s.procedure} for ${patientName(patientId)} in '
        '${theatreById(theatreId)?.name}, '
        '${scheduledAt.day}/${scheduledAt.month} '
        '${scheduledAt.hour.toString().padLeft(2, '0')}:'
        '${scheduledAt.minute.toString().padLeft(2, '0')}';
    _notify(
      title: 'Surgery scheduled',
      body: msg,
      role: UserRole.nurse,
      patientId: patientId,
    );
    if (surgeonId != currentUser?.id) {
      _notify(
        title: 'Surgery scheduled for you',
        body: msg,
        userId: surgeonId,
        patientId: patientId,
      );
    }
    await _commit();
    return s;
  }

  Future<void> startSurgery(String surgeryId) async {
    final s = surgeryById(surgeryId)!;
    if (s.status != SurgeryStatus.scheduled) {
      throw HospitalException('Surgery is ${s.status.label.toLowerCase()}');
    }
    if (surgeries.any(
      (o) => o.theatreId == s.theatreId && o.status == SurgeryStatus.inProgress,
    )) {
      throw HospitalException('${theatreById(s.theatreId)?.name} is in use');
    }
    s
      ..status = SurgeryStatus.inProgress
      ..startedAt = DateTime.now()
      // The patient may have been admitted after scheduling.
      ..admissionId ??= activeAdmissionFor(s.patientId)?.id;
    await _commit();
  }

  /// Ends the surgery and bills it: theatre time (started hours × rate),
  /// surgeon and anaesthesia fees, and consumables. Charges go on the
  /// admission's invoice, or a new one for a day case.
  Future<void> completeSurgery(
    String surgeryId, {
    double consumablesCost = 0,
    String notes = '',
  }) async {
    if (consumablesCost < 0) {
      throw HospitalException('Consumables cost cannot be negative');
    }
    final s = surgeryById(surgeryId)!;
    if (s.status != SurgeryStatus.inProgress) {
      throw HospitalException('Start the surgery first');
    }
    final number = s.admissionId == null ? await _next('invoice') : null;
    s
      ..status = SurgeryStatus.completed
      ..endedAt = DateTime.now()
      ..consumablesCost = consumablesCost;
    if (notes.trim().isNotEmpty) s.notes = notes.trim();

    final invoice =
        (s.admissionId == null ? null : invoiceForAdmission(s.admissionId!)) ??
        _newInvoice(
          patientId: s.patientId,
          admissionId: s.admissionId,
          surgeryId: s.admissionId == null ? s.id : null,
          number: number,
        );
    final theatre = theatreById(s.theatreId);
    void line(String description, int qty, double price) {
      if (price <= 0) return;
      invoice.lines.add(
        InvoiceLine(
          id: newId('LINE'),
          department: BillingDepartment.surgery,
          description: description,
          quantity: qty,
          unitPrice: price,
          sourceId: s.id,
        ),
      );
    }

    line(
      '${theatre?.name ?? 'Theatre'} – ${s.billableHours} h (${s.procedure})',
      s.billableHours,
      theatre?.hourlyRate ?? 0,
    );
    line('Surgeon fee – ${userName(s.surgeonId)}', 1, s.surgeonFee);
    line(
      'Anaesthesia${s.anaesthetist.isEmpty ? '' : ' – ${s.anaesthetist}'}',
      1,
      s.anaesthesiaFee,
    );
    line('Theatre consumables', 1, consumablesCost);
    await _commit();
  }

  Future<void> cancelSurgery(String surgeryId) async {
    final s = surgeryById(surgeryId)!;
    if (s.status != SurgeryStatus.scheduled) {
      throw HospitalException('Only scheduled surgeries can be cancelled');
    }
    s.status = SurgeryStatus.cancelled;
    _notify(
      title: 'Surgery cancelled',
      body: '${s.procedure} for ${patientName(s.patientId)}',
      role: UserRole.nurse,
      patientId: s.patientId,
    );
    await _commit();
  }
}
