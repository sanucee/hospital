/// Domain models for the hospital system.
///
/// Every model serialises to and from JSON so the whole hospital state can be
/// persisted as a single document (see `HospitalStore`).
library;

part 'hr_finance.dart';
part 'inpatient.dart';

enum UserRole {
  admin,
  receptionist,
  doctor,
  labTechnician,
  pharmacist,
  nurse,
  accountant,

  /// Cleaners, security, porters...: on the staff list and payroll, but
  /// without access to the app.
  supportStaff,
}

extension UserRoleX on UserRole {
  String get label => switch (this) {
    UserRole.admin => 'Administrator',
    UserRole.receptionist => 'Reception',
    UserRole.doctor => 'Doctor',
    UserRole.labTechnician => 'Laboratory',
    UserRole.pharmacist => 'Pharmacy',
    UserRole.nurse => 'Nurse',
    UserRole.accountant => 'Accounts',
    UserRole.supportStaff => 'Support staff',
  };

  bool get canSignIn => this != UserRole.supportStaff;
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

DateTime? _date(dynamic v) => v == null ? null : DateTime.parse(v as String);

class StaffUser {
  StaffUser({
    required this.id,
    required this.name,
    required this.username,
    required this.password,
    required this.role,
    this.specialization,
    this.consultationFee = 0,
    this.email = '',
    this.authUid,
    this.department = '',
    this.designation = '',
    this.phone = '',
    this.joinedOn,
    this.active = true,
  });

  final String id;
  String name;
  String username;

  /// Only used in local mode; with Firebase, sign-in is handled by Firebase
  /// Auth and no password is stored.
  String password;
  UserRole role;

  /// Only meaningful for doctors.
  String? specialization;
  double consultationFee;

  /// Sign-in email (Firebase mode).
  String email;

  /// Firebase Auth uid; null when this staff member has no login.
  String? authUid;

  // HR details. Salaries are kept separately (see [SalaryStructure]) so that
  // only administrators and accounts can read them.
  String department;
  String designation;
  String phone;
  DateTime? joinedOn;

  /// Inactive staff (left the hospital) can't sign in and aren't paid.
  bool active;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'username': username,
    'password': password,
    'role': role.name,
    'specialization': specialization,
    'consultationFee': consultationFee,
    'email': email,
    'authUid': authUid,
    'department': department,
    'designation': designation,
    'phone': phone,
    'joinedOn': joinedOn?.toIso8601String(),
    'active': active,
  };

  factory StaffUser.fromJson(Map<String, dynamic> j) => StaffUser(
    id: j['id'],
    name: j['name'],
    username: j['username'],
    password: j['password'],
    role: _enumByName(UserRole.values, j['role'], UserRole.receptionist),
    specialization: j['specialization'],
    consultationFee: (j['consultationFee'] as num?)?.toDouble() ?? 0,
    email: j['email'] ?? '',
    authUid: j['authUid'],
    department: j['department'] ?? '',
    designation: j['designation'] ?? '',
    phone: j['phone'] ?? '',
    joinedOn: _date(j['joinedOn']),
    active: j['active'] ?? true,
  );
}

class Patient {
  Patient({
    required this.id,
    required this.mrn,
    required this.name,
    required this.dateOfBirth,
    required this.gender,
    required this.phone,
    this.address = '',
    this.bloodGroup = '',
    this.allergies = '',
    required this.registeredAt,
  });

  final String id;

  /// Medical record number shown to staff, e.g. `MRN-00012`.
  final String mrn;
  String name;
  DateTime dateOfBirth;
  String gender;
  String phone;
  String address;
  String bloodGroup;
  String allergies;
  final DateTime registeredAt;

  int get age {
    final now = DateTime.now();
    var years = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      years--;
    }
    return years;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'mrn': mrn,
    'name': name,
    'dateOfBirth': dateOfBirth.toIso8601String(),
    'gender': gender,
    'phone': phone,
    'address': address,
    'bloodGroup': bloodGroup,
    'allergies': allergies,
    'registeredAt': registeredAt.toIso8601String(),
  };

  factory Patient.fromJson(Map<String, dynamic> j) => Patient(
    id: j['id'],
    mrn: j['mrn'],
    name: j['name'],
    dateOfBirth: DateTime.parse(j['dateOfBirth']),
    gender: j['gender'],
    phone: j['phone'],
    address: j['address'] ?? '',
    bloodGroup: j['bloodGroup'] ?? '',
    allergies: j['allergies'] ?? '',
    registeredAt: DateTime.parse(j['registeredAt']),
  );
}

