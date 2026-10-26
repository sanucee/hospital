part of 'models.dart';

const kModalities = [
  'X-ray',
  'Ultrasound',
  'CT',
  'MRI',
  'Mammography',
  'Fluoroscopy',
];

/// An examination the imaging department offers.
class ImagingStudy {
  ImagingStudy({
    required this.id,
    required this.name,
    required this.modality,
    required this.price,
    this.bodyPart = '',
    this.preparation = '',
  });

  final String id;
  String name;
  String modality;
  double price;
  String bodyPart;

  /// Told to the patient when the study is booked, e.g. "Full bladder".
  String preparation;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'modality': modality,
    'price': price,
    'bodyPart': bodyPart,
    'preparation': preparation,
  };

  factory ImagingStudy.fromJson(Map<String, dynamic> j) => ImagingStudy(
    id: j['id'],
    name: j['name'],
    modality: j['modality'] ?? 'X-ray',
    price: (j['price'] as num).toDouble(),
    bodyPart: j['bodyPart'] ?? '',
    preparation: j['preparation'] ?? '',
  );
}

enum ImagingStatus { ordered, scheduled, performed, reported, cancelled }

extension ImagingStatusX on ImagingStatus {
  String get label => switch (this) {
    ImagingStatus.ordered => 'Requested',
    ImagingStatus.scheduled => 'Booked',
    ImagingStatus.performed => 'Awaiting report',
    ImagingStatus.reported => 'Reported',
    ImagingStatus.cancelled => 'Cancelled',
  };
}

/// A doctor's request for an imaging study, through to the report.
class ImagingOrder {
  ImagingOrder({
    required this.id,
    required this.consultationId,
    required this.patientId,
    required this.doctorId,
    required this.studyId,
    required this.studyName,
    required this.modality,
    required this.price,
    required this.orderedAt,
    this.urgent = false,
    this.clinicalNotes = '',
    this.status = ImagingStatus.ordered,
    this.scheduledAt,
    this.performedAt,
    this.radiographerId,
    this.findings = '',
    this.impression = '',
    this.abnormal = false,
    this.reportedAt,
    this.reportedBy,
    this.reviewedByDoctor = false,
  });

  final String id;
  final String consultationId;
  final String patientId;
  final String doctorId;
  final String studyId;

  /// Copied at order time, like lab orders, so catalogue edits don't change
  /// history or bills.
  final String studyName;
  final String modality;
  final double price;
  final DateTime orderedAt;
  bool urgent;
  String clinicalNotes;
  ImagingStatus status;
  DateTime? scheduledAt;
  DateTime? performedAt;
  String? radiographerId;
  String findings;
  String impression;
  bool abnormal;
  DateTime? reportedAt;
  String? reportedBy;
  bool reviewedByDoctor;

  bool get isPending =>
      status == ImagingStatus.ordered ||
      status == ImagingStatus.scheduled ||
      status == ImagingStatus.performed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'consultationId': consultationId,
    'patientId': patientId,
    'doctorId': doctorId,
    'studyId': studyId,
    'studyName': studyName,
    'modality': modality,
    'price': price,
    'orderedAt': orderedAt.toIso8601String(),
    'urgent': urgent,
    'clinicalNotes': clinicalNotes,
    'status': status.name,
    'scheduledAt': scheduledAt?.toIso8601String(),
    'performedAt': performedAt?.toIso8601String(),
    'radiographerId': radiographerId,
    'findings': findings,
    'impression': impression,
    'abnormal': abnormal,
    'reportedAt': reportedAt?.toIso8601String(),
    'reportedBy': reportedBy,
    'reviewedByDoctor': reviewedByDoctor,
  };

  factory ImagingOrder.fromJson(Map<String, dynamic> j) => ImagingOrder(
    id: j['id'],
    consultationId: j['consultationId'],
    patientId: j['patientId'],
    doctorId: j['doctorId'],
    studyId: j['studyId'],
    studyName: j['studyName'],
    modality: j['modality'] ?? 'X-ray',
    price: (j['price'] as num).toDouble(),
    orderedAt: DateTime.parse(j['orderedAt']),
    urgent: j['urgent'] ?? false,
    clinicalNotes: j['clinicalNotes'] ?? '',
    status: _enumByName(
      ImagingStatus.values,
      j['status'],
      ImagingStatus.ordered,
    ),
    scheduledAt: _date(j['scheduledAt']),
    performedAt: _date(j['performedAt']),
    radiographerId: j['radiographerId'],
    findings: j['findings'] ?? '',
    impression: j['impression'] ?? '',
    abnormal: j['abnormal'] ?? false,
    reportedAt: _date(j['reportedAt']),
    reportedBy: j['reportedBy'],
    reviewedByDoctor: j['reviewedByDoctor'] ?? false,
  );
}
