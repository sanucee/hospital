import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'backend.dart';
import 'storage.dart';

export 'backend.dart' show HospitalException, SessionStatus;

part 'seed_data.dart';
part 'store_audit.dart';
part 'store_nursing.dart';
part 'store_portal.dart';
part 'store_scheduling.dart';
part 'store_billing_supply.dart';
part 'store_blood_bank.dart';
part 'store_counter.dart';
part 'store_emergency.dart';
part 'store_hr_finance.dart';
part 'store_inpatient.dart';
part 'store_radiology.dart';
part 'store_stores.dart';

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
  final List<Room> rooms = [];
  final List<Admission> admissions = [];
  final List<OperationTheatre> theatres = [];
  final List<Surgery> surgeries = [];
  final List<LeaveRequest> leaves = [];
  final List<Payment> payments = [];
  final List<InsuranceProvider> insurers = [];
  final List<InsuranceClaim> claims = [];
  final List<Supplier> suppliers = [];
  final List<PurchaseOrder> purchaseOrders = [];
  final List<VitalsReading> vitals = [];
  final List<MedicationOrder> medicationOrders = [];
  final List<MedicationDose> medicationDoses = [];
  final List<NursingNote> nursingNotes = [];
  final List<DoctorSchedule> schedules = [];
  final List<AppointmentReminder> reminders = [];
  final List<EmergencyVisit> emergencyVisits = [];
  final List<ImagingStudy> imagingStudies = [];
  final List<ImagingOrder> imagingOrders = [];
  final List<BloodDonor> bloodDonors = [];
  final List<BloodUnit> bloodUnits = [];
  final List<BloodRequest> bloodRequests = [];
  final List<StoreItem> storeItems = [];
  final List<Requisition> requisitions = [];
  final List<StockMovement> stockMovements = [];

  /// Doctors' booked times, without patient details (see [BookedSlot]).
  final List<BookedSlot> bookedSlots = [];

  /// Cashiers' cash drawers. With a remote backend only cashier roles,
  /// administrators and accounts can read them.
  final List<CashTill> tills = [];

  /// Refunds to patients; readable by the same roles as tills.
  final List<Refund> refunds = [];

  /// Who changed what. With a remote backend only administrators can read
  /// it; everyone else's device just appends.
  final List<AuditEntry> auditLog = [];

  /// The data as last saved or received, to work out what a commit changed.
  Docs? _auditBaseline;
  HospitalProfile profile = HospitalProfile();

  // Only administrators and accounts can read these with a remote backend;
  // for everyone else they stay empty.
  final List<Expense> expenses = [];
  final List<Payslip> payslips = [];
  final List<SalaryStructure> salaries = [];

  /// Sequence counters (MRN, invoice and queue numbers). In local mode they
  /// live here; with a remote backend they are allocated by the backend.
  final Map<String, int> _counters = {};

  int _seq = 0;
  // (1 << 30, not 1 << 32: shifts are 32-bit on the web.)
  static final String _deviceTag = Random().nextInt(1 << 30).toRadixString(36);

  String? _currentUserId;

  /// Remote mode: staff id of the signed-in account, even before (or
  /// without) a matching staff record.
  String? _sessionStaffId;

  StaffUser? get currentUser =>
      _currentUserId == null ? null : userById(_currentUserId!);

  /// The patient signed in to the patient portal, if any.
  String? _portalPatientId;

  Patient? get currentPatient =>
      _portalPatientId == null ? null : patientById(_portalPatientId!);

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

  /// The last data set received, re-applied when a portal session starts.
  Docs _lastDocs = {};

  void _onDocs(Docs docs) {
    _lastDocs = docs;
    _applyDocs(isRemote && _portalPatientId != null ? _portalView(docs) : docs);
    if (!isRemote && users.isEmpty) {
      _seedDemoData(this);
      backend.push(_toDocs());
    }
    // Changes arriving from other devices (or the initial load) are not
    // this user's; only later local commits are audited against this.
    _auditBaseline = _toDocs();
    notifyListeners();
  }

  void _onSession(SessionStatus status, String? staffId, String? patientId) {
    final wasReady = session == SessionStatus.ready;
    session = status;
    _sessionStaffId = status == SessionStatus.ready ? staffId : null;
    _currentUserId = _sessionStaffId;
    final portalStarted = patientId != null && patientId != _portalPatientId;
    _portalPatientId = status == SessionStatus.ready ? patientId : null;
    // The first data arrives before the backend says this is a patient;
    // rebuild the doctors from the directory now.
    if (portalStarted && status == SessionStatus.ready) {
      _applyDocs(_portalView(_lastDocs));
      _auditBaseline = _toDocs();
    }
    for (final w in [..._sessionWaiters]) {
      if (w.$1 == status) {
        w.$2.complete();
        _sessionWaiters.remove(w);
      }
    }
    notifyListeners();
    if (status == SessionStatus.ready && !wasReady && !settingUp) {
      _logEvent('signed in');
    }
  }

  /// For extensions, which can't call [notifyListeners] directly.
  void _changed() => notifyListeners();

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
    await _commit(audit: false);
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
      rooms,
      admissions,
      theatres,
      surgeries,
      leaves,
      payments,
      expenses,
      payslips,
      salaries,
      insurers,
      claims,
      suppliers,
      purchaseOrders,
      vitals,
      medicationOrders,
      medicationDoses,
      nursingNotes,
      auditLog,
      schedules,
      reminders,
      bookedSlots,
      tills,
      refunds,
      emergencyVisits,
      imagingStudies,
      imagingOrders,
      bloodDonors,
      bloodUnits,
      bloodRequests,
      storeItems,
      requisitions,
      stockMovements,
    ]) {
      l.clear();
    }
    profile = HospitalProfile();
    _counters.clear();
  }

  /// Saves the current state. Unless [audit] is false, every record the
  /// signed-in user created, changed or deleted since the last save is
  /// written to the audit log first.
  Future<void> _commit({bool audit = true}) async {
    var docs = _toDocs();
    final base = _auditBaseline;
    final actor = _actor;
    if (audit && base != null && actor != null) {
      final entries = _auditChanges(this, base, docs, actor.$1, actor.$2);
      if (entries.isNotEmpty) {
        auditLog.addAll(entries);
        if (!isRemote) _trimAuditLog();
        docs = _toDocs();
      }
    }
    _auditBaseline = docs;
    notifyListeners();
    await backend.push(docs);
  }

  /// Who is making changes, as (id, name) for the audit log: the staff
  /// member, or the patient using the portal.
  (String, String)? get _actor {
    final user = currentUser;
    if (user != null) return (user.id, user.name);
    final p = currentPatient;
    if (p != null) return (p.id, '${p.name} (patient portal)');
    return null;
  }

  /// Records an event that isn't a data change, such as signing in.
  Future<void> _logEvent(String action, {String summary = ''}) async {
    final actor = _actor;
    if (actor == null) return;
    final (id, name) = actor;
    auditLog.add(
      AuditEntry(
        id: newId('AUD'),
        at: DateTime.now(),
        userId: id,
        userName: name,
        action: action,
        collection: 'session',
        docId: id,
        summary: summary.isEmpty ? '$name $action' : summary,
      ),
    );
    await _commit(audit: false);
  }

  /// Local mode keeps the most recent entries so device storage stays small.
  void _trimAuditLog() {
    const keep = 5000;
    if (auditLog.length <= keep) return;
    auditLog.sort((a, b) => a.at.compareTo(b.at));
    auditLog.removeRange(0, auditLog.length - keep);
  }

  Docs _toDocs() {
    Map<String, Map<String, dynamic>> docs<T>(
      List<T> list,
      String Function(T) id,
      Map<String, dynamic> Function(T) json,
    ) => {for (final e in list) id(e): json(e)};
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
      'invoices': docs(
        invoices,
        (e) => e.id,
        (e) => e.toJson()..remove('lines'),
      ),
      // patientId lets the patient portal load a patient's own lines.
      'invoiceLines': {
        for (final inv in invoices)
          for (final l in inv.lines)
            l.id: {
              ...l.toJson(),
              'invoiceId': inv.id,
              'patientId': inv.patientId,
            },
      },
      'notifications': docs(notifications, (e) => e.id, (e) => e.toJson()),
      'rooms': docs(rooms, (e) => e.id, (e) => e.toJson()),
      'admissions': docs(admissions, (e) => e.id, (e) => e.toJson()),
      'theatres': docs(theatres, (e) => e.id, (e) => e.toJson()),
      'surgeries': docs(surgeries, (e) => e.id, (e) => e.toJson()),
      'leaves': docs(leaves, (e) => e.id, (e) => e.toJson()),
      'payments': docs(payments, (e) => e.id, (e) => e.toJson()),
      'expenses': docs(expenses, (e) => e.id, (e) => e.toJson()),
      'payslips': docs(payslips, (e) => e.id, (e) => e.toJson()),
      'salaries': docs(salaries, (e) => e.staffId, (e) => e.toJson()),
      'insurers': docs(insurers, (e) => e.id, (e) => e.toJson()),
      'claims': docs(claims, (e) => e.id, (e) => e.toJson()),
      'suppliers': docs(suppliers, (e) => e.id, (e) => e.toJson()),
      'purchaseOrders': docs(purchaseOrders, (e) => e.id, (e) => e.toJson()),
      'settings': {HospitalProfile.docId: profile.toJson()},
      'vitals': docs(vitals, (e) => e.id, (e) => e.toJson()),
      'medicationOrders': docs(
        medicationOrders,
        (e) => e.id,
        (e) => e.toJson(),
      ),
      'medicationDoses': docs(medicationDoses, (e) => e.id, (e) => e.toJson()),
      'nursingNotes': docs(nursingNotes, (e) => e.id, (e) => e.toJson()),
      'auditLog': docs(auditLog, (e) => e.id, (e) => e.toJson()),
      'schedules': docs(schedules, (e) => e.doctorId, (e) => e.toJson()),
      'reminders': docs(reminders, (e) => e.id, (e) => e.toJson()),
      'bookedSlots': docs(bookedSlots, (e) => e.id, (e) => e.toJson()),
      'tills': docs(tills, (e) => e.id, (e) => e.toJson()),
      'refunds': docs(refunds, (e) => e.id, (e) => e.toJson()),
      'emergencyVisits': docs(emergencyVisits, (e) => e.id, (e) => e.toJson()),
      'imagingStudies': docs(imagingStudies, (e) => e.id, (e) => e.toJson()),
      'imagingOrders': docs(imagingOrders, (e) => e.id, (e) => e.toJson()),
      'bloodDonors': docs(bloodDonors, (e) => e.id, (e) => e.toJson()),
      'bloodUnits': docs(bloodUnits, (e) => e.id, (e) => e.toJson()),
      'bloodRequests': docs(bloodRequests, (e) => e.id, (e) => e.toJson()),
      'storeItems': docs(storeItems, (e) => e.id, (e) => e.toJson()),
      'requisitions': docs(requisitions, (e) => e.id, (e) => e.toJson()),
      'stockMovements': docs(stockMovements, (e) => e.id, (e) => e.toJson()),
      'directory': _directoryDocs(),
    };
  }

  /// What the patient portal may know about doctors: names, specialities,
  /// fees and leave dates, but not salaries, contacts or leave reasons.
  Map<String, Map<String, dynamic>> _directoryDocs() {
    final today = _dayOnly(DateTime.now());
    return {
      for (final d in doctors)
        d.id: {
          'id': d.id,
          'name': d.name,
          'specialization': d.specialization,
          'consultationFee': d.consultationFee,
          'active': d.active,
          'leave': [
            for (final l in leaves)
              if (l.staffId == d.id &&
                  l.status == LeaveStatus.approved &&
                  !_dayOnly(l.to).isBefore(today))
                {
                  'from': _dayOnly(l.from).toIso8601String(),
                  'to': _dayOnly(l.to).toIso8601String(),
                },
          ],
        },
    };
  }

  /// A portal session can't read staff or leave records; rebuild the
  /// doctors and their leave from the public directory instead.
  Docs _portalView(Docs d) {
    final dir = d['directory'] ?? {};
    return {
      ...d,
      'users': {
        for (final MapEntry(key: id, value: e) in dir.entries)
          id: {
            'id': id,
            'name': e['name'],
            'username': '',
            'password': '',
            'role': UserRole.doctor.name,
            'specialization': e['specialization'],
            'consultationFee': e['consultationFee'],
            'active': e['active'] ?? true,
          },
      },
      'leaves': {
        for (final MapEntry(key: id, value: e) in dir.entries)
          for (final (i, l) in ((e['leave'] as List?) ?? const []).indexed)
            'DIR-$id-$i': {
              'id': 'DIR-$id-$i',
              'staffId': id,
              'type': LeaveType.annual.name,
              'from': (l as Map)['from'],
              'to': l['to'],
              'status': LeaveStatus.approved.name,
              'requestedAt': l['from'],
            },
      },
    };
  }

  void _applyDocs(Docs d) {
    _sync(
      users,
      d['users'],
      StaffUser.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      patients,
      d['patients'],
      Patient.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      appointments,
      d['appointments'],
      Appointment.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      consultations,
      d['consultations'],
      Consultation.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      labTests,
      d['labTests'],
      LabTest.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      labOrders,
      d['labOrders'],
      LabOrder.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      medicines,
      d['medicines'],
      Medicine.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      prescriptions,
      d['prescriptions'],
      Prescription.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      notifications,
      d['notifications'],
      AppNotification.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(rooms, d['rooms'], Room.fromJson, (e) => e.id, (e) => e.toJson());
    _sync(
      admissions,
      d['admissions'],
      Admission.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      theatres,
      d['theatres'],
      OperationTheatre.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      surgeries,
      d['surgeries'],
      Surgery.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      leaves,
      d['leaves'],
      LeaveRequest.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      payments,
      d['payments'],
      Payment.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      expenses,
      d['expenses'],
      Expense.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      payslips,
      d['payslips'],
      Payslip.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      salaries,
      d['salaries'],
      SalaryStructure.fromJson,
      (e) => e.staffId,
      (e) => e.toJson(),
    );
    _sync(
      insurers,
      d['insurers'],
      InsuranceProvider.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      claims,
      d['claims'],
      InsuranceClaim.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      suppliers,
      d['suppliers'],
      Supplier.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      purchaseOrders,
      d['purchaseOrders'],
      PurchaseOrder.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      vitals,
      d['vitals'],
      VitalsReading.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      medicationOrders,
      d['medicationOrders'],
      MedicationOrder.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      medicationDoses,
      d['medicationDoses'],
      MedicationDose.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      nursingNotes,
      d['nursingNotes'],
      NursingNote.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      schedules,
      d['schedules'],
      DoctorSchedule.fromJson,
      (e) => e.doctorId,
      (e) => e.toJson(),
    );
    _sync(
      reminders,
      d['reminders'],
      AppointmentReminder.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(tills, d['tills'], CashTill.fromJson, (e) => e.id, (e) => e.toJson());
    _sync(
      refunds,
      d['refunds'],
      Refund.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      emergencyVisits,
      d['emergencyVisits'],
      EmergencyVisit.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      imagingStudies,
      d['imagingStudies'],
      ImagingStudy.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      imagingOrders,
      d['imagingOrders'],
      ImagingOrder.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      bloodDonors,
      d['bloodDonors'],
      BloodDonor.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      bloodUnits,
      d['bloodUnits'],
      BloodUnit.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      bloodRequests,
      d['bloodRequests'],
      BloodRequest.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      storeItems,
      d['storeItems'],
      StoreItem.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      requisitions,
      d['requisitions'],
      Requisition.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      stockMovements,
      d['stockMovements'],
      StockMovement.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      bookedSlots,
      d['bookedSlots'],
      BookedSlot.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    _sync(
      auditLog,
      d['auditLog'],
      AuditEntry.fromJson,
      (e) => e.id,
      (e) => e.toJson(),
    );
    final profileDoc = d['settings']?[HospitalProfile.docId];
    if (profileDoc == null) {
      profile = HospitalProfile();
    } else if (!jsonEquals(profile.toJson(), {
      ...profileDoc,
      'id': HospitalProfile.docId,
    })) {
      profile = HospitalProfile.fromJson(profileDoc);
    }

    final linesByInvoice = <String, List<Map<String, dynamic>>>{};
    for (final MapEntry(key: id, value: l)
        in (d['invoiceLines'] ?? {}).entries) {
      linesByInvoice.putIfAbsent(l['invoiceId'] as String? ?? '', () => []).add(
        {...l, 'id': id},
      );
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
      next.add(
        old != null && jsonEquals(toJson(old), toJson(candidate))
            ? old
            : candidate,
      );
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
              .where(
                (p) =>
                    p.name.toLowerCase().contains(q) ||
                    p.mrn.toLowerCase().contains(q) ||
                    p.phone.contains(q),
              )
              .toList();
    result.sort((a, b) => b.registeredAt.compareTo(a.registeredAt));
    return result;
  }

  List<Consultation> consultationsFor(String patientId) =>
      consultations.where((c) => c.patientId == patientId).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  List<LabOrder> labOrdersFor({String? patientId, String? consultationId}) =>
      labOrders
          .where(
            (o) =>
                (patientId == null || o.patientId == patientId) &&
                (consultationId == null || o.consultationId == consultationId),
          )
          .toList()
        ..sort((a, b) => b.orderedAt.compareTo(a.orderedAt));

  List<Prescription> prescriptionsFor({
    String? patientId,
    String? consultationId,
  }) =>
      prescriptions
          .where(
            (p) =>
                (patientId == null || p.patientId == patientId) &&
                (consultationId == null || p.consultationId == consultationId),
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<Invoice> invoicesFor(String patientId) =>
      invoices.where((i) => i.patientId == patientId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Appointment> appointmentsOn(DateTime day, {String? doctorId}) =>
      appointments
          .where(
            (a) =>
                _sameDay(a.scheduledAt, day) &&
                (doctorId == null || a.doctorId == doctorId),
          )
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  /// Patients checked in and waiting for (or with) the given doctor.
  List<Appointment> doctorQueue(String doctorId) =>
      appointments
          .where(
            (a) =>
                a.doctorId == doctorId &&
                (a.status == AppointmentStatus.checkedIn ||
                    a.status == AppointmentStatus.inConsultation),
          )
          .toList()
        ..sort((a, b) => (a.tokenNumber ?? 0).compareTo(b.tokenNumber ?? 0));

  List<LabOrder> get labQueue =>
      labOrders
          .where(
            (o) =>
                o.status == LabOrderStatus.ordered ||
                o.status == LabOrderStatus.sampleCollected,
          )
          .toList()
        ..sort((a, b) {
          if (a.urgent != b.urgent) return a.urgent ? -1 : 1;
          return a.orderedAt.compareTo(b.orderedAt);
        });

  List<Prescription> get pharmacyQueue =>
      prescriptions
          .where(
            (p) =>
                p.status == PrescriptionStatus.pending ||
                p.status == PrescriptionStatus.partiallyDispensed,
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Completed lab results the doctor hasn't acknowledged yet.
  List<LabOrder> unreviewedResults(String doctorId) => labOrders
      .where(
        (o) =>
            o.doctorId == doctorId &&
            o.status == LabOrderStatus.completed &&
            !o.reviewedByDoctor,
      )
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
          u.password == password,
    );
    if (u == null || !u.role.canSignIn || u.password.isEmpty) {
      throw HospitalException('Invalid username or password');
    }
    if (!u.active) throw HospitalException('This account is inactive');
    _currentUserId = u.id;
    notifyListeners();
    await _logEvent('signed in');
  }

  Future<void> logout() async {
    // With Firebase, a write queued now would be sent after sign-out and be
    // rejected, so only local mode records sign-outs.
    if (!isRemote) await _logEvent('signed out');
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
        email: email.trim(),
        password: password,
        staffId: adminId,
      );
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
    await _commit(audit: false);
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
    String department = '',
    String designation = '',
    String phone = '',
    DateTime? joinedOn,
  }) async {
    final login = role.canSignIn;
    if (login &&
        users.any((u) => u.username.toLowerCase() == username.toLowerCase())) {
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
      email: isRemote && login ? username : '',
      department: department,
      designation: designation,
      phone: phone,
      joinedOn: joinedOn,
    );
    if (isRemote && login) {
      u.authUid = await backend.createLogin(
        email: username,
        password: password,
        role: role.name,
        staffId: u.id,
      );
    }
    users.add(u);
    await _commit();
    return u;
  }

  /// Remote mode: gives an existing staff record (e.g. from demo data) a
  /// sign-in account.
  Future<void> createLoginFor(
    String staffId, {
    required String email,
    required String password,
  }) async {
    final uid = await backend.createLogin(
      email: email.trim(),
      password: password,
      role: userById(staffId)!.role.name,
      staffId: staffId,
    );
    userById(staffId)!
      ..authUid = uid
      ..email = email.trim()
      ..username = email.trim();
    await _commit();
  }

  /// The signed-in staff member changes their own password.
  Future<void> changeMyPassword(String current, String next) async {
    final me = currentUser;
    if (me == null) throw HospitalException('Sign in first');
    if (next.length < 6) {
      throw HospitalException('The new password must be at least 6 characters');
    }
    if (next == current) {
      throw HospitalException(
        'Choose a password different from the current one',
      );
    }
    if (isRemote) {
      await backend.changePassword(current, next);
      await _logEvent('changed their password');
      return;
    }
    if (me.password != current) {
      throw HospitalException('The current password is wrong');
    }
    me.password = next;
    await _commit();
  }

  /// Whether [u] has a login whose password an administrator can reset.
  bool hasLogin(StaffUser u) =>
      u.role.canSignIn &&
      (isRemote ? u.authUid != null : u.password.isNotEmpty);

  /// An administrator sets a staff member's password (e.g. forgotten).
  /// Returns false when the backend emailed them a reset link instead
  /// (Firebase).
  Future<bool> resetStaffPassword(String staffId, String password) async {
    if (currentUser?.role != UserRole.admin) {
      throw HospitalException('Only administrators reset passwords');
    }
    final u = userById(staffId)!;
    if (!hasLogin(u)) throw HospitalException('${u.name} has no login');
    final emailed = isRemote && backend.emailLogins;
    if (!emailed && password.length < 6) {
      throw HospitalException('The password must be at least 6 characters');
    }
    if (isRemote) {
      final set = await backend.resetPassword(
        uid: u.authUid!,
        login: u.email.isNotEmpty ? u.email : u.username,
        password: password,
      );
      await _logEvent(
        set ? 'reset a password' : 'sent a password reset email',
        summary:
            '${currentUser!.name} ${set ? 'reset the password of' : 'sent a password reset email to'} ${u.name}',
      );
      return set;
    }
    u.password = password;
    await _commit();
    return true;
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
    String email = '',
    String address = '',
    String bloodGroup = '',
    String allergies = '',
    String? insurerId,
    String policyNumber = '',
    DateTime? policyExpiry,
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
      email: email.trim(),
      address: address,
      bloodGroup: bloodGroup,
      allergies: allergies,
      registeredAt: DateTime.now(),
      insurerId: insurerId,
      policyNumber: insurerId == null ? '' : policyNumber,
      policyExpiry: insurerId == null ? null : policyExpiry,
    );
    patients.add(p);
    await _commit();
    return p;
  }

  Future<void> updatePatient(Patient p) => _commit();

  /// Books an appointment. Unless [enforceSchedule] is false (walk-ins), the
  /// time must be free within the doctor's working hours. Reminders are
  /// queued for the patient, plus a booking confirmation to send now if
  /// [sendConfirmation].
  Future<Appointment> bookAppointment({
    required String patientId,
    required String doctorId,
    required DateTime scheduledAt,
    String reason = '',
    bool enforceSchedule = true,
    BookingChannel channel = BookingChannel.counter,
    String callerName = '',
    bool sendConfirmation = false,
  }) async {
    if (enforceSchedule) _checkBookable(doctorId, scheduledAt);
    final a = Appointment(
      id: newId('APT'),
      patientId: patientId,
      doctorId: doctorId,
      scheduledAt: scheduledAt,
      reason: reason,
      channel: channel,
      bookedBy: currentUser?.id,
      callerName: callerName.trim(),
    );
    appointments.add(a);
    if (channel != BookingChannel.walkIn) _holdSlot(a);
    if (currentUser != null) _pruneSlots();
    if (sendConfirmation) _createConfirmation(a);
    _createReminders(a);
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
    final n = await _next(_tokenCounter(booked!.doctorId, booked.scheduledAt));
    // Another device may have changed the appointment while we waited.
    final a = appointmentById(appointmentId);
    validate(a);
    a!.tokenNumber =
        n ??
        appointmentsOn(
              a.scheduledAt,
              doctorId: a.doctorId,
            ).map((x) => x.tokenNumber ?? 0).fold(0, max) +
            1;
    a.status = AppointmentStatus.checkedIn;
    // The patient has arrived; later reminders would only confuse them.
    _cancelReminders(a.id);
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
      reason: reason,
      enforceSchedule: false,
      channel: BookingChannel.walkIn,
    );
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
    _cancelReminders(a.id);
    _releaseSlot(a.id);
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
        : _find(
            consultations,
            (c) => c.appointmentId == appointmentId && c.isOpen,
          );
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
      invoice.lines.add(
        InvoiceLine(
          id: newId('LINE'),
          department: BillingDepartment.consultation,
          description: 'Consultation – ${doctor!.name}',
          quantity: 1,
          unitPrice: doctor.consultationFee,
          sourceId: c.id,
        ),
      );
    }
    await _commit();
    return c;
  }

  Invoice _invoiceFor(Consultation c, {int? number}) =>
      invoiceForConsultation(c.id) ??
      _newInvoice(patientId: c.patientId, consultationId: c.id, number: number);

  /// [number] comes from the shared invoice counter; without one (offline)
  /// a time-based number is used.
  Invoice _newInvoice({
    required String patientId,
    String? consultationId,
    String? admissionId,
    String? surgeryId,
    int? number,
  }) {
    final inv = Invoice(
      id: newId('INV'),
      number: number == null
          ? 'INV-T${_offlineNumber()}'
          : 'INV-${number.toString().padLeft(5, '0')}',
      patientId: patientId,
      consultationId: consultationId,
      admissionId: admissionId,
      surgeryId: surgeryId,
      createdAt: DateTime.now(),
    );
    _applyInsurance(inv);
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
      // Take the doctor's first free slot from the chosen day, if they
      // have a schedule.
      final d = c.followUpDate!;
      final slot = scheduleFor(c.doctorId) == null
          ? null
          : nextAvailableSlot(
              c.doctorId,
              from: DateTime(d.year, d.month, d.day),
            );
      await bookAppointment(
        patientId: c.patientId,
        doctorId: c.doctorId,
        scheduledAt: slot ?? d,
        reason: 'Follow-up: ${c.diagnosis}',
        enforceSchedule: false,
        channel: BookingChannel.followUp,
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
      invoice.lines.add(
        InvoiceLine(
          id: newId('LINE'),
          department: BillingDepartment.laboratory,
          description: 'Lab: ${t.name}',
          quantity: 1,
          unitPrice: t.price,
          sourceId: o.id,
        ),
      );
    }
    if (created.isNotEmpty) {
      _notify(
        title: urgent ? 'URGENT lab request' : 'New lab request',
        body:
            '${created.length} test(s) for ${patientName(c.patientId)} '
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
      body:
          '${items.length} item(s) for ${patientName(c.patientId)} '
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
    invoiceForConsultation(o.consultationId)?.lines
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
  Future<void> dispense(
    String prescriptionId, {
    Map<int, int>? quantities,
  }) async {
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
          '${item.medicineName}: only ${item.outstanding} outstanding',
        );
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
          '${med.displayName}: only ${med.stock} in stock, $qty requested',
        );
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
      invoice.lines.add(
        InvoiceLine(
          id: newId('LINE'),
          department: BillingDepartment.pharmacy,
          description: med.displayName,
          quantity: qty,
          unitPrice: med.unitPrice,
          sourceId: rx.id,
        ),
      );
      if (med.isLowStock) {
        _notify(
          title: 'Low stock',
          body: '${med.displayName} is down to ${med.stock} units',
          role: UserRole.pharmacist,
        );
      }
    }

    final done = rx.items.every((i) => i.outstanding <= 0);
    rx.status = done
        ? PrescriptionStatus.dispensed
        : PrescriptionStatus.partiallyDispensed;
    rx.dispensedAt = DateTime.now();
    rx.pharmacistId = currentUser?.id;
    _notify(
      title: done ? 'Prescription dispensed' : 'Prescription partly dispensed',
      body:
          'Medicines for ${patientName(rx.patientId)} '
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

  Future<void> restock(
    String medicineId,
    int quantity, {
    DateTime? expiryDate,
  }) async {
    if (quantity <= 0) throw HospitalException('Quantity must be positive');
    final m = medicineById(medicineId)!;
    m.stock += quantity;
    if (expiryDate != null) m.expiryDate = expiryDate;
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Billing
  // ---------------------------------------------------------------------------

  Future<void> recordPayment(
    String invoiceId,
    double amount, {
    String method = 'Cash',
  }) async {
    final inv = _find(invoices, (i) => i.id == invoiceId)!;
    if (amount <= 0) throw HospitalException('Amount must be positive');
    // With insurance the patient only owes their share; the insurer's
    // share is settled through its claim.
    if (amount > inv.patientBalance + 0.004) {
      throw HospitalException(
        'Amount exceeds the patient balance of '
        '${inv.patientBalance.toStringAsFixed(2)}',
      );
    }
    inv.amountPaid += amount;
    payments.add(
      Payment(
        id: newId('PMT'),
        invoiceId: inv.id,
        patientId: inv.patientId,
        amount: amount,
        method: method,
        receivedAt: DateTime.now(),
        receivedBy: currentUser?.id,
        tillId: myOpenTill?.id,
      ),
    );
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
    notifications.add(
      AppNotification(
        id: newId('NTF'),
        title: title,
        body: body,
        createdAt: DateTime.now(),
        targetRole: role,
        targetUserId: userId,
        patientId: patientId,
      ),
    );
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

  /// Payments received on [day].
  double revenueOn(DateTime day) => payments
      .where((p) => _sameDay(p.receivedAt, day))
      .fold(0, (s, p) => s + p.amount);

  double get outstandingBalance =>
      invoices.fold(0, (s, i) => s + (i.balance > 0 ? i.balance : 0));
}

class _StoreListener implements BackendListener {
  _StoreListener(this.store);

  final HospitalStore store;

  @override
  void onDocs(Docs docs) => store._onDocs(docs);

  @override
  void onSession(SessionStatus status, {String? staffId, String? patientId}) =>
      store._onSession(status, staffId, patientId);

  @override
  void onSyncError(Object error) => store._onSyncError(error);
}
