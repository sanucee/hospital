import '../protocol.dart';

const _admin = 'admin';
const _rec = 'receptionist';
const _doc = 'doctor';
const _lab = 'labTechnician';
const _pha = 'pharmacist';
const _nur = 'nurse';
const _acc = 'accountant';
const _rad = 'radiographer';
const _sto = 'storekeeper';

const kStaffRoles = {_admin, _rec, _doc, _lab, _pha, _nur, _acc, _rad, _sto};
const _cashiers = {_admin, _rec, _pha, _acc};
const _finance = {_admin, _acc};

/// Who may read and change one collection. This mirrors `firestore.rules`
/// role by role; the few rules there that depend on other documents (tills,
/// refunds) are simplified to the roles involved.
class Rule {
  const Rule({
    this.read = kStaffRoles,
    this.create = const {},
    this.update = const {},
    this.delete = const {},
    this.updateOnly = const {},
    this.updateOnlyTo = const {},
    this.updateOnlyFrom = const {},
    this.ownField,
    this.ownId = false,
  });

  /// Everyone reads, [roles] write.
  const Rule.write(Set<String> roles, {Set<String> read = kStaffRoles})
    : this(read: read, create: roles, update: roles, delete: roles);

  final Set<String> read;
  final Set<String> create;
  final Set<String> update;
  final Set<String> delete;

  /// Roles that may update only the listed fields.
  final Map<String, Set<String>> updateOnly;

  /// For [updateOnly] changes: values those fields must be set to, and
  /// values they must have beforehand (e.g. only `pending` → `cancelled`).
  final Map<String, Object?> updateOnlyTo;
  final Map<String, Object?> updateOnlyFrom;

  /// Non-admins may only create documents whose [ownField] is their staff id
  /// (leave requests, audit entries, requisitions).
  final String? ownField;

  /// Non-admins may only write the document whose id is their staff id
  /// (a doctor's own working hours).
  final bool ownId;
}

final kRules = <String, Rule>{
  'users': Rule.write({_admin}),
  'patients': Rule(
    create: {_admin, _rec, _doc, _nur},
    update: {_admin, _rec},
    delete: {_admin},
    updateOnly: {
      _lab: {'bloodGroup'},
    },
  ),
  'appointments': Rule(
    create: {_admin, _rec, _doc},
    update: {_admin, _rec, _doc},
    delete: {_admin},
  ),
  'bookedSlots': Rule.write({_admin, _rec, _doc}),
  'directory': Rule.write(kStaffRoles),
  'consultations': Rule(
    create: {_admin, _doc},
    update: {_admin, _doc},
    delete: {_admin},
  ),
  'labTests': Rule.write({_admin, _lab}),
  'labOrders': Rule(
    create: {_admin, _doc},
    update: {_admin, _doc, _lab},
    delete: {_admin},
  ),
  'medicines': Rule.write({_admin, _pha}),
  'prescriptions': Rule(
    create: {_admin, _doc},
    update: {_admin, _doc, _pha},
    delete: {_admin},
  ),
  'invoices': Rule(create: kStaffRoles, update: kStaffRoles, delete: {_admin}),
  // The lab and radiology remove the charge for a cancelled order.
  'invoiceLines': Rule.write(kStaffRoles),
  'notifications': Rule(
    create: kStaffRoles,
    delete: {_admin},
    updateOnly: {
      for (final r in kStaffRoles) r: {'readBy'},
    },
  ),
  'rooms': Rule.write({_admin}),
  'theatres': Rule.write({_admin}),
  'admissions': Rule(
    create: {_admin, _rec, _doc, _nur},
    update: {_admin, _rec, _doc, _nur},
    delete: {_admin},
  ),
  'surgeries': Rule(
    create: {_admin, _doc},
    update: {_admin, _doc, _nur},
    delete: {_admin},
  ),
  'leaves': Rule(
    create: kStaffRoles,
    update: {_admin},
    delete: {_admin},
    ownField: 'staffId',
  ),
  'payments': Rule(create: _cashiers, update: {_admin}, delete: {_admin}),
  'expenses': Rule.write(_finance, read: _finance),
  'payslips': Rule.write(_finance, read: _finance),
  'salaries': Rule.write(_finance, read: _finance),
  'insurers': Rule.write(_finance),
  'claims': Rule.write({_admin, _rec, _acc}),
  'suppliers': Rule.write({_admin, _pha}),
  'purchaseOrders': Rule(
    create: {_admin, _pha},
    update: {_admin, _pha},
    delete: {_admin, _pha},
    updateOnly: {
      _acc: {'paidAt', 'expenseId'},
    },
  ),
  'settings': Rule.write({_admin}),
  'vitals': Rule(create: {_admin, _doc, _nur}),
  'medicationOrders': Rule(create: {_admin, _doc}, update: {_admin, _doc}),
  'medicationDoses': Rule(create: {_admin, _doc, _nur}),
  'nursingNotes': Rule(create: {_admin, _doc, _nur}),
  'auditLog': Rule(read: {_admin}, create: kStaffRoles, ownField: 'userId'),
  'schedules': Rule(
    create: {_admin, _doc},
    update: {_admin, _doc},
    delete: {_admin, _doc},
    ownId: true,
  ),
  'reminders': Rule(create: {_admin, _rec, _doc}, update: {_admin, _rec, _doc}),
  'tills': Rule(read: _cashiers, create: _cashiers, update: _cashiers),
  'refunds': Rule(read: _cashiers, create: _cashiers, update: _cashiers),
  'emergencyVisits': Rule(
    create: {_admin, _rec, _doc, _nur},
    update: {_admin, _rec, _doc, _nur},
    delete: {_admin},
  ),
  'imagingStudies': Rule.write({_admin, _rad}),
  'imagingOrders': Rule(
    create: {_admin, _doc},
    update: {_admin, _doc, _rad},
    delete: {_admin},
  ),
  'bloodDonors': Rule.write({_admin, _lab}),
  'bloodUnits': Rule(
    create: {_admin, _lab},
    update: {_admin, _lab},
    delete: {_admin},
  ),
  'bloodRequests': Rule(
    create: {_admin, _doc},
    update: {_admin, _lab},
    delete: {_admin},
    updateOnly: {
      _doc: {'status', 'cancelReason', 'unitIds'},
    },
    updateOnlyTo: {'status': 'cancelled'},
    updateOnlyFrom: {'status': 'pending'},
    ownField: 'doctorId',
  ),
  'storeItems': Rule.write({_admin, _sto}),
  'requisitions': Rule(
    create: kStaffRoles,
    update: {_admin, _sto},
    ownField: 'requestedBy',
    updateOnly: {
      for (final r in kStaffRoles) r: {'status'},
    },
    updateOnlyTo: {'status': 'cancelled'},
    updateOnlyFrom: {'status': 'pending'},
  ),
  'stockMovements': Rule(create: {_admin, _sto}),
};

