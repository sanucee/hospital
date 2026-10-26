part of 'hospital_store.dart';

/// The emergency department: arrival, triage, the doctor's assessment and
/// disposition. The assessment is a normal consultation, so tests, imaging,
/// prescriptions and billing reuse the clinic workflow; the attendance fee
/// goes on the same bill.
extension EmergencyOperations on HospitalStore {
  EmergencyVisit? emergencyVisitById(String id) =>
      _find(emergencyVisits, (v) => v.id == id);

  EmergencyVisit? openEmergencyVisitFor(String patientId) =>
      _find(emergencyVisits, (v) => v.patientId == patientId && v.isOpen);

  EmergencyVisit? emergencyVisitForConsultation(String consultationId) =>
      _find(emergencyVisits, (v) => v.consultationId == consultationId);

  List<EmergencyVisit> emergencyVisitsFor(String patientId) =>
      emergencyVisits.where((v) => v.patientId == patientId).toList()
        ..sort((a, b) => b.arrivedAt.compareTo(a.arrivedAt));

  /// Patients in the department: those awaiting triage first, then by
  /// triage level, then by arrival.
  List<EmergencyVisit> get emergencyBoard {
    int rank(EmergencyVisit v) =>
        v.triageLevel == null ? -1 : TriageLevel.values.indexOf(v.triageLevel!);
    return emergencyVisits.where((v) => v.isOpen).toList()..sort((a, b) {
      final seen = (a.status == EmergencyStatus.beingSeen ? 1 : 0).compareTo(
        b.status == EmergencyStatus.beingSeen ? 1 : 0,
      );
      if (seen != 0) return seen;
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.arrivedAt.compareTo(b.arrivedAt);
    });
  }

  /// Emergency visits that ended on [day].
  List<EmergencyVisit> emergencyClosedOn(DateTime day) =>
      emergencyVisits
          .where(
            (v) =>
                v.closedAt != null && HospitalStore._sameDay(v.closedAt!, day),
          )
          .toList()
        ..sort((a, b) => b.closedAt!.compareTo(a.closedAt!));

  /// Registers someone who can't give their details (unconscious, alone),
  /// so treatment and billing can start. Reception completes the record
  /// later.
  Future<Patient> registerUnknownPatient({
    required String gender,
    int estimatedAge = 30,
  }) {
    final now = DateTime.now();
    final stamp =
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    return registerPatient(
      name: 'Unknown ${gender.toLowerCase()} (ER $stamp)',
      dateOfBirth: DateTime(now.year - estimatedAge, 1, 1),
      gender: gender,
      phone: '',
    );
  }

  Future<EmergencyVisit> registerEmergency({
    required String patientId,
    required String complaint,
    String arrivalMode = 'Walk-in',
  }) async {
    if (complaint.trim().isEmpty) {
      throw HospitalException('Enter the presenting complaint');
    }
    if (openEmergencyVisitFor(patientId) != null) {
      throw HospitalException(
        '${patientName(patientId)} is already in the emergency department',
      );
    }
    final v = EmergencyVisit(
      id: newId('ER'),
      patientId: patientId,
      arrivedAt: DateTime.now(),
      complaint: complaint.trim(),
      arrivalMode: arrivalMode,
      registeredBy: currentUser?.id,
    );
    emergencyVisits.add(v);
    _notify(
      title: 'Emergency arrival',
      body:
          '${patientName(patientId)} (${v.arrivalMode}): ${v.complaint} – '
          'awaiting triage',
      role: UserRole.nurse,
      patientId: patientId,
    );
    await _commit();
    return v;
  }