enum AppointmentStatus {
  scheduled,
  checkedIn,
  inConsultation,
  completed,
  cancelled,
}

extension AppointmentStatusX on AppointmentStatus {
  String get label => switch (this) {
    AppointmentStatus.scheduled => 'Scheduled',
    AppointmentStatus.checkedIn => 'Waiting',
    AppointmentStatus.inConsultation => 'In consultation',
    AppointmentStatus.completed => 'Completed',
    AppointmentStatus.cancelled => 'Cancelled',
  };
}

class Appointment {
  Appointment({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.scheduledAt,
    this.reason = '',
    this.status = AppointmentStatus.scheduled,
    this.tokenNumber,
  });

  final String id;
  final String patientId;
  String doctorId;
  DateTime scheduledAt;
  String reason;
  AppointmentStatus status;

  /// Queue number assigned at check-in.
  int? tokenNumber;

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'doctorId': doctorId,
    'scheduledAt': scheduledAt.toIso8601String(),
    'reason': reason,
    'status': status.name,
    'tokenNumber': tokenNumber,
  };

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
    id: j['id'],
    patientId: j['patientId'],
    doctorId: j['doctorId'],
    scheduledAt: DateTime.parse(j['scheduledAt']),
    reason: j['reason'] ?? '',
    status: _enumByName(
      AppointmentStatus.values,
      j['status'],
      AppointmentStatus.scheduled,
    ),
    tokenNumber: j['tokenNumber'],
  );
}

class Vitals {
  Vitals({
    this.temperature = '',
    this.bloodPressure = '',
    this.pulse = '',
    this.weight = '',
    this.spo2 = '',
  });

  String temperature;
  String bloodPressure;
  String pulse;
  String weight;
  String spo2;

  bool get isEmpty => [
    temperature,
    bloodPressure,
    pulse,
    weight,
    spo2,
  ].every((v) => v.trim().isEmpty);

  Map<String, dynamic> toJson() => {
    'temperature': temperature,
    'bloodPressure': bloodPressure,
    'pulse': pulse,
    'weight': weight,
    'spo2': spo2,
  };

  factory Vitals.fromJson(Map<String, dynamic>? j) => j == null
      ? Vitals()
      : Vitals(
          temperature: j['temperature'] ?? '',
          bloodPressure: j['bloodPressure'] ?? '',
          pulse: j['pulse'] ?? '',
          weight: j['weight'] ?? '',
          spo2: j['spo2'] ?? '',
        );
}

/// A doctor's encounter with a patient. Lab orders, prescriptions and the
/// invoice all hang off a consultation, which is what links the departments.
class Consultation {
  Consultation({
    required this.id,
    required this.patientId,
    required this.doctorId,
    this.appointmentId,
    required this.startedAt,
    this.completedAt,
    Vitals? vitals,
    this.complaints = '',
    this.diagnosis = '',
    this.notes = '',
    this.followUpDate,
  }) : vitals = vitals ?? Vitals();

  final String id;
  final String patientId;
  final String doctorId;
  final String? appointmentId;
  final DateTime startedAt;
  DateTime? completedAt;
  Vitals vitals;
  String complaints;
  String diagnosis;
  String notes;
  DateTime? followUpDate;

  bool get isOpen => completedAt == null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'doctorId': doctorId,
    'appointmentId': appointmentId,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'vitals': vitals.toJson(),
    'complaints': complaints,
    'diagnosis': diagnosis,
    'notes': notes,
    'followUpDate': followUpDate?.toIso8601String(),
  };

  factory Consultation.fromJson(Map<String, dynamic> j) => Consultation(
    id: j['id'],
    patientId: j['patientId'],
    doctorId: j['doctorId'],
    appointmentId: j['appointmentId'],
    startedAt: DateTime.parse(j['startedAt']),
    completedAt: _date(j['completedAt']),
    vitals: Vitals.fromJson(j['vitals']),
    complaints: j['complaints'] ?? '',
    diagnosis: j['diagnosis'] ?? '',
    notes: j['notes'] ?? '',
    followUpDate: _date(j['followUpDate']),
  );
}

/// An entry in the laboratory's test catalogue.
class LabTest {
  LabTest({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.unit = '',
    this.referenceRange = '',
    this.sampleType = 'Blood',
  });

