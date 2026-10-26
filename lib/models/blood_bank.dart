part of 'models.dart';

const kBloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

enum BloodComponent { wholeBlood, redCells, platelets, plasma, cryo }

extension BloodComponentX on BloodComponent {
  String get label => switch (this) {
    BloodComponent.wholeBlood => 'Whole blood',
    BloodComponent.redCells => 'Packed red cells',
    BloodComponent.platelets => 'Platelets',
    BloodComponent.plasma => 'Fresh frozen plasma',
    BloodComponent.cryo => 'Cryoprecipitate',
  };

  /// How long a unit keeps from collection.
  Duration get shelfLife => switch (this) {
    BloodComponent.wholeBlood => const Duration(days: 35),
    BloodComponent.redCells => const Duration(days: 42),
    BloodComponent.platelets => const Duration(days: 5),
    BloodComponent.plasma => const Duration(days: 365),
    BloodComponent.cryo => const Duration(days: 365),
  };

  int get defaultVolumeMl => switch (this) {
    BloodComponent.wholeBlood => 450,
    BloodComponent.redCells => 300,
    BloodComponent.platelets => 50,
    BloodComponent.plasma => 250,
    BloodComponent.cryo => 15,
  };

  /// Processing and cross-match fee charged per unit issued.
  double get fee => switch (this) {
    BloodComponent.wholeBlood => 60,
    BloodComponent.redCells => 70,
    BloodComponent.platelets => 80,
    BloodComponent.plasma => 50,
    BloodComponent.cryo => 40,
  };

  /// Plasma components follow the reverse ABO rules of red cells.
  bool get isPlasma =>
      this == BloodComponent.plasma || this == BloodComponent.cryo;
}

/// Whether a unit of [donor] blood group can be given to a patient of group
/// [recipient] as [component]. Groups are written like "AB-".
bool bloodCompatible(String donor, String recipient, BloodComponent component) {
  final d = _parseGroup(donor);
  final r = _parseGroup(recipient);
  if (d == null || r == null) return false;
  final (dAbo, dPos) = d;
  final (rAbo, rPos) = r;
  // Rh-negative patients get Rh-negative cells; plasma carries no Rh cells.
  if (!component.isPlasma && dPos && !rPos) return false;
  bool has(String abo, String antigen) => abo.contains(antigen);
  switch (component) {
    case BloodComponent.wholeBlood:
      // Whole blood carries both cells and plasma: same ABO group only.
      return dAbo == rAbo;
    case BloodComponent.redCells:
      // The donor's cells may not carry an antigen the patient lacks.
      return (!has(dAbo, 'A') || has(rAbo, 'A')) &&
          (!has(dAbo, 'B') || has(rAbo, 'B'));
    case BloodComponent.platelets:
      return true;
    case BloodComponent.plasma:
    case BloodComponent.cryo:
      // The donor's plasma may not carry antibodies to the patient's cells.
      return (!has(rAbo, 'A') || has(dAbo, 'A')) &&
          (!has(rAbo, 'B') || has(dAbo, 'B'));
  }
}

(String, bool)? _parseGroup(String g) {
  final s = g.trim().toUpperCase();
  if (!kBloodGroups.contains(s)) return null;
  final abo = s.substring(0, s.length - 1);
  return (abo == 'O' ? '' : abo, s.endsWith('+'));
}

class BloodDonor {
  BloodDonor({
    required this.id,
    required this.name,
    required this.bloodGroup,
    this.phone = '',
    this.gender = '',
    this.lastDonationAt,
    this.deferredUntil,
    this.notes = '',
    this.patientId,
  });

  final String id;
  String name;
  String bloodGroup;
  String phone;
  String gender;
  DateTime? lastDonationAt;

  /// Temporarily unable to donate (illness, travel...) until this date.
  DateTime? deferredUntil;
  String notes;

  /// Set when the donor is also a registered patient.
  String? patientId;

  /// Minimum gap between whole-blood donations.
  static const donationInterval = Duration(days: 56);

