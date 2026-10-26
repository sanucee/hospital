import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'backend.dart';
import 'storage.dart';

export 'backend.dart' show HospitalException, SessionStatus;

part 'seed_data.dart';

/// Single source of truth for the hospital.
///
/// All departments read and write through this store, which is what makes
/// them interconnected: a doctor's lab order appears in the laboratory queue,
/// the lab's result notifies the doctor, a prescription appears in the
/// pharmacy queue, dispensing deducts stock, and every service adds a line to
/// the patient's invoice.
///
/// Data is persisted through a [HospitalBackend]: on this device only
/// ([LocalBackend]) or shared between devices (`FirebaseBackend`). When
/// another device changes data, the backend delivers it and the store
/// rebuilds the affected records, so every open screen updates live.
class HospitalStore extends ChangeNotifier {
  HospitalStore({StorageBackend? storage, HospitalBackend? backend})
      : backend = backend ?? LocalBackend(storage ?? SharedPrefsStorage());

  final HospitalBackend backend;

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

  /// Sequence counters (MRN, invoice and queue numbers). In local mode they
  /// live here; with a remote backend they are allocated by the backend.
  final Map<String, int> _counters = {};

  int _seq = 0;
  // (1 << 30, not 1 << 32: shifts are 32-bit on the web.)
  static final String _deviceTag =
      Random().nextInt(1 << 30).toRadixString(36);

  String? _currentUserId;

  /// Remote mode: staff id of the signed-in account, even before (or
  /// without) a matching staff record.
  String? _sessionStaffId;

  StaffUser? get currentUser =>
      _currentUserId == null ? null : userById(_currentUserId!);

  bool loaded = false;

  /// True while [setupHospital] runs, so the UI can hold a loading screen
  /// through the intermediate sign-in states.
  bool settingUp = false;

  /// Remote mode: who is signed in and whether their data has arrived.
  SessionStatus session = SessionStatus.signedOut;

  /// The last write the server rejected, for the UI to surface.
  Object? syncError;

  bool get isRemote => backend.isRemote;

  final _sessionWaiters = <(SessionStatus, Completer<void>)>[];