  final String id;
  String name;
  String category;
  double price;
  String unit;
  String referenceRange;
  String sampleType;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'price': price,
    'unit': unit,
    'referenceRange': referenceRange,
    'sampleType': sampleType,
  };

  factory LabTest.fromJson(Map<String, dynamic> j) => LabTest(
    id: j['id'],
    name: j['name'],
    category: j['category'],
    price: (j['price'] as num).toDouble(),
    unit: j['unit'] ?? '',
    referenceRange: j['referenceRange'] ?? '',
    sampleType: j['sampleType'] ?? 'Blood',
  );
}

enum LabOrderStatus { ordered, sampleCollected, completed, cancelled }

extension LabOrderStatusX on LabOrderStatus {
  String get label => switch (this) {
    LabOrderStatus.ordered => 'Awaiting sample',
    LabOrderStatus.sampleCollected => 'Processing',
    LabOrderStatus.completed => 'Result ready',
    LabOrderStatus.cancelled => 'Cancelled',
  };
}

class LabOrder {
  LabOrder({
    required this.id,
    required this.consultationId,
    required this.patientId,
    required this.doctorId,
    required this.testId,
    required this.testName,
    required this.price,
    required this.orderedAt,
    this.urgent = false,
    this.clinicalNotes = '',
    this.status = LabOrderStatus.ordered,
    this.sampleCollectedAt,
    this.completedAt,
    this.result = '',
    this.resultRemarks = '',
    this.abnormal = false,
    this.technicianId,
    this.reviewedByDoctor = false,
  });

  final String id;
  final String consultationId;
  final String patientId;
  final String doctorId;
  final String testId;

  /// Name and price are copied at order time so later catalogue edits don't
  /// rewrite history or invoices.
  final String testName;
  final double price;
  final DateTime orderedAt;
  bool urgent;
  String clinicalNotes;
  LabOrderStatus status;
  DateTime? sampleCollectedAt;
  DateTime? completedAt;
  String result;
  String resultRemarks;
  bool abnormal;
  String? technicianId;
  bool reviewedByDoctor;

  Map<String, dynamic> toJson() => {
    'id': id,
    'consultationId': consultationId,
    'patientId': patientId,
    'doctorId': doctorId,
    'testId': testId,
    'testName': testName,
    'price': price,
    'orderedAt': orderedAt.toIso8601String(),
    'urgent': urgent,
    'clinicalNotes': clinicalNotes,
    'status': status.name,
    'sampleCollectedAt': sampleCollectedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'result': result,
    'resultRemarks': resultRemarks,
    'abnormal': abnormal,
    'technicianId': technicianId,
    'reviewedByDoctor': reviewedByDoctor,
  };

  factory LabOrder.fromJson(Map<String, dynamic> j) => LabOrder(
    id: j['id'],
    consultationId: j['consultationId'],
    patientId: j['patientId'],
    doctorId: j['doctorId'],
    testId: j['testId'],
    testName: j['testName'],
    price: (j['price'] as num).toDouble(),
    orderedAt: DateTime.parse(j['orderedAt']),
    urgent: j['urgent'] ?? false,
    clinicalNotes: j['clinicalNotes'] ?? '',
    status: _enumByName(
      LabOrderStatus.values,
      j['status'],
      LabOrderStatus.ordered,
    ),
    sampleCollectedAt: _date(j['sampleCollectedAt']),
    completedAt: _date(j['completedAt']),
    result: j['result'] ?? '',
    resultRemarks: j['resultRemarks'] ?? '',
    abnormal: j['abnormal'] ?? false,
    technicianId: j['technicianId'],
    reviewedByDoctor: j['reviewedByDoctor'] ?? false,
  );
}

/// A stock item held by the pharmacy.
class Medicine {
  Medicine({
    required this.id,
    required this.name,
    required this.form,
    required this.strength,
    required this.unitPrice,
    required this.stock,
    this.reorderLevel = 20,
    this.expiryDate,
    this.manufacturer = '',
  });

  final String id;
  String name;

  /// Tablet, capsule, syrup, injection...
  String form;
  String strength;
  double unitPrice;
  int stock;
  int reorderLevel;
  DateTime? expiryDate;
  String manufacturer;

