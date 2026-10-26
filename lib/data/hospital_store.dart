import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'storage.dart';

part 'seed_data.dart';

/// Thrown when a workflow rule is violated (e.g. dispensing more than stock).
class HospitalException implements Exception {
  HospitalException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Single source of truth for the hospital.
///
/// All departments read and write through this store, which is what makes
/// them interconnected: a doctor's lab order appears in the laboratory queue,
/// the lab's result notifies the doctor, a prescription appears in the
/// pharmacy queue, dispensing deducts stock, and every service adds a line to
/// the patient's invoice.
class HospitalStore extends ChangeNotifier {
  HospitalStore({StorageBackend? storage})
      : _storage = storage ?? SharedPrefsStorage();

  final StorageBackend _storage;

  final List<StaffUser> users = [];
  final List<Patient> patients = [];
  final List<Appointment> appointments = [];
  final List<Consultation> consultations = [];
  final List<LabTest> labTests = [];
  final List<LabOrder> labOrders = [];
  final List<Medicine> medicines = [];
  final List<Prescription> prescriptions = [];
  final List<Invoice> invoices = [];
  final List<AppNotification> notifications = [];

  int _seq = 0;
  int _mrnSeq = 0;
  int _invoiceSeq = 0;

  StaffUser? currentUser;
  bool loaded = false;

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    final raw = await _storage.read();
    if (raw == null) {
      _seedDemoData(this);
      await _save();
    } else {
      _fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    loaded = true;
    notifyListeners();
  }

  /// Wipes everything and reloads the demo data set.
  Future<void> resetToDemoData() async {
    _clearAll();
    currentUser = null;
    _seedDemoData(this);
    await _save();
    notifyListeners();
  }

  void _clearAll() {
    for (final l in <List>[
      users,
      patients,
      appointments,
      consultations,
      labTests,
      labOrders,
      medicines,
      prescriptions,
      invoices,
      notifications,
    ]) {
      l.clear();
    }
    _seq = _mrnSeq = _invoiceSeq = 0;
  }

  Future<void> _save() => _storage.write(jsonEncode(_toJson()));

  Future<void> _commit() async {
    notifyListeners();
    await _save();
  }

  Map<String, dynamic> _toJson() => {
        'seq': _seq,
        'mrnSeq': _mrnSeq,
        'invoiceSeq': _invoiceSeq,
        'users': users.map((e) => e.toJson()).toList(),
        'patients': patients.map((e) => e.toJson()).toList(),
        'appointments': appointments.map((e) => e.toJson()).toList(),
        'consultations': consultations.map((e) => e.toJson()).toList(),
        'labTests': labTests.map((e) => e.toJson()).toList(),
        'labOrders': labOrders.map((e) => e.toJson()).toList(),
        'medicines': medicines.map((e) => e.toJson()).toList(),
        'prescriptions': prescriptions.map((e) => e.toJson()).toList(),
        'invoices': invoices.map((e) => e.toJson()).toList(),
        'notifications': notifications.map((e) => e.toJson()).toList(),
      };

  void _fromJson(Map<String, dynamic> j) {
    _clearAll();
    List<Map<String, dynamic>> list(String k) =>
        ((j[k] as List?) ?? []).cast<Map<String, dynamic>>();
    _seq = j['seq'] ?? 0;
    _mrnSeq = j['mrnSeq'] ?? 0;
    _invoiceSeq = j['invoiceSeq'] ?? 0;
    users.addAll(list('users').map(StaffUser.fromJson));
    patients.addAll(list('patients').map(Patient.fromJson));
    appointments.addAll(list('appointments').map(Appointment.fromJson));
    consultations.addAll(list('consultations').map(Consultation.fromJson));
    labTests.addAll(list('labTests').map(LabTest.fromJson));
    labOrders.addAll(list('labOrders').map(LabOrder.fromJson));
    medicines.addAll(list('medicines').map(Medicine.fromJson));
    prescriptions.addAll(list('prescriptions').map(Prescription.fromJson));
    invoices.addAll(list('invoices').map(Invoice.fromJson));
    notifications.addAll(list('notifications').map(AppNotification.fromJson));
  }