  /// The first day this donor may give blood again.
  DateTime? nextEligible() {
    final dates = [
      if (lastDonationAt != null)
        _dayOnly(lastDonationAt!).add(donationInterval),
      if (deferredUntil != null) _dayOnly(deferredUntil!),
    ];
    if (dates.isEmpty) return null;
    return dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  bool canDonateOn(DateTime day) {
    final next = nextEligible();
    return next == null || !_dayOnly(day).isBefore(next);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bloodGroup': bloodGroup,
    'phone': phone,
    'gender': gender,
    'lastDonationAt': lastDonationAt?.toIso8601String(),
    'deferredUntil': deferredUntil?.toIso8601String(),
    'notes': notes,
    'patientId': patientId,
  };

  factory BloodDonor.fromJson(Map<String, dynamic> j) => BloodDonor(
    id: j['id'],
    name: j['name'],
    bloodGroup: j['bloodGroup'] ?? '',
    phone: j['phone'] ?? '',
    gender: j['gender'] ?? '',
    lastDonationAt: _date(j['lastDonationAt']),
    deferredUntil: _date(j['deferredUntil']),
    notes: j['notes'] ?? '',
    patientId: j['patientId'],
  );
}

enum BloodUnitStatus { quarantine, available, reserved, issued, discarded }

extension BloodUnitStatusX on BloodUnitStatus {
  String get label => switch (this) {
    BloodUnitStatus.quarantine => 'Awaiting screening',
    BloodUnitStatus.available => 'Available',
    BloodUnitStatus.reserved => 'Cross-matched',
    BloodUnitStatus.issued => 'Issued',
    BloodUnitStatus.discarded => 'Discarded',
  };
}

/// A bag of blood or a blood component in the blood bank.
class BloodUnit {
  BloodUnit({
    required this.id,
    required this.unitNumber,
    required this.bloodGroup,
    required this.component,
    required this.collectedAt,
    required this.expiresAt,
    this.volumeMl = 450,
    this.donorId,
    this.source = 'Donation',
    this.status = BloodUnitStatus.quarantine,
    this.screenedAt,
    this.screenedBy,
    this.discardReason = '',
    this.requestId,
    this.issuedAt,
    this.issuedBy,
    this.patientId,
  });

  final String id;

  /// Bag label, e.g. `BU-00012`.
  final String unitNumber;
  final String bloodGroup;
  final BloodComponent component;
  final DateTime collectedAt;
  final DateTime expiresAt;
  int volumeMl;
  String? donorId;

  /// "Donation", or the blood service it was bought from.
  String source;
  BloodUnitStatus status;

  /// Infection screening (HIV, hepatitis B/C, syphilis, malaria).
  DateTime? screenedAt;
  String? screenedBy;
  String discardReason;

  /// The request it is cross-matched for or was issued to.
  String? requestId;
  DateTime? issuedAt;
  String? issuedBy;
  String? patientId;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  /// In stock and usable now.
  bool usable(DateTime now) =>
      status == BloodUnitStatus.available && !isExpired(now);

  Map<String, dynamic> toJson() => {
    'id': id,
    'unitNumber': unitNumber,
    'bloodGroup': bloodGroup,
    'component': component.name,
    'collectedAt': collectedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'volumeMl': volumeMl,
    'donorId': donorId,
    'source': source,
    'status': status.name,
    'screenedAt': screenedAt?.toIso8601String(),
    'screenedBy': screenedBy,
    'discardReason': discardReason,
    'requestId': requestId,
    'issuedAt': issuedAt?.toIso8601String(),
    'issuedBy': issuedBy,
    'patientId': patientId,
  };