  String get displayName => '$name $strength ($form)';
  bool get isLowStock => stock <= reorderLevel;
  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());
  bool get expiresSoon =>
      expiryDate != null &&
      !isExpired &&
      expiryDate!.isBefore(DateTime.now().add(const Duration(days: 90)));

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'form': form,
    'strength': strength,
    'unitPrice': unitPrice,
    'stock': stock,
    'reorderLevel': reorderLevel,
    'expiryDate': expiryDate?.toIso8601String(),
    'manufacturer': manufacturer,
  };

  factory Medicine.fromJson(Map<String, dynamic> j) => Medicine(
    id: j['id'],
    name: j['name'],
    form: j['form'],
    strength: j['strength'],
    unitPrice: (j['unitPrice'] as num).toDouble(),
    stock: j['stock'],
    reorderLevel: j['reorderLevel'] ?? 20,
    expiryDate: _date(j['expiryDate']),
    manufacturer: j['manufacturer'] ?? '',
  );
}

class PrescriptionItem {
  PrescriptionItem({
    required this.medicineId,
    required this.medicineName,
    required this.dosage,
    required this.frequency,
    required this.durationDays,
    required this.quantity,
    this.instructions = '',
    this.dispensedQuantity = 0,
    this.unitPrice = 0,
  });

  final String medicineId;
  final String medicineName;
  String dosage;

  /// e.g. `1-0-1`, `TDS`, `Once daily`.
  String frequency;
  int durationDays;
  int quantity;
  String instructions;
  int dispensedQuantity;

  /// Price the pharmacy charged at dispensing time.
  double unitPrice;

  int get outstanding => quantity - dispensedQuantity;

  Map<String, dynamic> toJson() => {
    'medicineId': medicineId,
    'medicineName': medicineName,
    'dosage': dosage,
    'frequency': frequency,
    'durationDays': durationDays,
    'quantity': quantity,
    'instructions': instructions,
    'dispensedQuantity': dispensedQuantity,
    'unitPrice': unitPrice,
  };

  factory PrescriptionItem.fromJson(Map<String, dynamic> j) => PrescriptionItem(
    medicineId: j['medicineId'],
    medicineName: j['medicineName'],
    dosage: j['dosage'] ?? '',
    frequency: j['frequency'] ?? '',
    durationDays: j['durationDays'] ?? 0,
    quantity: j['quantity'] ?? 0,
    instructions: j['instructions'] ?? '',
    dispensedQuantity: j['dispensedQuantity'] ?? 0,
    unitPrice: (j['unitPrice'] as num?)?.toDouble() ?? 0,
  );
}

enum PrescriptionStatus { pending, partiallyDispensed, dispensed, cancelled }

extension PrescriptionStatusX on PrescriptionStatus {
  String get label => switch (this) {
    PrescriptionStatus.pending => 'Pending',
    PrescriptionStatus.partiallyDispensed => 'Partially dispensed',
    PrescriptionStatus.dispensed => 'Dispensed',
    PrescriptionStatus.cancelled => 'Cancelled',
  };
}

class Prescription {
  Prescription({
    required this.id,
    required this.consultationId,
    required this.patientId,
    required this.doctorId,
    required this.createdAt,
    required this.items,
    this.status = PrescriptionStatus.pending,
    this.dispensedAt,
    this.pharmacistId,
  });

  final String id;
  final String consultationId;
  final String patientId;
  final String doctorId;
  final DateTime createdAt;
  final List<PrescriptionItem> items;
  PrescriptionStatus status;
  DateTime? dispensedAt;
  String? pharmacistId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'consultationId': consultationId,
    'patientId': patientId,
    'doctorId': doctorId,
    'createdAt': createdAt.toIso8601String(),
    'items': items.map((i) => i.toJson()).toList(),
    'status': status.name,
    'dispensedAt': dispensedAt?.toIso8601String(),
    'pharmacistId': pharmacistId,
  };

  factory Prescription.fromJson(Map<String, dynamic> j) => Prescription(
    id: j['id'],
    consultationId: j['consultationId'],
    patientId: j['patientId'],
    doctorId: j['doctorId'],
    createdAt: DateTime.parse(j['createdAt']),
    items: (j['items'] as List)
        .map((e) => PrescriptionItem.fromJson(e))
        .toList(),
    status: _enumByName(
      PrescriptionStatus.values,
      j['status'],
      PrescriptionStatus.pending,
    ),
    dispensedAt: _date(j['dispensedAt']),
    pharmacistId: j['pharmacistId'],
  );
}

