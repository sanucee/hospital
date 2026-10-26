import 'dart:convert';

import 'storage.dart';

/// Thrown when a workflow rule is violated (e.g. dispensing more than stock)
/// or a backend operation fails in a way the user should see.
class HospitalException implements Exception {
  HospitalException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The whole hospital as documents: collection → document id → fields.
///
/// This is the shape Firestore stores, and the local backend persists the
/// same structure so both modes share one serialisation path.
typedef Docs = Map<String, Map<String, Map<String, dynamic>>>;

/// Synced collections. `meta` (counters, setup marker) is handled separately.
const kCollections = [
  'users',
  'patients',
  'appointments',
  'consultations',
  'labTests',
  'labOrders',
  'medicines',
  'prescriptions',
  'invoices',
  'invoiceLines',
  'notifications',
  'rooms',
  'admissions',
  'theatres',
  'surgeries',
  'leaves',
  'payments',
  'expenses',
  'payslips',
  'salaries',
  'insurers',
  'claims',
  'suppliers',
  'purchaseOrders',
  'settings',
  'vitals',
  'medicationOrders',
  'medicationDoses',
  'nursingNotes',
  'auditLog',
  'schedules',
  'reminders',
  'bookedSlots',
  'directory',
];

/// Collections only some roles may read; mirrors `firestore.rules`.
const kRestrictedCollections = {
  'expenses': {'admin', 'accountant'},
  'payslips': {'admin', 'accountant'},
  'salaries': {'admin', 'accountant'},
  'auditLog': {'admin'},
};

/// Collections everyone may add to but not everyone may read: devices that
/// can't read them only push their new records.
const kAppendOnlyCollections = {'auditLog'};

/// The collections a staff member with [role] (a `UserRole` name) can read.
List<String> readableCollections(String role) => [
  for (final c in kCollections)
    if (kRestrictedCollections[c]?.contains(role) ?? true) c,
];

/// Patient-portal accounts load only their own records, matched on
/// `patientId` (lab orders only once the doctor has reviewed them)...
const kPortalOwnCollections = [
  'appointments',
  'reminders',
  'invoices',
  'invoiceLines',
  'prescriptions',
];

/// ...plus what they need to book: working hours, taken slots, the doctor
/// directory and the hospital details.
const kPortalSharedCollections = [
  'schedules',
  'bookedSlots',
  'directory',
  'settings',
];

/// What a portal account may change; mirrors `firestore.rules`.
const kPortalWritable = [
  'patients',
  'appointments',
  'reminders',
  'bookedSlots',
];

/// Portal accounts add to these without reading them.
const kPortalAppendOnly = {'auditLog', 'notifications'};

/// The role name of patient-portal accounts in `roles/{uid}`.
const kPatientRole = 'patient';

enum SessionStatus {
  /// No one is signed in.
  signedOut,

  /// Signed in; waiting for the staff profile and first data snapshot.
  loading,

  /// Signed in, but the account has no staff role in this hospital.
  noAccess,

  /// Signed in and data is available.
  ready,
}

abstract class BackendListener {
  /// Delivers the complete data set whenever any of it changes.
  void onDocs(Docs docs);

  /// Remote backends report who is signed in. When ready, [staffId] is set
  /// for staff and [patientId] for patient-portal accounts.
  void onSession(SessionStatus status, {String? staffId, String? patientId});

  /// A write was rejected (e.g. permission denied). The backend has already
  /// rolled the data back via [onDocs].
  void onSyncError(Object error);
}

abstract class HospitalBackend {
  /// True when data is shared between devices and authentication is handled
  /// by the backend rather than the local staff list.
  bool get isRemote;

  Future<void> start(BackendListener listener);

  /// Persists [docs] as the new state. Must apply its changes synchronously
  /// (before the first `await`) so later reads see them, and must not wait
  /// for a server round-trip, so the app keeps working offline.
  Future<void> push(Docs docs);

  /// Atomically reserves the next value of a shared counter, or returns null
  /// if that isn't possible right now (e.g. offline).
  Future<int?> allocate(String counter);

  /// Writes the initial counter values when a hospital is first set up.
  Future<void> initCounters(Map<String, int> counters);

  Future<void> signIn(String email, String password);
  Future<void> signOut();

  /// The signed-in account (remote mode).
  String? get signedInUid;
  String? get signedInEmail;

  /// First-run bootstrap: creates [email] as the hospital's administrator
  /// and returns the account's uid. Fails if the hospital is already set up.
  Future<String> setupHospital({
    required String email,
    required String password,
    required String staffId,
  });

  /// Creates a sign-in account for a staff member and grants [role].
  /// Returns the account's uid.
  Future<String> createLogin({
    required String email,
    required String password,
    required String role,
    required String staffId,
  });

  /// Patient portal: creates an account for a new patient and their
  /// patient record together, and signs them in.
  Future<void> registerPortalAccount({
    required String email,
    required String password,
    required String patientId,
    required Map<String, dynamic> patient,
  });

  /// Reception gives an existing patient a portal account. Returns its uid.
  Future<String> createPortalLogin({
    required String email,
    required String password,
    required String patientId,
  });

  /// Removes the role of the account with [uid], revoking its access.
  Future<void> revokeLogin(String uid);

  Future<void> dispose();
}

/// Keeps everything on this device. Sign-in is checked against the local
/// staff list by [HospitalStore].
class LocalBackend implements HospitalBackend {
  LocalBackend(this.storage);

  final StorageBackend storage;
  Future<void> _lastWrite = Future.value();

  @override
  bool get isRemote => false;

  @override
  Future<void> start(BackendListener listener) async {
    final raw = await storage.read();
    final docs = <String, Map<String, Map<String, dynamic>>>{};
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final MapEntry(key: c, value: v) in decoded.entries) {
        docs[c] = {
          for (final MapEntry(key: id, value: d) in (v as Map).entries)
            id as String: (d as Map).cast<String, dynamic>(),
        };
      }
    }
    listener.onDocs(docs);
  }

  @override
  Future<void> push(Docs docs) {
    // Encode now so later in-memory mutations can't leak into this write, and
    // chain writes so they land in order.
    final data = jsonEncode(docs);
    return _lastWrite = _lastWrite.then((_) => storage.write(data));
  }

  @override
  Future<int?> allocate(String counter) async => null;

  @override
  Future<void> initCounters(Map<String, int> counters) async {}

  Never _unsupported() => throw UnsupportedError('Not available in local mode');

  @override
  Future<void> signIn(String email, String password) => _unsupported();
  @override
  Future<void> signOut() async {}
  @override
  String? get signedInUid => null;
  @override
  String? get signedInEmail => null;
  @override
  Future<String> setupHospital({
    required String email,
    required String password,
    required String staffId,
  }) => _unsupported();
  @override
  Future<String> createLogin({
    required String email,
    required String password,
    required String role,
    required String staffId,
  }) => _unsupported();
  @override
  Future<void> registerPortalAccount({
    required String email,
    required String password,
    required String patientId,
    required Map<String, dynamic> patient,
  }) => _unsupported();
  @override
  Future<String> createPortalLogin({
    required String email,
    required String password,
    required String patientId,
  }) => _unsupported();
  @override
  Future<void> revokeLogin(String uid) => _unsupported();
  @override
  Future<void> dispose() async {}
}

/// Structural equality for JSON-like values. Numbers compare by value so
/// `50` and `50.0` (which Firestore may hand back interchangeably) match.
bool jsonEquals(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is Map && b is Map) {
    final keys = {...a.keys, ...b.keys};
    return keys.every((k) => jsonEquals(a[k], b[k]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
