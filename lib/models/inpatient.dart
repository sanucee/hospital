part of 'models.dart';

const kRoomTypes = [
  'General ward',
  'Semi-private',
  'Private',
  'ICU',
  'Maternity',
];

/// A ward or room that admitted patients occupy, billed per day.
class Room {
  Room({
    required this.id,
    required this.name,
    required this.type,
    required this.dailyRate,
    this.beds = 1,
  });

  final String id;
  String name;
  String type;
  double dailyRate;
  int beds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'dailyRate': dailyRate,
    'beds': beds,
  };

  factory Room.fromJson(Map<String, dynamic> j) => Room(
    id: j['id'],
    name: j['name'],
    type: j['type'] ?? 'General ward',
    dailyRate: (j['dailyRate'] as num).toDouble(),
    beds: j['beds'] ?? 1,
  );
}

/// A continuous period in one room. Transfers start a new stay.
class RoomStay {
  RoomStay({
    required this.roomId,
    required this.roomName,
    required this.dailyRate,
    required this.from,
    this.to,
  });

  final String roomId;

  /// Name and rate are copied when the stay starts, so later edits to the
  /// room don't change what this patient is charged.
  final String roomName;
  final double dailyRate;
  final DateTime from;
  DateTime? to;

  /// Calendar days between start and end (midnights crossed).
  int calendarDays(DateTime now) =>
      _dayOnly(to ?? now).difference(_dayOnly(from)).inDays;

  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'roomName': roomName,
    'dailyRate': dailyRate,
    'from': from.toIso8601String(),
    'to': to?.toIso8601String(),
  };

  factory RoomStay.fromJson(Map<String, dynamic> j) => RoomStay(
    roomId: j['roomId'],
    roomName: j['roomName'] ?? '',
    dailyRate: (j['dailyRate'] as num).toDouble(),
    from: DateTime.parse(j['from']),
    to: _date(j['to']),
  );
}

class Admission {
  Admission({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.admittedAt,
    required this.stays,
    this.reason = '',
    this.dischargedAt,
    this.dischargeSummary = '',
  });

  final String id;
  final String patientId;
  String doctorId;
  final DateTime admittedAt;
  final List<RoomStay> stays;
  String reason;
  DateTime? dischargedAt;
  String dischargeSummary;

  bool get isActive => dischargedAt == null;
  RoomStay get currentStay => stays.last;

  /// Billable days per stay: one per midnight spent in that room, and at
  /// least one day in total, so a same-day admission is charged one day.
  List<int> billableDays(DateTime now) {
    final days = [for (final s in stays) s.calendarDays(now)];
    if (days.fold(0, (a, b) => a + b) == 0 && days.isNotEmpty) {
      days[days.length - 1] = 1;
    }
    return days;
  }

  /// Room charges so far (the final amount once discharged).
  double roomCharges(DateTime now) {
    final days = billableDays(now);
    var total = 0.0;
    for (var i = 0; i < stays.length; i++) {
      total += days[i] * stays[i].dailyRate;
    }
    return total;
  }

  int totalDays(DateTime now) => billableDays(now).fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'doctorId': doctorId,
    'admittedAt': admittedAt.toIso8601String(),
    'stays': stays.map((s) => s.toJson()).toList(),
    'reason': reason,
    'dischargedAt': dischargedAt?.toIso8601String(),
    'dischargeSummary': dischargeSummary,
  };

  factory Admission.fromJson(Map<String, dynamic> j) => Admission(
    id: j['id'],
    patientId: j['patientId'],
    doctorId: j['doctorId'],
    admittedAt: DateTime.parse(j['admittedAt']),
    stays: (j['stays'] as List).map((e) => RoomStay.fromJson(e)).toList(),
    reason: j['reason'] ?? '',
    dischargedAt: _date(j['dischargedAt']),
    dischargeSummary: j['dischargeSummary'] ?? '',
  );
}

class OperationTheatre {
  OperationTheatre({
    required this.id,
    required this.name,
    required this.hourlyRate,
  });