  String newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${++_seq}';

  // ---------------------------------------------------------------------------
  // Lookups
  // ---------------------------------------------------------------------------

  T? _find<T>(List<T> list, bool Function(T) test) {
    for (final e in list) {
      if (test(e)) return e;
    }
    return null;
  }

  Patient? patientById(String id) => _find(patients, (p) => p.id == id);
  StaffUser? userById(String id) => _find(users, (u) => u.id == id);
  Medicine? medicineById(String id) => _find(medicines, (m) => m.id == id);
  LabTest? labTestById(String id) => _find(labTests, (t) => t.id == id);
  Consultation? consultationById(String id) =>
      _find(consultations, (c) => c.id == id);
  Appointment? appointmentById(String id) =>
      _find(appointments, (a) => a.id == id);
  Invoice? invoiceForConsultation(String consultationId) =>
      _find(invoices, (i) => i.consultationId == consultationId);

  String patientName(String id) => patientById(id)?.name ?? 'Unknown patient';
  String userName(String id) => userById(id)?.name ?? 'Unknown';

  List<StaffUser> get doctors =>
      users.where((u) => u.role == UserRole.doctor).toList();

  List<Patient> searchPatients(String query) {
    final q = query.trim().toLowerCase();
    final result = q.isEmpty
        ? [...patients]
        : patients
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                p.mrn.toLowerCase().contains(q) ||
                p.phone.contains(q))
            .toList();
    result.sort((a, b) => b.registeredAt.compareTo(a.registeredAt));
    return result;
  }

  List<Consultation> consultationsFor(String patientId) =>
      consultations.where((c) => c.patientId == patientId).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  List<LabOrder> labOrdersFor({String? patientId, String? consultationId}) =>
      labOrders
          .where((o) =>
              (patientId == null || o.patientId == patientId) &&
              (consultationId == null || o.consultationId == consultationId))
          .toList()
        ..sort((a, b) => b.orderedAt.compareTo(a.orderedAt));