  factory BloodUnit.fromJson(Map<String, dynamic> j) => BloodUnit(
    id: j['id'],
    unitNumber: j['unitNumber'],
    bloodGroup: j['bloodGroup'],
    component: _enumByName(
      BloodComponent.values,
      j['component'],
      BloodComponent.wholeBlood,
    ),
    collectedAt: DateTime.parse(j['collectedAt']),
    expiresAt: DateTime.parse(j['expiresAt']),
    volumeMl: (j['volumeMl'] as num?)?.toInt() ?? 450,
    donorId: j['donorId'],
    source: j['source'] ?? 'Donation',
    status: _enumByName(
      BloodUnitStatus.values,
      j['status'],
      BloodUnitStatus.quarantine,
    ),
    screenedAt: _date(j['screenedAt']),
    screenedBy: j['screenedBy'],
    discardReason: j['discardReason'] ?? '',
    requestId: j['requestId'],
    issuedAt: _date(j['issuedAt']),
    issuedBy: j['issuedBy'],
    patientId: j['patientId'],
  );
}

enum BloodRequestStatus { pending, reserved, issued, cancelled }

extension BloodRequestStatusX on BloodRequestStatus {
  String get label => switch (this) {
    BloodRequestStatus.pending => 'Awaiting cross-match',
    BloodRequestStatus.reserved => 'Ready to issue',
    BloodRequestStatus.issued => 'Issued',
    BloodRequestStatus.cancelled => 'Cancelled',
  };
}

const kBloodUrgencies = ['Routine', 'Urgent', 'Emergency'];

/// A doctor's request for blood for a patient.
class BloodRequest {
  BloodRequest({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.component,
    required this.units,
    required this.requestedAt,
    this.urgency = 'Routine',
    this.indication = '',
    this.consultationId,
    this.admissionId,
    this.status = BloodRequestStatus.pending,
    List<String>? unitIds,
    this.crossmatchedBy,
    this.crossmatchedAt,
    this.issuedAt,
    this.issuedBy,
    this.cancelReason = '',
  }) : unitIds = unitIds ?? [];

  final String id;
  final String patientId;
  final String doctorId;
  final BloodComponent component;
  final int units;
  final DateTime requestedAt;
  String urgency;
  String indication;

  /// Where the charge goes: the admission's bill, else the visit's.
  String? consultationId;
  String? admissionId;
  BloodRequestStatus status;
  final List<String> unitIds;
  String? crossmatchedBy;
  DateTime? crossmatchedAt;
  DateTime? issuedAt;
  String? issuedBy;
  String cancelReason;

  bool get isOpen =>
      status == BloodRequestStatus.pending ||
      status == BloodRequestStatus.reserved;

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'doctorId': doctorId,
    'component': component.name,
    'units': units,
    'requestedAt': requestedAt.toIso8601String(),
    'urgency': urgency,
    'indication': indication,
    'consultationId': consultationId,
    'admissionId': admissionId,
    'status': status.name,
    'unitIds': unitIds,
    'crossmatchedBy': crossmatchedBy,
    'crossmatchedAt': crossmatchedAt?.toIso8601String(),
    'issuedAt': issuedAt?.toIso8601String(),
    'issuedBy': issuedBy,
    'cancelReason': cancelReason,
  };

  factory BloodRequest.fromJson(Map<String, dynamic> j) => BloodRequest(
    id: j['id'],
    patientId: j['patientId'],
    doctorId: j['doctorId'],
    component: _enumByName(
      BloodComponent.values,
      j['component'],
      BloodComponent.redCells,
    ),
    units: (j['units'] as num).toInt(),
    requestedAt: DateTime.parse(j['requestedAt']),
    urgency: j['urgency'] ?? 'Routine',
    indication: j['indication'] ?? '',
    consultationId: j['consultationId'],
    admissionId: j['admissionId'],
    status: _enumByName(
      BloodRequestStatus.values,
      j['status'],
      BloodRequestStatus.pending,
    ),
    unitIds: (j['unitIds'] as List?)?.cast<String>() ?? [],
    crossmatchedBy: j['crossmatchedBy'],
    crossmatchedAt: _date(j['crossmatchedAt']),
    issuedAt: _date(j['issuedAt']),
    issuedBy: j['issuedBy'],
    cancelReason: j['cancelReason'] ?? '',
  );
}
