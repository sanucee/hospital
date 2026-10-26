part of 'models.dart';

/// Level of consciousness (ACVPU): anything other than alert scores 3 in
/// NEWS2.
enum Consciousness { alert, newConfusion, voice, pain, unresponsive }

extension ConsciousnessX on Consciousness {
  String get label => switch (this) {
    Consciousness.alert => 'Alert',
    Consciousness.newConfusion => 'New confusion',
    Consciousness.voice => 'Responds to voice',
    Consciousness.pain => 'Responds to pain',
    Consciousness.unresponsive => 'Unresponsive',
  };
}

enum News2Risk { low, lowMedium, medium, high }

extension News2RiskX on News2Risk {
  String get label => switch (this) {
    News2Risk.low => 'Low',
    News2Risk.lowMedium => 'Low-medium',
    News2Risk.medium => 'Medium',
    News2Risk.high => 'High',
  };

  /// Suggested response, per the NEWS2 clinical response guidance.
  String get response => switch (this) {
    News2Risk.low => 'Continue routine monitoring',
    News2Risk.lowMedium => 'Urgent ward review by a nurse',
    News2Risk.medium => 'Urgent review by a doctor',
    News2Risk.high => 'Emergency assessment; consider critical care',
  };
}

/// A NEWS2 (National Early Warning Score 2, SpO2 scale 1) result.
class News2 {
  const News2(this.score, {required this.complete, required this.anySingle3});

  final int score;

  /// False when a parameter was not recorded (the score is then a minimum).
  final bool complete;

  /// A single parameter scoring 3 raises the risk to at least low-medium.
  final bool anySingle3;

  News2Risk get risk {
    if (score >= 7) return News2Risk.high;
    if (score >= 5) return News2Risk.medium;
    if (anySingle3) return News2Risk.lowMedium;
    return News2Risk.low;
  }

  /// Medium or high risk: the doctor should be alerted.
  bool get needsDoctor => score >= 5;
}

/// One set of observations taken by a nurse.
class VitalsReading {
  VitalsReading({
    required this.id,
    required this.admissionId,
    required this.patientId,
    required this.takenAt,
    this.temperature,
    this.pulse,
    this.respRate,
    this.systolic,
    this.diastolic,
    this.spo2,
    this.onOxygen = false,
    this.consciousness = Consciousness.alert,
    this.painScore,
    this.bloodSugar,
    this.notes = '',
    this.recordedBy,
  });

  final String id;
  final String admissionId;
  final String patientId;
  final DateTime takenAt;
  final double? temperature;
  final int? pulse;
  final int? respRate;
  final int? systolic;
  final int? diastolic;
  final int? spo2;
  final bool onOxygen;
  final Consciousness consciousness;

  /// 0–10.
  final int? painScore;

  /// mmol/L.
  final double? bloodSugar;
  final String notes;
  final String? recordedBy;

  News2 get news2 {
    final parts = <int?>[
      switch (respRate) {
        null => null,
        <= 8 => 3,
        <= 11 => 1,
        <= 20 => 0,
        <= 24 => 2,
        _ => 3,
      },
      switch (spo2) {
        null => null,
        <= 91 => 3,
        <= 93 => 2,
        <= 95 => 1,
        _ => 0,
      },
      onOxygen ? 2 : 0,
      switch (systolic) {
        null => null,
        <= 90 => 3,
        <= 100 => 2,
        <= 110 => 1,
        <= 219 => 0,
        _ => 3,
      },
      switch (pulse) {
        null => null,
        <= 40 => 3,
        <= 50 => 1,
        <= 90 => 0,
        <= 110 => 1,
        <= 130 => 2,
        _ => 3,
      },
      consciousness == Consciousness.alert ? 0 : 3,
      switch (temperature) {
        null => null,
        <= 35.0 => 3,
        <= 36.0 => 1,
        <= 38.0 => 0,
        <= 39.0 => 1,
        _ => 2,
      },
    ];
    final known = parts.whereType<int>();
    return News2(
      known.fold(0, (a, b) => a + b),
      complete: parts.every((p) => p != null),
      anySingle3: known.any((p) => p == 3),
    );
  }