/// Collections [role] may read.
List<String> readableBy(String role) => [
  for (final MapEntry(key: c, value: r) in kRules.entries)
    if (r.read.contains(role)) c,
];

bool canRead(String role, String collection) =>
    kRules[collection]?.read.contains(role) ?? false;

/// Why [op] is refused for this account, or null if it is allowed.
String? refusal(
  Op op, {
  required String role,
  required String? staffId,
  required Map<String, dynamic>? current,
}) {
  final rule = kRules[op.collection];
  if (rule == null) return 'Unknown collection ${op.collection}';
  final admin = role == _admin;
  final what = '${op.collection}/${op.id}';

  if (op.kind == OpKind.delete) {
    if (current == null) return null;
    return rule.delete.contains(role) && _ownIdOk(rule, op, admin, staffId)
        ? null
        : 'Your role may not delete $what';
  }

  if (current == null) {
    if (!rule.create.contains(role)) return 'Your role may not add $what';
    final next = op.applyTo(null)!;
    if (!admin && rule.ownField != null && next[rule.ownField] != staffId) {
      return 'You may only add $what in your own name';
    }
    return _ownIdOk(rule, op, admin, staffId)
        ? null
        : 'You may only change your own ${op.collection}';
  }

  // An update. A full replacement counts as changing every field that differs.
  final changed = op.kind == OpKind.set
      ? {
          for (final k in {...current.keys, ...op.data!.keys})
            if (!_same(current[k], op.data![k])) k,
        }
      : op.fields;
  if (changed.isEmpty) return null;
  if (rule.update.contains(role)) {
    return _ownIdOk(rule, op, admin, staffId)
        ? null
        : 'You may only change your own ${op.collection}';
  }
  final allowed = rule.updateOnly[role];
  if (allowed != null && changed.every(allowed.contains)) {
    // e.g. a doctor withdrawing their own pending blood request.
    if (rule.ownField != null && current[rule.ownField] != staffId) {
      return 'You may only change your own ${op.collection}';
    }
    final next = op.applyTo(current)!;
    for (final MapEntry(key: f, value: v) in rule.updateOnlyFrom.entries) {
      if (current[f] != v) return 'Your role may not change $what now';
    }
    for (final MapEntry(key: f, value: v) in rule.updateOnlyTo.entries) {
      if (changed.contains(f) && next[f] != v) {
        return 'Your role may not change $what that way';
      }
    }
    return null;
  }
  return 'Your role may not change $what';
}

bool _ownIdOk(Rule rule, Op op, bool admin, String? staffId) =>
    !rule.ownId || admin || op.id == staffId;

bool _same(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is Map && b is Map) {
    final keys = {...a.keys, ...b.keys};
    return keys.every((k) => _same(a[k], b[k]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
