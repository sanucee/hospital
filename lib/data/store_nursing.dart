part of 'hospital_store.dart';

/// One scheduled administration time on the medication chart.
class MarSlot {
  MarSlot(this.order, this.time, this.dose);

  final MedicationOrder order;
  final DateTime time;

  /// What was recorded for this slot, if anything.
  final MedicationDose? dose;

  /// Within an hour either side of the scheduled time.
  bool isDue(DateTime now) =>
      dose == null && now.difference(time).inMinutes.abs() <= 60;

  /// More than an hour late with nothing recorded.
  bool isOverdue(DateTime now) =>
      dose == null && now.difference(time).inMinutes > 60;
}

/// Nursing care for admitted patients: observations with NEWS2, the
/// medication administration record, and nursing notes.
extension NursingOperations on HospitalStore {
  Admission _activeAdmission(String admissionId) {
    final a = admissionById(admissionId);
    if (a == null) throw HospitalException('Admission not found');
    if (!a.isActive) throw HospitalException('Patient has been discharged');
    return a;
  }

  // ---------------------------------------------------------------------------
  // Observations
  // ---------------------------------------------------------------------------

  List<VitalsReading> vitalsFor(String admissionId) =>
      vitals.where((v) => v.admissionId == admissionId).toList()
        ..sort((a, b) => b.takenAt.compareTo(a.takenAt));

  VitalsReading? latestVitals(String admissionId) {
    final list = vitalsFor(admissionId);
    return list.isEmpty ? null : list.first;
  }

  Future<VitalsReading> recordVitals({
    required String admissionId,
    double? temperature,
    int? pulse,
    int? respRate,
    int? systolic,
    int? diastolic,
    int? spo2,
    bool onOxygen = false,
    Consciousness consciousness = Consciousness.alert,
    int? painScore,
    double? bloodSugar,
    String notes = '',
    DateTime? takenAt,
  }) async {
    final a = _activeAdmission(admissionId);
    if ([
      temperature,
      pulse,
      respRate,
      systolic,
      spo2,
    ].every((v) => v == null)) {
      throw HospitalException('Enter at least one observation');
    }
    if (painScore != null && (painScore < 0 || painScore > 10)) {
      throw HospitalException('Pain score is 0 to 10');
    }
    if (spo2 != null && (spo2 < 50 || spo2 > 100)) {
      throw HospitalException('SpO₂ must be between 50 and 100%');
    }
    final v = VitalsReading(
      id: newId('VIT'),
      admissionId: a.id,
      patientId: a.patientId,
      takenAt: takenAt ?? DateTime.now(),
      temperature: temperature,
      pulse: pulse,
      respRate: respRate,
      systolic: systolic,
      diastolic: diastolic,
      spo2: spo2,
      onOxygen: onOxygen,
      consciousness: consciousness,
      painScore: painScore,
      bloodSugar: bloodSugar,
      notes: notes.trim(),
      recordedBy: currentUser?.id,
    );
    vitals.add(v);
    final news = v.news2;
    if (news.needsDoctor || news.anySingle3) {
      final msg =
          '${patientName(a.patientId)} (${a.currentStay.roomName}): NEWS2 '
          '${news.score}, ${news.risk.label.toLowerCase()} risk. '
          '${news.risk.response}.';
      _notify(
        title: news.needsDoctor
            ? 'Deteriorating patient'
            : 'Abnormal observation',
        body: msg,
        userId: a.doctorId,
        patientId: a.patientId,
      );
      if (news.needsDoctor) {
        _notify(
          title: 'Deteriorating patient',
          body: msg,
          role: UserRole.nurse,
          patientId: a.patientId,
        );
      }
    }
    await _commit();
    return v;
  }

  /// Admitted patients whose latest observations score medium or high.
  List<(Admission, VitalsReading)> get patientsAtRisk => [
    for (final a in activeAdmissions)
      if (latestVitals(a.id) case final v? when v.news2.needsDoctor) (a, v),
  ];

  // ---------------------------------------------------------------------------
  // Medication administration record
  // ---------------------------------------------------------------------------

  List<MedicationOrder> medicationOrdersFor(String admissionId) =>
      medicationOrders.where((o) => o.admissionId == admissionId).toList()
        ..sort((a, b) {
          if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
          return a.startAt.compareTo(b.startAt);
        });

  List<MedicationDose> dosesFor(String orderId) =>
      medicationDoses.where((d) => d.orderId == orderId).toList()
        ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