  /// Records the triage category and observations. Can be repeated while
  /// the patient waits, if their condition changes.
  Future<void> triageEmergency(
    String visitId, {
    required TriageLevel level,
    double? temperature,
    int? pulse,
    int? respRate,
    int? systolic,
    int? diastolic,
    int? spo2,
    int? painScore,
    String notes = '',
  }) async {
    final v = emergencyVisitById(visitId)!;
    if (v.status != EmergencyStatus.waitingTriage &&
        v.status != EmergencyStatus.waitingDoctor) {
      throw HospitalException('Patient is ${v.status.label.toLowerCase()}');
    }
    if (painScore != null && (painScore < 0 || painScore > 10)) {
      throw HospitalException('Pain score is 0 to 10');
    }
    final escalated =
        v.triageLevel == null ||
        TriageLevel.values.indexOf(level) <
            TriageLevel.values.indexOf(v.triageLevel!);
    v
      ..triageLevel = level
      ..triagedAt = DateTime.now()
      ..triagedBy = currentUser?.id
      ..temperature = temperature
      ..pulse = pulse
      ..respRate = respRate
      ..systolic = systolic
      ..diastolic = diastolic
      ..spo2 = spo2
      ..painScore = painScore
      ..triageNotes = notes.trim()
      ..status = EmergencyStatus.waitingDoctor;
    if (escalated &&
        (level == TriageLevel.immediate || level == TriageLevel.veryUrgent)) {
      _notify(
        title: '${level.colour.toUpperCase()} – emergency patient',
        body:
            '${patientName(v.patientId)}: ${v.complaint}. '
            'To be seen ${level == TriageLevel.immediate ? 'immediately' : 'within 10 minutes'}.',
        role: UserRole.doctor,
        patientId: v.patientId,
      );
    }
    await _commit();
  }

  /// A doctor takes the patient: opens a consultation (with the triage
  /// observations filled in) and bills the attendance fee.
  Future<Consultation> seeEmergencyPatient(
    String visitId, {
    required String doctorId,
  }) async {
    final v = emergencyVisitById(visitId)!;
    if (v.status == EmergencyStatus.closed) {
      throw HospitalException('Patient has left the department');
    }
    if (v.status == EmergencyStatus.beingSeen && v.consultationId != null) {
      final open = consultationById(v.consultationId!);
      if (open != null) return open;
    }
    final c = await startConsultation(
      patientId: v.patientId,
      doctorId: doctorId,
    );
    c
      ..complaints = v.complaint
      ..vitals = Vitals(
        temperature: v.temperature?.toString() ?? '',
        bloodPressure: v.systolic == null || v.diastolic == null
            ? ''
            : '${v.systolic}/${v.diastolic}',
        pulse: v.pulse?.toString() ?? '',
        spo2: v.spo2?.toString() ?? '',
      );
    v
      ..doctorId = doctorId
      ..seenAt = DateTime.now()
      ..consultationId = c.id
      ..status = EmergencyStatus.beingSeen;
    final fee = profile.emergencyFee;
    if (fee > 0) {
      _invoiceFor(c).lines.add(
        InvoiceLine(
          id: newId('LINE'),
          department: BillingDepartment.emergency,
          description: 'Emergency department attendance',
          quantity: 1,
          unitPrice: fee,
          sourceId: v.id,
        ),
      );
    }
    await _commit();
    return c;
  }

  /// Ends the visit. Admitting puts the patient in [roomId] under the
  /// treating doctor; the open consultation is completed.
  Future<void> closeEmergency(
    String visitId, {
    required EmergencyOutcome outcome,
    String notes = '',
    String? roomId,
  }) async {
    final v = emergencyVisitById(visitId)!;
    if (!v.isOpen) throw HospitalException('Visit is already closed');
    if (outcome == EmergencyOutcome.leftWithoutBeingSeen &&
        v.consultationId != null) {
      throw HospitalException('The patient has already been seen');
    }
    if (outcome == EmergencyOutcome.admitted) {
      if (roomId == null) throw HospitalException('Choose a ward or room');
      final doctorId = v.doctorId ?? currentUser?.id;
      if (doctorId == null || userById(doctorId)?.role != UserRole.doctor) {
        throw HospitalException('A doctor must see the patient first');
      }
      final a = await admitPatient(
        patientId: v.patientId,
        roomId: roomId,
        doctorId: doctorId,
        reason: 'From emergency: ${v.complaint}',
      );
      v.admissionId = a.id;
    }
    final c = v.consultationId == null
        ? null
        : consultationById(v.consultationId!);
    if (c != null && c.isOpen) {
      if (c.diagnosis.isEmpty && notes.trim().isNotEmpty) {
        c.diagnosis = notes.trim();
      }
      await completeConsultation(c.id);
    }
    v
      ..outcome = outcome
      ..outcomeNotes = notes.trim()
      ..closedAt = DateTime.now()
      ..status = EmergencyStatus.closed;
    await _commit();
  }
}
