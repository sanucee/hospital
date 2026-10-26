part of 'models.dart';

/// Five-level triage: how quickly a patient arriving at the emergency
/// department must be seen by a doctor.
enum TriageLevel { immediate, veryUrgent, urgent, standard, nonUrgent }

extension TriageLevelX on TriageLevel {
  String get label => switch (this) {
    TriageLevel.immediate => 'Immediate',
    TriageLevel.veryUrgent => 'Very urgent',
    TriageLevel.urgent => 'Urgent',
    TriageLevel.standard => 'Standard',
    TriageLevel.nonUrgent => 'Non-urgent',
  };

  /// The usual triage colour, for the board.
  String get colour => switch (this) {
    TriageLevel.immediate => 'Red',
    TriageLevel.veryUrgent => 'Orange',
    TriageLevel.urgent => 'Yellow',
    TriageLevel.standard => 'Green',
    TriageLevel.nonUrgent => 'Blue',
  };

  /// Longest acceptable wait from arrival to being seen by a doctor.
  Duration get target => switch (this) {
    TriageLevel.immediate => Duration.zero,
    TriageLevel.veryUrgent => const Duration(minutes: 10),
    TriageLevel.urgent => const Duration(minutes: 60),
    TriageLevel.standard => const Duration(minutes: 120),
    TriageLevel.nonUrgent => const Duration(minutes: 240),
  };
}

const kArrivalModes = [
  'Walk-in',
  'Ambulance',
  'Police',
  'Referred',
  'Brought by family',
];

enum EmergencyStatus { waitingTriage, waitingDoctor, beingSeen, closed }

extension EmergencyStatusX on EmergencyStatus {
  String get label => switch (this) {
    EmergencyStatus.waitingTriage => 'Awaiting triage',
    EmergencyStatus.waitingDoctor => 'Awaiting doctor',
    EmergencyStatus.beingSeen => 'With doctor',
    EmergencyStatus.closed => 'Left the department',
  };
}

/// How an emergency visit ended.
enum EmergencyOutcome {
  discharged,
  admitted,
  referred,
  leftWithoutBeingSeen,
  died,
}

extension EmergencyOutcomeX on EmergencyOutcome {
  String get label => switch (this) {
    EmergencyOutcome.discharged => 'Discharged home',
    EmergencyOutcome.admitted => 'Admitted',
    EmergencyOutcome.referred => 'Referred elsewhere',
    EmergencyOutcome.leftWithoutBeingSeen => 'Left without being seen',
    EmergencyOutcome.died => 'Died',
  };
}

/// One attendance at the emergency department, from arrival to disposition.
///
/// The doctor's assessment is an ordinary [Consultation] (linked by
/// [consultationId]), so lab tests, imaging, prescriptions and the bill work
/// exactly as in the clinic.
class EmergencyVisit {
  EmergencyVisit({
    required this.id,
    required this.patientId,
    required this.arrivedAt,
    required this.complaint,
    this.arrivalMode = 'Walk-in',
    this.status = EmergencyStatus.waitingTriage,
    this.triageLevel,
    this.triagedAt,
    this.triagedBy,
    this.triageNotes = '',
    this.temperature,
    this.pulse,
    this.respRate,
    this.systolic,
    this.diastolic,
    this.spo2,
    this.painScore,
    this.doctorId,
    this.seenAt,
    this.consultationId,
    this.outcome,
    this.closedAt,
    this.outcomeNotes = '',
    this.admissionId,
    this.registeredBy,
  });

  final String id;
  final String patientId;
  final DateTime arrivedAt;
  String complaint;
  String arrivalMode;
  EmergencyStatus status;

  TriageLevel? triageLevel;
  DateTime? triagedAt;
  String? triagedBy;
  String triageNotes;

  // Triage observations.
  double? temperature;
  int? pulse;
  int? respRate;
  int? systolic;
  int? diastolic;
  int? spo2;
  int? painScore;

  String? doctorId;
  DateTime? seenAt;
  String? consultationId;

  EmergencyOutcome? outcome;
  DateTime? closedAt;
  String outcomeNotes;
  String? admissionId;
  String? registeredBy;

  bool get isOpen => status != EmergencyStatus.closed;

  /// When the patient should be seen by, once triaged.
  DateTime? get seeBy => triageLevel == null
      ? null
      : (triagedAt ?? arrivedAt).add(triageLevel!.target);

  /// True when still waiting for a doctor past the triage target.
  bool overdue(DateTime now) =>
      status == EmergencyStatus.waitingDoctor &&
      seeBy != null &&
      now.isAfter(seeBy!);

  /// Arrival to being seen (or to now, while waiting).
  Duration waited(DateTime now) =>
      (seenAt ?? closedAt ?? now).difference(arrivedAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'arrivedAt': arrivedAt.toIso8601String(),
    'complaint': complaint,
    'arrivalMode': arrivalMode,
    'status': status.name,
    'triageLevel': triageLevel?.name,
    'triagedAt': triagedAt?.toIso8601String(),
    'triagedBy': triagedBy,
    'triageNotes': triageNotes,
    'temperature': temperature,
    'pulse': pulse,
    'respRate': respRate,
    'systolic': systolic,
    'diastolic': diastolic,
    'spo2': spo2,
    'painScore': painScore,
    'doctorId': doctorId,
    'seenAt': seenAt?.toIso8601String(),
    'consultationId': consultationId,
    'outcome': outcome?.name,
    'closedAt': closedAt?.toIso8601String(),
    'outcomeNotes': outcomeNotes,
    'admissionId': admissionId,
    'registeredBy': registeredBy,
  };

  factory EmergencyVisit.fromJson(Map<String, dynamic> j) => EmergencyVisit(
    id: j['id'],
    patientId: j['patientId'],
    arrivedAt: DateTime.parse(j['arrivedAt']),
    complaint: j['complaint'] ?? '',
    arrivalMode: j['arrivalMode'] ?? 'Walk-in',
    status: _enumByName(
      EmergencyStatus.values,
      j['status'],
      EmergencyStatus.waitingTriage,
    ),
    triageLevel: j['triageLevel'] == null
        ? null
        : _enumByName(TriageLevel.values, j['triageLevel'], TriageLevel.urgent),
    triagedAt: _date(j['triagedAt']),
    triagedBy: j['triagedBy'],
    triageNotes: j['triageNotes'] ?? '',
    temperature: (j['temperature'] as num?)?.toDouble(),
    pulse: (j['pulse'] as num?)?.toInt(),
    respRate: (j['respRate'] as num?)?.toInt(),
    systolic: (j['systolic'] as num?)?.toInt(),
    diastolic: (j['diastolic'] as num?)?.toInt(),
    spo2: (j['spo2'] as num?)?.toInt(),
    painScore: (j['painScore'] as num?)?.toInt(),
    doctorId: j['doctorId'],
    seenAt: _date(j['seenAt']),
    consultationId: j['consultationId'],
    outcome: j['outcome'] == null
        ? null
        : _enumByName(
            EmergencyOutcome.values,
            j['outcome'],
            EmergencyOutcome.discharged,
          ),
    closedAt: _date(j['closedAt']),
    outcomeNotes: j['outcomeNotes'] ?? '',
    admissionId: j['admissionId'],
    registeredBy: j['registeredBy'],
  );
}