  Future<MedicationOrder> addMedicationOrder({
    required String admissionId,
    required String medicineName,
    required String dose,
    required String route,
    required String frequency,
    String? medicineId,
    String instructions = '',
  }) async {
    final a = _activeAdmission(admissionId);
    if (medicineName.trim().isEmpty || dose.trim().isEmpty) {
      throw HospitalException('Enter the medicine and dose');
    }
    final times = kMedicationSchedules[frequency];
    if (times == null) throw HospitalException('Choose a frequency');
    final o = MedicationOrder(
      id: newId('MO'),
      admissionId: a.id,
      patientId: a.patientId,
      medicineId: medicineId,
      medicineName: medicineName.trim(),
      dose: dose.trim(),
      route: route,
      frequency: frequency,
      times: times,
      startAt: DateTime.now(),
      instructions: instructions.trim(),
      orderedBy: currentUser?.id,
    );
    medicationOrders.add(o);
    _notify(
      title: 'New ward medication',
      body:
          '${patientName(a.patientId)}: ${o.medicineName} ${o.dose} '
          '${o.route}, ${o.frequency.toLowerCase()}',
      role: UserRole.nurse,
      patientId: a.patientId,
    );
    await _commit();
    return o;
  }

  Future<void> stopMedicationOrder(String orderId) async {
    final o = medicationOrders.firstWhere((o) => o.id == orderId);
    if (!o.isActive) throw HospitalException('Already stopped');
    o
      ..stoppedAt = DateTime.now()
      ..stoppedBy = currentUser?.id;
    await _commit();
  }

  /// The day's scheduled doses for an admission, in time order.
  List<MarSlot> marFor(String admissionId, DateTime day) {
    final slots = <MarSlot>[];
    for (final o in medicationOrdersFor(admissionId)) {
      final doses = dosesFor(o.id);
      for (final t in o.slotsOn(day)) {
        MedicationDose? done;
        for (final d in doses) {
          if (d.scheduledFor == t) {
            done = d;
            break;
          }
        }
        slots.add(MarSlot(o, t, done));
      }
    }
    return slots..sort((a, b) => a.time.compareTo(b.time));
  }

  /// Doses due now or overdue today, across all admitted patients.
  List<(Admission, MarSlot)> dosesNeedingAttention([DateTime? at]) {
    final now = at ?? DateTime.now();
    return [
      for (final a in activeAdmissions)
        for (final s in marFor(a.id, now))
          if (s.isDue(now) || s.isOverdue(now)) (a, s),
    ];
  }

  /// Records what happened at a scheduled time, or a PRN dose when
  /// [scheduledFor] is null.
  Future<MedicationDose> recordDose({
    required String orderId,
    DateTime? scheduledFor,
    required DoseStatus status,
    String notes = '',
  }) async {
    final o = medicationOrders.firstWhere((o) => o.id == orderId);
    _activeAdmission(o.admissionId);
    if (scheduledFor == null && !o.isPrn) {
      throw HospitalException('Choose the scheduled time');
    }
    if (scheduledFor != null &&
        medicationDoses.any(
          (d) => d.orderId == orderId && d.scheduledFor == scheduledFor,
        )) {
      throw HospitalException('This dose was already recorded');
    }
    if (status != DoseStatus.given && notes.trim().isEmpty) {
      throw HospitalException('Give a reason when a dose is not given');
    }
    final d = MedicationDose(
      id: newId('DOSE'),
      orderId: o.id,
      admissionId: o.admissionId,
      patientId: o.patientId,
      scheduledFor: scheduledFor,
      recordedAt: DateTime.now(),
      status: status,
      notes: notes.trim(),
      recordedBy: currentUser?.id,
    );
    medicationDoses.add(d);
    if (status == DoseStatus.refused || status == DoseStatus.held) {
      final a = admissionById(o.admissionId)!;
      _notify(
        title: 'Dose ${status.label.toLowerCase()}',
        body:
            '${patientName(o.patientId)}: ${o.medicineName} ${o.dose}. '
            '${d.notes}',
        userId: a.doctorId,
        patientId: o.patientId,
      );
    }
    await _commit();
    return d;
  }

  // ---------------------------------------------------------------------------
  // Nursing notes
  // ---------------------------------------------------------------------------

  List<NursingNote> notesFor(String admissionId) =>
      nursingNotes.where((n) => n.admissionId == admissionId).toList()
        ..sort((a, b) => b.at.compareTo(a.at));

  Future<NursingNote> addNursingNote({
    required String admissionId,
    required String category,
    required String text,
  }) async {
    final a = _activeAdmission(admissionId);
    if (text.trim().isEmpty) throw HospitalException('Write the note');
    final n = NursingNote(
      id: newId('NOTE'),
      admissionId: a.id,
      patientId: a.patientId,
      at: DateTime.now(),
      category: category,
      text: text.trim(),
      author: currentUser?.id,
    );
    nursingNotes.add(n);
    await _commit();
    return n;
  }
}
