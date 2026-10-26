part of 'hospital_store.dart';

/// Collections whose changes are not worth auditing (or are the log itself).
const _unaudited = {
  'meta',
  'notifications',
  'auditLog',
  // Derived from staff and appointment records, which are audited.
  'directory',
  'bookedSlots',
};

const _nouns = {
  'users': 'staff member',
  'patients': 'patient',
  'appointments': 'appointment',
  'consultations': 'consultation',
  'labTests': 'lab test',
  'labOrders': 'lab order',
  'medicines': 'medicine',
  'prescriptions': 'prescription',
  'invoices': 'invoice',
  'invoiceLines': 'charge',
  'rooms': 'room',
  'admissions': 'admission',
  'theatres': 'theatre',
  'surgeries': 'surgery',
  'leaves': 'leave request',
  'payments': 'payment',
  'expenses': 'expense',
  'payslips': 'payslip',
  'salaries': 'salary',
  'insurers': 'insurer',
  'claims': 'insurance claim',
  'suppliers': 'supplier',
  'purchaseOrders': 'purchase order',
  'settings': 'hospital details',
  'vitals': 'observations',
  'medicationOrders': 'ward medication',
  'medicationDoses': 'medication dose',
  'nursingNotes': 'nursing note',
  'schedules': 'working hours',
  'reminders': 'reminder',
  'tills': 'cash till',
  'refunds': 'refund',
  'emergencyVisits': 'emergency visit',
  'imagingStudies': 'imaging study',
  'imagingOrders': 'imaging request',
  'bloodDonors': 'blood donor',
  'bloodUnits': 'blood unit',
  'bloodRequests': 'blood request',
  'storeItems': 'store item',
  'requisitions': 'requisition',
  'stockMovements': 'stock movement',
};

/// A readable name for a collection, e.g. "charge" for invoice lines.
String auditRecordType(String collection) =>
    collection == 'session' ? 'sign-in' : _nouns[collection] ?? collection;

/// Fields never shown in the log.
const _secret = {'password'};

/// Audit entries for everything that differs between [before] and [after].
List<AuditEntry> _auditChanges(
  HospitalStore s,
  Docs before,
  Docs after,
  String userId,
  String userName,
) {
  final now = DateTime.now();
  final entries = <AuditEntry>[];
  void add(
    String action,
    String c,
    String id,
    Map<String, dynamic> doc,
    String summary,
  ) {
    final patientId =
        doc['patientId'] as String? ?? (c == 'patients' ? id : null);
    final text = summary.length > 400
        ? '${summary.substring(0, 397)}...'
        : summary;
    entries.add(
      AuditEntry(
        id: s.newId('AUD'),
        at: now,
        userId: userId,
        userName: userName,
        action: action,
        collection: c,
        docId: id,
        summary: text,
        patientId: patientId,
      ),
    );
  }

  for (final c in {...before.keys, ...after.keys}) {
    if (_unaudited.contains(c)) continue;
    final b = before[c] ?? const {};
    final a = after[c] ?? const {};
    for (final MapEntry(key: id, value: doc) in a.entries) {
      final old = b[id];
      if (old == null) {
        add('created', c, id, doc, 'Created ${_describe(s, c, id, doc)}');
      } else if (!jsonEquals(old, doc)) {
        final changes = [
          for (final k in {...old.keys, ...doc.keys})
            if (k != 'id' && !jsonEquals(old[k], doc[k]))
              _change(k, old[k], doc[k]),
        ];
        add(
          'updated',
          c,
          id,
          doc,
          'Updated ${_describe(s, c, id, doc)}: ${changes.join('; ')}',
        );
      }
    }
    for (final MapEntry(key: id, value: doc) in b.entries) {
      if (!a.containsKey(id)) {
        add('deleted', c, id, doc, 'Deleted ${_describe(s, c, id, doc)}');
      }
    }
  }
  return entries;
}

/// A readable name for a record, e.g. `lab order "Lipid Profile" (Ali
/// Hassan)`.
String _describe(HospitalStore s, String c, String id, Map<String, dynamic> d) {
  final noun = _nouns[c] ?? c;
  String? staff(Object? id) => id is String ? s.userById(id)?.name : null;
  num n(Object? v) => v is num ? v : 0;
  final label = switch (c) {
    'patients' => '${d['name']} (${d['mrn']})',
    'invoiceLines' =>
      '"${d['description']}" ${_money(n(d['quantity']) * n(d['unitPrice']))}',
    'payments' => '${_money(n(d['amount']))} by ${d['method']}',
    'expenses' => '"${d['description']}" ${_money(n(d['amount']))}',
    'salaries' => 'for ${staff(d['staffId']) ?? d['staffId']}',
    'payslips' =>
      'for ${staff(d['staffId']) ?? d['staffId']} '
          '(${(d['month'] as String? ?? '').substring(0, 7)})',
    'leaves' => 'for ${staff(d['staffId']) ?? d['staffId']}',
    'users' => '${d['name']} (${d['role']})',
    'medicationDoses' => '(${d['status']})',
    _ =>
      d['number'] ??
          d['name'] ??
          d['testName'] ??
          d['procedure'] ??
          d['medicineName'] ??
          d['description'] ??
          d['category'] ??
          id,
  };
  final patient = c == 'patients' || d['patientId'] is! String
      ? null
      : s.patientById(d['patientId'] as String)?.name;
  return '$noun ${label is String && label.startsWith('(') ? label : '"$label"'}'
      '${patient == null ? '' : ' for $patient'}';
}

String _change(String field, Object? old, Object? now) {
  if (_secret.contains(field)) return '$field changed';
  bool scalar(Object? v) => v == null || v is num || v is String || v is bool;
  if (!scalar(old) || !scalar(now)) return '$field changed';
  return '$field: ${_short(old)} → ${_short(now)}';
}

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');

String _short(Object? v) {
  if (v == null || v == '') return '—';
  if (v is double) return v.toStringAsFixed(2);
  var t = v.toString();
  if (_isoDate.hasMatch(t)) t = t.substring(0, 16).replaceFirst('T', ' ');
  return t.length > 40 ? '${t.substring(0, 37)}...' : t;
}

String _money(num v) => v.toStringAsFixed(2);