  final String id;
  String name;

  /// Theatre usage charge per started hour.
  double hourlyRate;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'hourlyRate': hourlyRate,
  };

  factory OperationTheatre.fromJson(Map<String, dynamic> j) => OperationTheatre(
    id: j['id'],
    name: j['name'],
    hourlyRate: (j['hourlyRate'] as num).toDouble(),
  );
}

enum SurgeryStatus { scheduled, inProgress, completed, cancelled }

extension SurgeryStatusX on SurgeryStatus {
  String get label => switch (this) {
    SurgeryStatus.scheduled => 'Scheduled',
    SurgeryStatus.inProgress => 'In theatre',
    SurgeryStatus.completed => 'Completed',
    SurgeryStatus.cancelled => 'Cancelled',
  };
}

class Surgery {
  Surgery({
    required this.id,
    required this.patientId,
    required this.surgeonId,
    required this.theatreId,
    required this.procedure,
    required this.scheduledAt,
    this.estimatedMinutes = 60,
    this.admissionId,
    this.anaesthetist = '',
    this.surgeonFee = 0,
    this.anaesthesiaFee = 0,
    this.status = SurgeryStatus.scheduled,
    this.startedAt,
    this.endedAt,
    this.consumablesCost = 0,
    this.notes = '',
  });

  final String id;
  final String patientId;
  String surgeonId;
  String theatreId;
  String procedure;
  DateTime scheduledAt;
  int estimatedMinutes;

  /// Set when the patient is admitted; theatre charges then go on the
  /// admission's bill. Otherwise it's a day case with its own bill.
  String? admissionId;
  String anaesthetist;
  double surgeonFee;
  double anaesthesiaFee;
  SurgeryStatus status;
  DateTime? startedAt;
  DateTime? endedAt;
  double consumablesCost;
  String notes;

  DateTime get plannedEnd =>
      scheduledAt.add(Duration(minutes: estimatedMinutes));

  /// Theatre time billed: actual duration rounded up to whole hours, with a
  /// one-hour minimum.
  int get billableHours {
    if (startedAt == null || endedAt == null) {
      return (estimatedMinutes / 60).ceil().clamp(1, 1 << 20);
    }
    final minutes = endedAt!.difference(startedAt!).inMinutes;
    return (minutes / 60).ceil().clamp(1, 1 << 20);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'surgeonId': surgeonId,
    'theatreId': theatreId,
    'procedure': procedure,
    'scheduledAt': scheduledAt.toIso8601String(),
    'estimatedMinutes': estimatedMinutes,
    'admissionId': admissionId,
    'anaesthetist': anaesthetist,
    'surgeonFee': surgeonFee,
    'anaesthesiaFee': anaesthesiaFee,
    'status': status.name,
    'startedAt': startedAt?.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'consumablesCost': consumablesCost,
    'notes': notes,
  };

  factory Surgery.fromJson(Map<String, dynamic> j) => Surgery(
    id: j['id'],
    patientId: j['patientId'],
    surgeonId: j['surgeonId'],
    theatreId: j['theatreId'],
    procedure: j['procedure'],
    scheduledAt: DateTime.parse(j['scheduledAt']),
    estimatedMinutes: j['estimatedMinutes'] ?? 60,
    admissionId: j['admissionId'],
    anaesthetist: j['anaesthetist'] ?? '',
    surgeonFee: (j['surgeonFee'] as num?)?.toDouble() ?? 0,
    anaesthesiaFee: (j['anaesthesiaFee'] as num?)?.toDouble() ?? 0,
    status: _enumByName(
      SurgeryStatus.values,
      j['status'],
      SurgeryStatus.scheduled,
    ),
    startedAt: _date(j['startedAt']),
    endedAt: _date(j['endedAt']),
    consumablesCost: (j['consumablesCost'] as num?)?.toDouble() ?? 0,
    notes: j['notes'] ?? '',
  );
}