  String get bloodPressure =>
      systolic == null ? '' : '$systolic/${diastolic ?? '-'}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'admissionId': admissionId,
    'patientId': patientId,
    'takenAt': takenAt.toIso8601String(),
    'temperature': temperature,
    'pulse': pulse,
    'respRate': respRate,
    'systolic': systolic,
    'diastolic': diastolic,
    'spo2': spo2,
    'onOxygen': onOxygen,
    'consciousness': consciousness.name,
    'painScore': painScore,
    'bloodSugar': bloodSugar,
    'notes': notes,
    'recordedBy': recordedBy,
  };

  factory VitalsReading.fromJson(Map<String, dynamic> j) => VitalsReading(
    id: j['id'],
    admissionId: j['admissionId'],
    patientId: j['patientId'],
    takenAt: DateTime.parse(j['takenAt']),
    temperature: (j['temperature'] as num?)?.toDouble(),
    pulse: (j['pulse'] as num?)?.toInt(),
    respRate: (j['respRate'] as num?)?.toInt(),
    systolic: (j['systolic'] as num?)?.toInt(),
    diastolic: (j['diastolic'] as num?)?.toInt(),
    spo2: (j['spo2'] as num?)?.toInt(),
    onOxygen: j['onOxygen'] ?? false,
    consciousness: _enumByName(
      Consciousness.values,
      j['consciousness'],
      Consciousness.alert,
    ),
    painScore: (j['painScore'] as num?)?.toInt(),
    bloodSugar: (j['bloodSugar'] as num?)?.toDouble(),
    notes: j['notes'] ?? '',
    recordedBy: j['recordedBy'],
  );
}

const kRoutes = ['Oral', 'IV', 'IM', 'SC', 'Inhaled', 'Topical', 'PR', 'SL'];

/// Standard administration times for each frequency (24 h clock).
const kMedicationSchedules = {
  'Once daily': ['08:00'],
  'Twice daily': ['08:00', '20:00'],
  'Three times daily': ['08:00', '14:00', '20:00'],
  'Four times daily': ['06:00', '12:00', '18:00', '22:00'],
  'Every 6 hours': ['00:00', '06:00', '12:00', '18:00'],
  'Every 8 hours': ['06:00', '14:00', '22:00'],
  'At night': ['22:00'],
  'As needed (PRN)': <String>[],
};

/// A doctor's order for a ward medicine, given by nurses at set times.
class MedicationOrder {
  MedicationOrder({
    required this.id,
    required this.admissionId,
    required this.patientId,
    required this.medicineName,
    required this.dose,
    required this.route,
    required this.frequency,
    required this.times,
    required this.startAt,
    this.medicineId,
    this.instructions = '',
    this.orderedBy,
    this.stoppedAt,
    this.stoppedBy,
  });

  final String id;
  final String admissionId;
  final String patientId;
  final String? medicineId;
  final String medicineName;
  final String dose;
  final String route;
  final String frequency;

  /// Scheduled times as "HH:mm"; empty for as-needed (PRN) orders.
  final List<String> times;
  final DateTime startAt;
  final String instructions;
  final String? orderedBy;
  DateTime? stoppedAt;
  String? stoppedBy;

  bool get isPrn => times.isEmpty;
  bool get isActive => stoppedAt == null;

  /// Scheduled administration times falling on [day], from the start time
  /// until the order is stopped.
  List<DateTime> slotsOn(DateTime day) => [
    for (final t in times)
      if (_slot(day, t) case final s
          when !s.isBefore(startAt.subtract(const Duration(minutes: 59))) &&
              (stoppedAt == null || s.isBefore(stoppedAt!)))
        s,
  ];

  static DateTime _slot(DateTime day, String hhmm) {
    final [h, m] = hhmm.split(':').map(int.parse).toList();
    return DateTime(day.year, day.month, day.day, h, m);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'admissionId': admissionId,
    'patientId': patientId,
    'medicineId': medicineId,
    'medicineName': medicineName,
    'dose': dose,
    'route': route,
    'frequency': frequency,
    'times': times,
    'startAt': startAt.toIso8601String(),
    'instructions': instructions,
    'orderedBy': orderedBy,
    'stoppedAt': stoppedAt?.toIso8601String(),
    'stoppedBy': stoppedBy,
  };