  List<Prescription> prescriptionsFor(
          {String? patientId, String? consultationId}) =>
      prescriptions
          .where((p) =>
              (patientId == null || p.patientId == patientId) &&
              (consultationId == null || p.consultationId == consultationId))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<Invoice> invoicesFor(String patientId) =>
      invoices.where((i) => i.patientId == patientId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Appointment> appointmentsOn(DateTime day, {String? doctorId}) =>
      appointments
          .where((a) =>
              _sameDay(a.scheduledAt, day) &&
              (doctorId == null || a.doctorId == doctorId))
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  /// Patients checked in and waiting for (or with) the given doctor.
  List<Appointment> doctorQueue(String doctorId) => appointments
      .where((a) =>
          a.doctorId == doctorId &&
          (a.status == AppointmentStatus.checkedIn ||
              a.status == AppointmentStatus.inConsultation))
      .toList()
    ..sort((a, b) => (a.tokenNumber ?? 0).compareTo(b.tokenNumber ?? 0));

  List<LabOrder> get labQueue => labOrders
      .where((o) =>
          o.status == LabOrderStatus.ordered ||
          o.status == LabOrderStatus.sampleCollected)
      .toList()
    ..sort((a, b) {
      if (a.urgent != b.urgent) return a.urgent ? -1 : 1;
      return a.orderedAt.compareTo(b.orderedAt);
    });

  List<Prescription> get pharmacyQueue => prescriptions
      .where((p) =>
          p.status == PrescriptionStatus.pending ||
          p.status == PrescriptionStatus.partiallyDispensed)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Completed lab results the doctor hasn't acknowledged yet.
  List<LabOrder> unreviewedResults(String doctorId) => labOrders
      .where((o) =>
          o.doctorId == doctorId &&
          o.status == LabOrderStatus.completed &&
          !o.reviewedByDoctor)
      .toList();

  List<Medicine> get lowStockMedicines =>
      medicines.where((m) => m.isLowStock).toList();

  List<AppNotification> notificationsFor(StaffUser u) =>
      notifications.where((n) => n.isFor(u)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int unreadCount(StaffUser u) =>
      notificationsFor(u).where((n) => !n.readBy.contains(u.id)).length;

  // ---------------------------------------------------------------------------
  // Authentication & staff
  // ---------------------------------------------------------------------------

  bool login(String username, String password) {
    final u = _find(
        users,
        (u) =>
            u.username.toLowerCase() == username.trim().toLowerCase() &&
            u.password == password);
    if (u == null) return false;
    currentUser = u;
    notifyListeners();
    return true;
  }

  void logout() {
    currentUser = null;
    notifyListeners();
  }

  Future<StaffUser> addStaff({
    required String name,
    required String username,
    required String password,
    required UserRole role,
    String? specialization,
    double consultationFee = 0,
  }) async {
    if (users.any((u) => u.username.toLowerCase() == username.toLowerCase())) {
      throw HospitalException('Username "$username" is already taken');
    }
    final u = StaffUser(
      id: newId('USR'),
      name: name,
      username: username,
      password: password,
      role: role,
      specialization: specialization,
      consultationFee: consultationFee,
    );
    users.add(u);
    await _commit();
    return u;
  }

  Future<void> removeStaff(String id) async {
    if (currentUser?.id == id) {
      throw HospitalException('You cannot remove your own account');
    }
    users.removeWhere((u) => u.id == id);
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Reception
  // ---------------------------------------------------------------------------

  Future<Patient> registerPatient({
    required String name,
    required DateTime dateOfBirth,
    required String gender,
    required String phone,
    String address = '',
    String bloodGroup = '',
    String allergies = '',
  }) async {
    final p = Patient(
      id: newId('PAT'),
      mrn: 'MRN-${(++_mrnSeq).toString().padLeft(5, '0')}',
      name: name,
      dateOfBirth: dateOfBirth,
      gender: gender,
      phone: phone,
      address: address,
      bloodGroup: bloodGroup,
      allergies: allergies,
      registeredAt: DateTime.now(),
    );
    patients.add(p);
    await _commit();
    return p;
  }

  Future<void> updatePatient(Patient p) => _commit();

  Future<Appointment> bookAppointment({
    required String patientId,
    required String doctorId,
    required DateTime scheduledAt,
    String reason = '',
  }) async {
    final a = Appointment(
      id: newId('APT'),
      patientId: patientId,
      doctorId: doctorId,
      scheduledAt: scheduledAt,
      reason: reason,
    );
    appointments.add(a);
    await _commit();
    return a;
  }

  /// Marks the patient as arrived and puts them in the doctor's queue.
  Future<void> checkIn(String appointmentId) async {
    final a = appointmentById(appointmentId)!;
    if (a.status != AppointmentStatus.scheduled) {
      throw HospitalException('Appointment is already ${a.status.label}');
    }
    final todaysTokens = appointmentsOn(a.scheduledAt, doctorId: a.doctorId)
        .map((x) => x.tokenNumber ?? 0);
    a.tokenNumber =
        (todaysTokens.isEmpty ? 0 : todaysTokens.reduce((x, y) => x > y ? x : y)) +
            1;
    a.status = AppointmentStatus.checkedIn;
    _notify(
      title: 'Patient waiting',
      body: '${patientName(a.patientId)} checked in (token #${a.tokenNumber})',
      userId: a.doctorId,
      patientId: a.patientId,
    );
    await _commit();
  }

  /// Books and checks in a walk-in patient in one step.
  Future<Appointment> walkIn({
    required String patientId,
    required String doctorId,
    String reason = '',
  }) async {
    final a = await bookAppointment(
        patientId: patientId,
        doctorId: doctorId,
        scheduledAt: DateTime.now(),
        reason: reason);
    await checkIn(a.id);
    return a;
  }

  Future<void> cancelAppointment(String appointmentId) async {
    final a = appointmentById(appointmentId)!;
    if (a.status == AppointmentStatus.inConsultation ||
        a.status == AppointmentStatus.completed) {
      throw HospitalException('Cannot cancel a ${a.status.label} visit');
    }
    a.status = AppointmentStatus.cancelled;
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Doctor
  // ---------------------------------------------------------------------------

  /// Opens a consultation (or returns the already-open one for the
  /// appointment) and raises the invoice with the doctor's fee.
  Future<Consultation> startConsultation({
    required String patientId,
    required String doctorId,
    String? appointmentId,
  }) async {
    if (appointmentId != null) {
      final existing = _find(consultations,
          (c) => c.appointmentId == appointmentId && c.isOpen);
      if (existing != null) return existing;
    }
    final appt = appointmentId == null ? null : appointmentById(appointmentId);
    final c = Consultation(
      id: newId('CON'),
      patientId: patientId,
      doctorId: doctorId,
      appointmentId: appointmentId,
      startedAt: DateTime.now(),
      complaints: appt?.reason ?? '',
    );
    consultations.add(c);
    appt?.status = AppointmentStatus.inConsultation;

    final doctor = userById(doctorId);
    final invoice = _invoiceFor(c);
    if ((doctor?.consultationFee ?? 0) > 0) {
      invoice.lines.add(InvoiceLine(
        department: BillingDepartment.consultation,
        description: 'Consultation – ${doctor!.name}',
        quantity: 1,
        unitPrice: doctor.consultationFee,
        sourceId: c.id,
      ));
    }
    await _commit();
    return c;
  }

  Invoice _invoiceFor(Consultation c) {
    final existing = invoiceForConsultation(c.id);
    if (existing != null) return existing;
    final inv = Invoice(
      id: newId('INV'),
      number: 'INV-${(++_invoiceSeq).toString().padLeft(5, '0')}',
      patientId: c.patientId,
      consultationId: c.id,
      createdAt: DateTime.now(),
    );
    invoices.add(inv);
    return inv;
  }

  Future<void> saveConsultation(Consultation c) => _commit();

  Future<void> completeConsultation(String consultationId) async {
    final c = consultationById(consultationId)!;
    c.completedAt = DateTime.now();
    if (c.appointmentId != null) {
      appointmentById(c.appointmentId!)?.status = AppointmentStatus.completed;
    }
    if (c.followUpDate != null) {
      await bookAppointment(
        patientId: c.patientId,
        doctorId: c.doctorId,
        scheduledAt: c.followUpDate!,
        reason: 'Follow-up: ${c.diagnosis}',
      );
    }
    await _commit();
  }

  /// Sends test requests to the laboratory and bills them on the visit's
  /// invoice.
  Future<List<LabOrder>> orderLabTests({
    required String consultationId,
    required List<String> testIds,
    bool urgent = false,
    String clinicalNotes = '',
  }) async {
    final c = consultationById(consultationId)!;
    final invoice = _invoiceFor(c);
    final created = <LabOrder>[];
    for (final tid in testIds) {
      final t = labTestById(tid);
      if (t == null) continue;
      final o = LabOrder(
        id: newId('LAB'),
        consultationId: c.id,
        patientId: c.patientId,
        doctorId: c.doctorId,
        testId: t.id,
        testName: t.name,
        price: t.price,
        orderedAt: DateTime.now(),
        urgent: urgent,
        clinicalNotes: clinicalNotes,
      );
      labOrders.add(o);
      created.add(o);
      invoice.lines.add(InvoiceLine(
        department: BillingDepartment.laboratory,
        description: 'Lab: ${t.name}',
        quantity: 1,
        unitPrice: t.price,
        sourceId: o.id,
      ));
    }
    if (created.isNotEmpty) {
      _notify(
        title: urgent ? 'URGENT lab request' : 'New lab request',
        body: '${created.length} test(s) for ${patientName(c.patientId)} '
            'from ${userName(c.doctorId)}: '
            '${created.map((o) => o.testName).join(', ')}',
        role: UserRole.labTechnician,
        patientId: c.patientId,
      );
    }
    await _commit();
    return created;
  }

  Future<void> markResultReviewed(String labOrderId) async {
    _find(labOrders, (o) => o.id == labOrderId)?.reviewedByDoctor = true;
    await _commit();
  }

  /// Sends a prescription to the pharmacy. Billing happens on dispensing,
  /// since that is when the patient actually receives the medicine.
  Future<Prescription> prescribe({
    required String consultationId,
    required List<PrescriptionItem> items,
  }) async {
    if (items.isEmpty) throw HospitalException('Add at least one medicine');
    final c = consultationById(consultationId)!;
    final rx = Prescription(
      id: newId('RX'),
      consultationId: c.id,
      patientId: c.patientId,
      doctorId: c.doctorId,
      createdAt: DateTime.now(),
      items: items,
    );
    prescriptions.add(rx);
    _notify(
      title: 'New prescription',
      body: '${items.length} item(s) for ${patientName(c.patientId)} '
          'from ${userName(c.doctorId)}',
      role: UserRole.pharmacist,
      patientId: c.patientId,
    );
    await _commit();
    return rx;
  }

  // ---------------------------------------------------------------------------
  // Laboratory
  // ---------------------------------------------------------------------------

  Future<void> collectSample(String labOrderId) async {
    final o = _find(labOrders, (o) => o.id == labOrderId)!;
    if (o.status != LabOrderStatus.ordered) {
      throw HospitalException('Sample already collected');
    }
    o.status = LabOrderStatus.sampleCollected;
    o.sampleCollectedAt = DateTime.now();
    o.technicianId = currentUser?.id;
    await _commit();
  }

  /// Records a result and notifies the ordering doctor.
  Future<void> enterLabResult({
    required String labOrderId,
    required String result,
    String remarks = '',
    bool abnormal = false,
  }) async {
    final o = _find(labOrders, (o) => o.id == labOrderId)!;
    if (o.status == LabOrderStatus.cancelled) {
      throw HospitalException('Order was cancelled');
    }
    if (result.trim().isEmpty) throw HospitalException('Result is required');
    o.sampleCollectedAt ??= DateTime.now();
    o.status = LabOrderStatus.completed;
    o.completedAt = DateTime.now();
    o.result = result.trim();
    o.resultRemarks = remarks.trim();
    o.abnormal = abnormal;
    o.technicianId = currentUser?.id ?? o.technicianId;
    o.reviewedByDoctor = false;
    _notify(
      title: abnormal ? 'ABNORMAL lab result' : 'Lab result ready',
      body: '${o.testName} for ${patientName(o.patientId)}: ${o.result}',
      userId: o.doctorId,
      patientId: o.patientId,
    );
    await _commit();
  }

  /// Cancels an order that hasn't been resulted and removes its charge.
  Future<void> cancelLabOrder(String labOrderId) async {
    final o = _find(labOrders, (o) => o.id == labOrderId)!;
    if (o.status == LabOrderStatus.completed) {
      throw HospitalException('Completed tests cannot be cancelled');
    }
    o.status = LabOrderStatus.cancelled;
    invoiceForConsultation(o.consultationId)
        ?.lines
        .removeWhere((l) => l.sourceId == o.id);
    await _commit();
  }

  Future<LabTest> upsertLabTest(LabTest t) async {
    if (labTestById(t.id) == null) labTests.add(t);
    await _commit();
    return t;
  }

  // ---------------------------------------------------------------------------
  // Pharmacy
  // ---------------------------------------------------------------------------

  /// Dispenses medicines. [quantities] maps item index → quantity to hand out
  /// now; omitted items dispense their full outstanding amount. Stock is
  /// deducted and each dispensed quantity is billed.
  Future<void> dispense(String prescriptionId,
      {Map<int, int>? quantities}) async {
    final rx = _find(prescriptions, (p) => p.id == prescriptionId)!;
    if (rx.status == PrescriptionStatus.dispensed ||
        rx.status == PrescriptionStatus.cancelled) {
      throw HospitalException('Prescription is already ${rx.status.label}');
    }

    // Validate everything first so a failure leaves no partial changes.
    final plan = <int, int>{};
    for (var i = 0; i < rx.items.length; i++) {
      final item = rx.items[i];
      final qty = quantities?[i] ?? item.outstanding;
      if (qty <= 0) continue;
      if (qty > item.outstanding) {
        throw HospitalException(
            '${item.medicineName}: only ${item.outstanding} outstanding');
      }
      final med = medicineById(item.medicineId);
      if (med == null) {
        throw HospitalException('${item.medicineName} is not in inventory');
      }
      if (med.isExpired) {
        throw HospitalException('${med.displayName} stock has expired');
      }
      if (med.stock < qty) {
        throw HospitalException(
            '${med.displayName}: only ${med.stock} in stock, $qty requested');
      }
      plan[i] = qty;
    }
    if (plan.isEmpty) throw HospitalException('Nothing to dispense');

    final c = consultationById(rx.consultationId)!;
    final invoice = _invoiceFor(c);
    for (final MapEntry(key: i, value: qty) in plan.entries) {
      final item = rx.items[i];
      final med = medicineById(item.medicineId)!;
      med.stock -= qty;
      item.dispensedQuantity += qty;
      item.unitPrice = med.unitPrice;
      invoice.lines.add(InvoiceLine(
        department: BillingDepartment.pharmacy,
        description: med.displayName,
        quantity: qty,
        unitPrice: med.unitPrice,
        sourceId: rx.id,
      ));
      if (med.isLowStock) {
        _notify(
          title: 'Low stock',
          body: '${med.displayName} is down to ${med.stock} units',
          role: UserRole.pharmacist,
        );
      }
    }

    final done = rx.items.every((i) => i.outstanding <= 0);
    rx.status =
        done ? PrescriptionStatus.dispensed : PrescriptionStatus.partiallyDispensed;
    rx.dispensedAt = DateTime.now();
    rx.pharmacistId = currentUser?.id;
    _notify(
      title: done ? 'Prescription dispensed' : 'Prescription partly dispensed',
      body: 'Medicines for ${patientName(rx.patientId)} '
          '${done ? 'handed over' : 'partially handed over (stock shortage)'}',
      userId: rx.doctorId,
      patientId: rx.patientId,
    );
    await _commit();
  }

  Future<void> cancelPrescription(String prescriptionId) async {
    final rx = _find(prescriptions, (p) => p.id == prescriptionId)!;
    if (rx.status != PrescriptionStatus.pending) {
      throw HospitalException('Only pending prescriptions can be cancelled');
    }
    rx.status = PrescriptionStatus.cancelled;
    await _commit();
  }

  Future<Medicine> upsertMedicine(Medicine m) async {
    if (medicineById(m.id) == null) medicines.add(m);
    await _commit();
    return m;
  }

  Future<void> restock(String medicineId, int quantity,
      {DateTime? expiryDate}) async {
    if (quantity <= 0) throw HospitalException('Quantity must be positive');
    final m = medicineById(medicineId)!;
    m.stock += quantity;
    if (expiryDate != null) m.expiryDate = expiryDate;
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Billing
  // ---------------------------------------------------------------------------

  Future<void> recordPayment(String invoiceId, double amount) async {
    final inv = _find(invoices, (i) => i.id == invoiceId)!;
    if (amount <= 0) throw HospitalException('Amount must be positive');
    if (amount > inv.balance + 0.004) {
      throw HospitalException(
          'Amount exceeds balance of ${inv.balance.toStringAsFixed(2)}');
    }
    inv.amountPaid += amount;
    await _commit();
  }

  Future<void> applyDiscount(String invoiceId, double discount) async {
    final inv = _find(invoices, (i) => i.id == invoiceId)!;
    if (discount < 0 || discount > inv.subtotal) {
      throw HospitalException('Invalid discount');
    }
    inv.discount = discount;
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  void _notify({
    required String title,
    required String body,
    UserRole? role,
    String? userId,
    String? patientId,
  }) {
    notifications.add(AppNotification(
      id: newId('NTF'),
      title: title,
      body: body,
      createdAt: DateTime.now(),
      targetRole: role,
      targetUserId: userId,
      patientId: patientId,
    ));
  }

  Future<void> markAllRead(StaffUser u) async {
    for (final n in notificationsFor(u)) {
      if (!n.readBy.contains(u.id)) n.readBy.add(u.id);
    }
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Dashboard figures
  // ---------------------------------------------------------------------------

  double revenueOn(DateTime day) => invoices
      .where((i) => _sameDay(i.createdAt, day))
      .fold(0, (s, i) => s + i.amountPaid);

  double get outstandingBalance =>
      invoices.fold(0, (s, i) => s + (i.balance > 0 ? i.balance : 0));
}
