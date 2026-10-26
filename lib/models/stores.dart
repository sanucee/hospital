part of 'models.dart';

const kStoreCategories = [
  'Medical consumables',
  'Surgical supplies',
  'Linen',
  'Cleaning',
  'Stationery',
  'Equipment',
];

/// Departments that draw supplies from the general store.
const kStoreDepartments = [
  'Wards',
  'Emergency',
  'Operation theatre',
  'Laboratory',
  'Radiology',
  'Pharmacy',
  'Reception',
  'Administration',
  'Facilities',
];

/// A non-drug item kept in the general store (gloves, gauze, linen...).
class StoreItem {
  StoreItem({
    required this.id,
    required this.name,
    required this.category,
    this.unit = 'piece',
    this.stock = 0,
    this.reorderLevel = 0,
    this.unitCost = 0,
    this.patientPrice = 0,
  });

  final String id;
  String name;
  String category;

  /// What one unit is: piece, box, pack, roll...
  String unit;
  int stock;
  int reorderLevel;

  /// Latest purchase cost per unit.
  double unitCost;

  /// Charged to the patient when issued for a patient; 0 = not billable.
  double patientPrice;

  bool get isLowStock => stock <= reorderLevel;
  bool get billable => patientPrice > 0;
  double get stockValue => stock * unitCost;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'unit': unit,
    'stock': stock,
    'reorderLevel': reorderLevel,
    'unitCost': unitCost,
    'patientPrice': patientPrice,
  };

  factory StoreItem.fromJson(Map<String, dynamic> j) => StoreItem(
    id: j['id'],
    name: j['name'],
    category: j['category'] ?? 'Medical consumables',
    unit: j['unit'] ?? 'piece',
    stock: (j['stock'] as num?)?.toInt() ?? 0,
    reorderLevel: (j['reorderLevel'] as num?)?.toInt() ?? 0,
    unitCost: (j['unitCost'] as num?)?.toDouble() ?? 0,
    patientPrice: (j['patientPrice'] as num?)?.toDouble() ?? 0,
  );
}

class RequisitionLine {
  RequisitionLine({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    this.issuedQuantity = 0,
  });

  final String itemId;
  final String itemName;
  final int quantity;
  int issuedQuantity;

  int get outstanding => quantity - issuedQuantity;

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'itemName': itemName,
    'quantity': quantity,
    'issuedQuantity': issuedQuantity,
  };

  factory RequisitionLine.fromJson(Map<String, dynamic> j) => RequisitionLine(
    itemId: j['itemId'],
    itemName: j['itemName'] ?? '',
    quantity: (j['quantity'] as num).toInt(),
    issuedQuantity: (j['issuedQuantity'] as num?)?.toInt() ?? 0,
  );
}

enum RequisitionStatus { pending, partlyIssued, issued, rejected, cancelled }

extension RequisitionStatusX on RequisitionStatus {
  String get label => switch (this) {
    RequisitionStatus.pending => 'Pending',
    RequisitionStatus.partlyIssued => 'Partly issued',
    RequisitionStatus.issued => 'Issued',
    RequisitionStatus.rejected => 'Rejected',
    RequisitionStatus.cancelled => 'Cancelled',
  };
}

/// A department's request for supplies from the store. When it is for a
/// patient, billable items are charged to that patient when issued.
class Requisition {
  Requisition({
    required this.id,
    required this.number,
    required this.department,
    required this.requestedBy,
    required this.requestedAt,
    required this.lines,
    this.patientId,
    this.notes = '',
    this.status = RequisitionStatus.pending,
    this.issuedBy,
    this.issuedAt,
    this.decisionNote = '',
  });

  final String id;

  /// e.g. `REQ-00012`.
  final String number;
  final String department;
  final String requestedBy;
  final DateTime requestedAt;
  final List<RequisitionLine> lines;
  final String? patientId;
  String notes;
  RequisitionStatus status;
  String? issuedBy;
  DateTime? issuedAt;
  String decisionNote;

  bool get isOpen =>
      status == RequisitionStatus.pending ||
      status == RequisitionStatus.partlyIssued;

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'department': department,
    'requestedBy': requestedBy,
    'requestedAt': requestedAt.toIso8601String(),
    'lines': lines.map((l) => l.toJson()).toList(),
    'patientId': patientId,
    'notes': notes,
    'status': status.name,
    'issuedBy': issuedBy,
    'issuedAt': issuedAt?.toIso8601String(),
    'decisionNote': decisionNote,
  };

  factory Requisition.fromJson(Map<String, dynamic> j) => Requisition(
    id: j['id'],
    number: j['number'],
    department: j['department'] ?? '',
    requestedBy: j['requestedBy'],
    requestedAt: DateTime.parse(j['requestedAt']),
    lines: (j['lines'] as List)
        .map((e) => RequisitionLine.fromJson(e))
        .toList(),
    patientId: j['patientId'],
    notes: j['notes'] ?? '',
    status: _enumByName(
      RequisitionStatus.values,
      j['status'],
      RequisitionStatus.pending,
    ),
    issuedBy: j['issuedBy'],
    issuedAt: _date(j['issuedAt']),
    decisionNote: j['decisionNote'] ?? '',
  );
}

enum StockMovementKind { received, issued, adjusted }

extension StockMovementKindX on StockMovementKind {
  String get label => switch (this) {
    StockMovementKind.received => 'Received',
    StockMovementKind.issued => 'Issued',
    StockMovementKind.adjusted => 'Stock count',
  };
}

/// One change to a store item's stock, for the stock card. Never edited.
class StockMovement {
  StockMovement({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.quantity,
    required this.at,
    this.balance = 0,
    this.unitCost = 0,
    this.reference = '',
    this.by,
  });

  final String id;
  final String itemId;
  final StockMovementKind kind;

  /// Positive for stock in, negative for stock out.
  final int quantity;
  final DateTime at;

  /// Stock after the movement, as this device saw it.
  final int balance;
  final double unitCost;

  /// Supplier and delivery note, requisition number, or count reason.
  final String reference;
  final String? by;

  Map<String, dynamic> toJson() => {
    'id': id,
    'itemId': itemId,
    'kind': kind.name,
    'quantity': quantity,
    'at': at.toIso8601String(),
    'balance': balance,
    'unitCost': unitCost,
    'reference': reference,
    'by': by,
  };

  factory StockMovement.fromJson(Map<String, dynamic> j) => StockMovement(
    id: j['id'],
    itemId: j['itemId'],
    kind: _enumByName(
      StockMovementKind.values,
      j['kind'],
      StockMovementKind.adjusted,
    ),
    quantity: (j['quantity'] as num).toInt(),
    at: DateTime.parse(j['at']),
    balance: (j['balance'] as num?)?.toInt() ?? 0,
    unitCost: (j['unitCost'] as num?)?.toDouble() ?? 0,
    reference: j['reference'] ?? '',
    by: j['by'],
  );
}