  // ---------------------------------------------------------------------------
  // Persistence & sync
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    await backend.start(_StoreListener(this));
    loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    backend.dispose();
    super.dispose();
  }

  void _onDocs(Docs docs) {
    _applyDocs(docs);
    if (!isRemote && users.isEmpty) {
      _seedDemoData(this);
      backend.push(_toDocs());
    }
    notifyListeners();
  }

  void _onSession(SessionStatus status, String? staffId) {
    session = status;
    _sessionStaffId = status == SessionStatus.ready ? staffId : null;
    _currentUserId = _sessionStaffId;
    for (final w in [..._sessionWaiters]) {
      if (w.$1 == status) {
        w.$2.complete();
        _sessionWaiters.remove(w);
      }
    }
    notifyListeners();
  }

  void _onSyncError(Object error) {
    syncError = error;
    notifyListeners();
  }

  void clearSyncError() {
    syncError = null;
    notifyListeners();
  }

  Future<void> _waitForSession(SessionStatus status) {
    if (session == status) return Future.value();
    final c = Completer<void>();
    _sessionWaiters.add((status, c));
    return c.future.timeout(const Duration(seconds: 30));
  }

  /// Wipes everything and reloads the demo data set (local mode only).
  Future<void> resetToDemoData() async {
    if (isRemote) {
      throw HospitalException('Reset is disabled for shared hospital data');
    }
    _clearAll();
    _currentUserId = null;
    _seedDemoData(this);
    await _commit();
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
    _counters.clear();
  }

  Future<void> _commit() async {
    notifyListeners();
    await backend.push(_toDocs());
  }

  Docs _toDocs() {
    Map<String, Map<String, dynamic>> docs<T>(
            List<T> list, String Function(T) id, Map<String, dynamic> Function(T) json) =>
        {for (final e in list) id(e): json(e)};
    return {
      'meta': {'counters': Map.of(_counters)},
      'users': docs(users, (e) => e.id, (e) => e.toJson()),
      'patients': docs(patients, (e) => e.id, (e) => e.toJson()),
      'appointments': docs(appointments, (e) => e.id, (e) => e.toJson()),
      'consultations': docs(consultations, (e) => e.id, (e) => e.toJson()),
      'labTests': docs(labTests, (e) => e.id, (e) => e.toJson()),
      'labOrders': docs(labOrders, (e) => e.id, (e) => e.toJson()),
      'medicines': docs(medicines, (e) => e.id, (e) => e.toJson()),
      'prescriptions': docs(prescriptions, (e) => e.id, (e) => e.toJson()),
      // Lines are stored separately so departments can bill one visit
      // concurrently without overwriting each other's charges.
      'invoices': docs(invoices, (e) => e.id, (e) => e.toJson()..remove('lines')),
      'invoiceLines': {
        for (final inv in invoices)
          for (final l in inv.lines) l.id: {...l.toJson(), 'invoiceId': inv.id},
      },
      'notifications': docs(notifications, (e) => e.id, (e) => e.toJson()),
    };
  }

  void _applyDocs(Docs d) {
    _sync(users, d['users'], StaffUser.fromJson, (e) => e.id, (e) => e.toJson());
    _sync(patients, d['patients'], Patient.fromJson, (e) => e.id, (e) => e.toJson());
    _sync(appointments, d['appointments'], Appointment.fromJson, (e) => e.id,
        (e) => e.toJson());
    _sync(consultations, d['consultations'], Consultation.fromJson, (e) => e.id,
        (e) => e.toJson());
    _sync(labTests, d['labTests'], LabTest.fromJson, (e) => e.id, (e) => e.toJson());
    _sync(labOrders, d['labOrders'], LabOrder.fromJson, (e) => e.id, (e) => e.toJson());
    _sync(medicines, d['medicines'], Medicine.fromJson, (e) => e.id, (e) => e.toJson());
    _sync(prescriptions, d['prescriptions'], Prescription.fromJson, (e) => e.id,
        (e) => e.toJson());
    _sync(notifications, d['notifications'], AppNotification.fromJson, (e) => e.id,
        (e) => e.toJson());

    final linesByInvoice = <String, List<Map<String, dynamic>>>{};
    for (final MapEntry(key: id, value: l) in (d['invoiceLines'] ?? {}).entries) {
      linesByInvoice
          .putIfAbsent(l['invoiceId'] as String? ?? '', () => [])
          .add({...l, 'id': id});
    }
    for (final ls in linesByInvoice.values) {
      // Line ids start with a creation timestamp, so this is billing order.
      ls.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    }
    _sync(
      invoices,
      {
        for (final MapEntry(key: id, value: inv)
            in (d['invoices'] ?? <String, Map<String, dynamic>>{}).entries)
          id: {...inv, 'lines': linesByInvoice[id] ?? []},
      },
      Invoice.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );

    final counters = d['meta']?['counters'];
    if (counters != null) {
      _counters
        ..clear()
        ..addAll(counters.map((k, v) => MapEntry(k, (v as num).toInt())));
    }
  }

  /// Replaces [list] with the records in [docs], keeping existing objects
  /// that haven't changed so screens holding them stay valid.
  void _sync<T>(
    List<T> list,
    Map<String, Map<String, dynamic>>? docs,
    T Function(Map<String, dynamic>) fromJson,
    String Function(T) idOf,
    Map<String, dynamic> Function(T) toJson,
  ) {
    final existing = {for (final e in list) idOf(e): e};
    final next = <T>[];
    for (final MapEntry(key: id, value: data) in (docs ?? {}).entries) {
      final T candidate;
      try {
        candidate = fromJson({...data, 'id': id});
      } catch (e) {
        debugPrint('Skipping malformed record $id: $e');
        continue;
      }
      final old = existing[id];
      next.add(old != null && jsonEquals(toJson(old), toJson(candidate))
          ? old
          : candidate);
    }
    list
      ..clear()
      ..addAll(next);
  }

  /// Unique across devices: timestamp, per-process sequence and device tag.
  String newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${++_seq}$_deviceTag';

  int _bumpLocal(String counter) =>
      _counters[counter] = (_counters[counter] ?? 0) + 1;

  /// Next value of a shared counter, or null if a remote backend can't
  /// coordinate one right now (callers then use an uncoordinated fallback).
  Future<int?> _next(String counter) async =>
      isRemote ? await backend.allocate(counter) : _bumpLocal(counter);

  /// A number that is unique without coordination, for offline use.
  String _offlineNumber() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();

  /// Counter names are used as Firestore field names, so keep them to
  /// letters, digits and underscores.
  static String _tokenCounter(String doctorId, DateTime day) =>
      'token_${doctorId.replaceAll(RegExp(r'\W'), '_')}_${day.year}${day.month.toString().padLeft(2, '0')}'
      '${day.day.toString().padLeft(2, '0')}';

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

  /// Signs in. Local mode checks the staff list; remote mode signs in with
  /// email and password and the session arrives through the backend.
  Future<void> login(String username, String password) async {
    if (isRemote) {
      if (username.trim().isEmpty || password.isEmpty) {
        throw HospitalException('Enter email and password');
      }
      await backend.signIn(username.trim(), password);
      return;
    }
    final u = _find(
        users,
        (u) =>
            u.username.toLowerCase() == username.trim().toLowerCase() &&
            u.password == password);
    if (u == null) throw HospitalException('Invalid username or password');
    _currentUserId = u.id;
    notifyListeners();
  }

  Future<void> logout() async {
    _currentUserId = null;
    notifyListeners();
    if (isRemote) await backend.signOut();
  }

  /// Remote mode, first run: creates the administrator account and the
  /// initial data (demo patients etc. if [demoData], otherwise just the lab
  /// test catalogue and medicine list).
  Future<void> setupHospital({
    required String name,
    required String email,
    required String password,
    bool demoData = true,
  }) async {
    const adminId = 'USR-admin';
    settingUp = true;
    notifyListeners();
    try {
      await backend.setupHospital(
          email: email.trim(), password: password, staffId: adminId);
      // Seed only once the (empty) data set has arrived, so the first
      // snapshot can't arrive later and appear to delete the seeded records.
      await _waitForSession(SessionStatus.ready);
      await finishSetup(name: name, demoData: demoData);
    } finally {
      settingUp = false;
      notifyListeners();
    }
  }

  /// True when the signed-in account was made administrator but the initial
  /// data was never written (e.g. the app closed mid-setup).
  bool get setupIncomplete =>
      isRemote &&
      session == SessionStatus.ready &&
      users.isEmpty &&
      _sessionStaffId != null;

  /// Writes the initial data for a newly set-up hospital. Also used to
  /// resume an interrupted setup.
  Future<void> finishSetup({required String name, bool demoData = true}) async {
    final staffId = _sessionStaffId!;
    final email = backend.signedInEmail ?? '';
    _seedDemoData(
      this,
      demo: demoData,
      admin: StaffUser(
        id: staffId,
        name: name.trim(),
        username: email,
        password: '',
        role: UserRole.admin,
        email: email,
        authUid: backend.signedInUid,
      ),
    );
    _currentUserId = staffId;
    await backend.initCounters(_counters);
    await _commit();
  }

  /// Adds a staff member. With a remote backend this also creates their
  /// sign-in account ([username] is then their email).
  Future<StaffUser> addStaff({
    required String name,
    required String username,
    required String password,
    required UserRole role,
    String? specialization,
    double consultationFee = 0,
  }) async {
    if (users.any((u) => u.username.toLowerCase() == username.toLowerCase())) {
      throw HospitalException('"$username" is already in use');
    }
    final u = StaffUser(
      id: newId('USR'),
      name: name,
      username: username,
      password: isRemote ? '' : password,
      role: role,
      specialization: specialization,
      consultationFee: consultationFee,
      email: isRemote ? username : '',
    );
    if (isRemote) {
      u.authUid = await backend.createLogin(
          email: username, password: password, role: role.name, staffId: u.id);
    }
    users.add(u);
    await _commit();
    return u;
  }

  /// Remote mode: gives an existing staff record (e.g. from demo data) a
  /// sign-in account.
  Future<void> createLoginFor(String staffId,
      {required String email, required String password}) async {
    final uid = await backend.createLogin(
        email: email.trim(),
        password: password,
        role: userById(staffId)!.role.name,
        staffId: staffId);
    userById(staffId)!
      ..authUid = uid
      ..email = email.trim()
      ..username = email.trim();
    await _commit();
  }

  Future<void> removeStaff(String id) async {
    if (currentUser?.id == id) {
      throw HospitalException('You cannot remove your own account');
    }
    final uid = userById(id)?.authUid;
    if (isRemote && uid != null) await backend.revokeLogin(uid);
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
    final n = await _next('mrn');
    final p = Patient(
      id: newId('PAT'),
      mrn: n == null
          ? 'MRN-T${_offlineNumber()}'
          : 'MRN-${n.toString().padLeft(5, '0')}',
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
    void validate(Appointment? a) {
      if (a == null) throw HospitalException('Appointment no longer exists');
      if (a.status != AppointmentStatus.scheduled) {
        throw HospitalException('Appointment is already ${a.status.label}');
      }
    }

    final booked = appointmentById(appointmentId);
    validate(booked);
    final n =
        await _next(_tokenCounter(booked!.doctorId, booked.scheduledAt));
    // Another device may have changed the appointment while we waited.
    final a = appointmentById(appointmentId);
    validate(a);
    a!.tokenNumber = n ??
        appointmentsOn(a.scheduledAt, doctorId: a.doctorId)
                .map((x) => x.tokenNumber ?? 0)
                .fold(0, max) +
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
    Consultation? openForAppointment() => appointmentId == null
        ? null
        : _find(consultations,
            (c) => c.appointmentId == appointmentId && c.isOpen);
    final open = openForAppointment();
    if (open != null) return open;
    final invoiceNo = await _next('invoice');
    // A double tap may have opened it while the number was being reserved.
    final openNow = openForAppointment();
    if (openNow != null) return openNow;
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
    final invoice = _invoiceFor(c, number: invoiceNo);
    if ((doctor?.consultationFee ?? 0) > 0) {
      invoice.lines.add(InvoiceLine(
        id: newId('LINE'),
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

  Invoice _invoiceFor(Consultation c, {int? number}) {
    final existing = invoiceForConsultation(c.id);
    if (existing != null) return existing;
    final inv = Invoice(
      id: newId('INV'),
      number: number == null
          ? 'INV-T${_offlineNumber()}'
          : 'INV-${number.toString().padLeft(5, '0')}',
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
        id: newId('LINE'),
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
        id: newId('LINE'),
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

class _StoreListener implements BackendListener {
  _StoreListener(this.store);

  final HospitalStore store;

  @override
  void onDocs(Docs docs) => store._onDocs(docs);

  @override
  void onSession(SessionStatus status, {String? staffId}) =>
      store._onSession(status, staffId);

  @override
  void onSyncError(Object error) => store._onSyncError(error);
}