enum BillingDepartment { consultation, laboratory, pharmacy, room, surgery }

extension BillingDepartmentX on BillingDepartment {
  String get label => switch (this) {
    BillingDepartment.consultation => 'Consultation',
    BillingDepartment.laboratory => 'Laboratory',
    BillingDepartment.pharmacy => 'Pharmacy',
    BillingDepartment.room => 'Room charges',
    BillingDepartment.surgery => 'Operation theatre',
  };
}

class InvoiceLine {
  InvoiceLine({
    required this.id,
    required this.department,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.sourceId,
  });

  final String id;
  final BillingDepartment department;
  final String description;
  final int quantity;
  final double unitPrice;

  /// The lab order / prescription / consultation this charge came from.
  final String? sourceId;

  double get total => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
    'id': id,
    'department': department.name,
    'description': description,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'sourceId': sourceId,
  };

  factory InvoiceLine.fromJson(Map<String, dynamic> j) => InvoiceLine(
    id: j['id'],
    department: _enumByName(
      BillingDepartment.values,
      j['department'],
      BillingDepartment.consultation,
    ),
    description: j['description'],
    quantity: j['quantity'],
    unitPrice: (j['unitPrice'] as num).toDouble(),
    sourceId: j['sourceId'],
  );
}

/// One invoice per visit: an outpatient consultation, an inpatient admission,
/// or a day-case surgery. Each department appends lines to it as it delivers
/// a service, so the patient settles everything in one place.
class Invoice {
  Invoice({
    required this.id,
    required this.number,
    required this.patientId,
    this.consultationId,
    this.admissionId,
    this.surgeryId,
    required this.createdAt,
    List<InvoiceLine>? lines,
    this.amountPaid = 0,
    this.discount = 0,
  }) : lines = lines ?? [];

  final String id;
  final String number;
  final String patientId;

  /// Exactly one of these says which visit the invoice belongs to.
  final String? consultationId;
  final String? admissionId;
  final String? surgeryId;
  final DateTime createdAt;
  final List<InvoiceLine> lines;
  double amountPaid;
  double discount;

  double get subtotal => lines.fold(0, (s, l) => s + l.total);
  double get total => (subtotal - discount).clamp(0, double.infinity);
  double get balance => total - amountPaid;
  bool get isPaid => lines.isNotEmpty && balance <= 0.004;

  double totalFor(BillingDepartment d) =>
      lines.where((l) => l.department == d).fold(0, (s, l) => s + l.total);

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'patientId': patientId,
    'consultationId': consultationId,
    'admissionId': admissionId,
    'surgeryId': surgeryId,
    'createdAt': createdAt.toIso8601String(),
    'lines': lines.map((l) => l.toJson()).toList(),
    'amountPaid': amountPaid,
    'discount': discount,
  };

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
    id: j['id'],
    number: j['number'],
    patientId: j['patientId'],
    consultationId: j['consultationId'],
    admissionId: j['admissionId'],
    surgeryId: j['surgeryId'],
    createdAt: DateTime.parse(j['createdAt']),
    lines: (j['lines'] as List).map((e) => InvoiceLine.fromJson(e)).toList(),
    amountPaid: (j['amountPaid'] as num?)?.toDouble() ?? 0,
    discount: (j['discount'] as num?)?.toDouble() ?? 0,
  );
}

/// A message routed to a role (every user with that role sees it) or to a
/// specific user.
class AppNotification {
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.targetRole,
    this.targetUserId,
    this.patientId,
    List<String>? readBy,
  }) : readBy = readBy ?? [];

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final UserRole? targetRole;
  final String? targetUserId;
  final String? patientId;
  final List<String> readBy;

  bool isFor(StaffUser u) =>
      targetUserId == u.id || (targetUserId == null && targetRole == u.role);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'targetRole': targetRole?.name,
    'targetUserId': targetUserId,
    'patientId': patientId,
    'readBy': readBy,
  };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'],
    title: j['title'],
    body: j['body'],
    createdAt: DateTime.parse(j['createdAt']),
    targetRole: j['targetRole'] == null
        ? null
        : _enumByName(UserRole.values, j['targetRole'], UserRole.admin),
    targetUserId: j['targetUserId'],
    patientId: j['patientId'],
    readBy: (j['readBy'] as List?)?.cast<String>() ?? [],
  );
}