  factory MedicationOrder.fromJson(Map<String, dynamic> j) => MedicationOrder(
    id: j['id'],
    admissionId: j['admissionId'],
    patientId: j['patientId'],
    medicineId: j['medicineId'],
    medicineName: j['medicineName'],
    dose: j['dose'] ?? '',
    route: j['route'] ?? 'Oral',
    frequency: j['frequency'] ?? '',
    times: ((j['times'] as List?) ?? []).cast<String>(),
    startAt: DateTime.parse(j['startAt']),
    instructions: j['instructions'] ?? '',
    orderedBy: j['orderedBy'],
    stoppedAt: _date(j['stoppedAt']),
    stoppedBy: j['stoppedBy'],
  );
}

enum DoseStatus { given, held, refused, missed }

extension DoseStatusX on DoseStatus {
  String get label => switch (this) {
    DoseStatus.given => 'Given',
    DoseStatus.held => 'Held',
    DoseStatus.refused => 'Refused',
    DoseStatus.missed => 'Missed',
  };
}

/// What happened at one administration time (or a PRN dose).
class MedicationDose {
  MedicationDose({
    required this.id,
    required this.orderId,
    required this.admissionId,
    required this.patientId,
    required this.recordedAt,
    required this.status,
    this.scheduledFor,
    this.notes = '',
    this.recordedBy,
  });

  final String id;
  final String orderId;
  final String admissionId;
  final String patientId;

  /// The scheduled slot this dose answers; null for PRN doses.
  final DateTime? scheduledFor;
  final DateTime recordedAt;
  final DoseStatus status;
  final String notes;
  final String? recordedBy;

  Map<String, dynamic> toJson() => {
    'id': id,
    'orderId': orderId,
    'admissionId': admissionId,
    'patientId': patientId,
    'scheduledFor': scheduledFor?.toIso8601String(),
    'recordedAt': recordedAt.toIso8601String(),
    'status': status.name,
    'notes': notes,
    'recordedBy': recordedBy,
  };

  factory MedicationDose.fromJson(Map<String, dynamic> j) => MedicationDose(
    id: j['id'],
    orderId: j['orderId'],
    admissionId: j['admissionId'],
    patientId: j['patientId'],
    scheduledFor: _date(j['scheduledFor']),
    recordedAt: DateTime.parse(j['recordedAt']),
    status: _enumByName(DoseStatus.values, j['status'], DoseStatus.given),
    notes: j['notes'] ?? '',
    recordedBy: j['recordedBy'],
  );
}

const kNoteCategories = [
  'General',
  'Handover',
  'Wound care',
  'Fluid balance',
  'Nutrition',
  'Mobility / falls',
  'Patient education',
];

class NursingNote {
  NursingNote({
    required this.id,
    required this.admissionId,
    required this.patientId,
    required this.at,
    required this.category,
    required this.text,
    this.author,
  });

  final String id;
  final String admissionId;
  final String patientId;
  final DateTime at;
  final String category;
  final String text;
  final String? author;

  Map<String, dynamic> toJson() => {
    'id': id,
    'admissionId': admissionId,
    'patientId': patientId,
    'at': at.toIso8601String(),
    'category': category,
    'text': text,
    'author': author,
  };

  factory NursingNote.fromJson(Map<String, dynamic> j) => NursingNote(
    id: j['id'],
    admissionId: j['admissionId'],
    patientId: j['patientId'],
    at: DateTime.parse(j['at']),
    category: j['category'] ?? 'General',
    text: j['text'] ?? '',
    author: j['author'],
  );
}

/// One recorded change: who did what to which record, and when.
class AuditEntry {
  AuditEntry({
    required this.id,
    required this.at,
    required this.userId,
    required this.userName,
    required this.action,
    required this.collection,
    required this.docId,
    required this.summary,
    this.patientId,
  });

  final String id;
  final DateTime at;
  final String userId;
  final String userName;

  /// created, updated, deleted, or an event such as "signed in".
  final String action;
  final String collection;
  final String docId;
  final String summary;
  final String? patientId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'userId': userId,
    'userName': userName,
    'action': action,
    'collection': collection,
    'docId': docId,
    'summary': summary,
    'patientId': patientId,
  };

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
    id: j['id'],
    at: DateTime.parse(j['at']),
    userId: j['userId'] ?? '',
    userName: j['userName'] ?? '',
    action: j['action'] ?? '',
    collection: j['collection'] ?? '',
    docId: j['docId'] ?? '',
    summary: j['summary'] ?? '',
    patientId: j['patientId'],
  );
}
