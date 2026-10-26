part of 'models.dart';

/// Hospital details printed on receipts and reports.
class HospitalProfile {
  HospitalProfile({
    this.name = 'CareConnect Hospital',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.taxId = '',
    this.receiptFooter = 'Thank you. Get well soon!',
  });

  String name;
  String address;
  String phone;
  String email;
  String taxId;
  String receiptFooter;

  static const docId = 'profile';

  Map<String, dynamic> toJson() => {
    'id': docId,
    'name': name,
    'address': address,
    'phone': phone,
    'email': email,
    'taxId': taxId,
    'receiptFooter': receiptFooter,
  };

  factory HospitalProfile.fromJson(Map<String, dynamic> j) => HospitalProfile(
    name: j['name'] ?? 'CareConnect Hospital',
    address: j['address'] ?? '',
    phone: j['phone'] ?? '',
    email: j['email'] ?? '',
    taxId: j['taxId'] ?? '',
    receiptFooter: j['receiptFooter'] ?? '',
  );
}

/// An insurance company or corporate payer.
class InsuranceProvider {
  InsuranceProvider({
    required this.id,
    required this.name,
    this.coveragePercent = 80,
    this.coverageLimit = 0,
    this.contact = '',
    this.active = true,
  });

  final String id;
  String name;

  /// Share of each bill the insurer pays.
  double coveragePercent;

  /// Maximum the insurer pays per bill; 0 means no limit.
  double coverageLimit;
  String contact;
  bool active;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'coveragePercent': coveragePercent,
    'coverageLimit': coverageLimit,
    'contact': contact,
    'active': active,
  };

  factory InsuranceProvider.fromJson(Map<String, dynamic> j) =>
      InsuranceProvider(
        id: j['id'],
        name: j['name'],
        coveragePercent: (j['coveragePercent'] as num?)?.toDouble() ?? 80,
        coverageLimit: (j['coverageLimit'] as num?)?.toDouble() ?? 0,
        contact: j['contact'] ?? '',
        active: j['active'] ?? true,
      );
}

enum ClaimStatus { draft, submitted, approved, rejected, paid }

extension ClaimStatusX on ClaimStatus {
  String get label => switch (this) {
    ClaimStatus.draft => 'Draft',
    ClaimStatus.submitted => 'Submitted',
    ClaimStatus.approved => 'Approved',
    ClaimStatus.rejected => 'Rejected',
    ClaimStatus.paid => 'Paid',
  };
}

/// A request to an insurer to pay its share of one invoice.
class InsuranceClaim {
  InsuranceClaim({
    required this.id,
    required this.number,
    required this.invoiceId,
    required this.insurerId,
    required this.patientId,
    required this.amountClaimed,
    required this.createdAt,
    this.status = ClaimStatus.draft,
    this.submittedAt,
    this.decidedAt,
    this.approvedAmount,
    this.amountPaid = 0,
    this.insurerReference = '',
    this.notes = '',
  });

  final String id;
  final String number;
  final String invoiceId;
  final String insurerId;
  final String patientId;
  double amountClaimed;
  final DateTime createdAt;
  ClaimStatus status;
  DateTime? submittedAt;
  DateTime? decidedAt;
  double? approvedAmount;
  double amountPaid;

  /// The insurer's own claim or authorisation number.
  String insurerReference;
  String notes;

  double get outstanding => (approvedAmount ?? 0) - amountPaid;

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'invoiceId': invoiceId,
    'insurerId': insurerId,
    'patientId': patientId,
    'amountClaimed': amountClaimed,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'submittedAt': submittedAt?.toIso8601String(),
    'decidedAt': decidedAt?.toIso8601String(),
    'approvedAmount': approvedAmount,
    'amountPaid': amountPaid,
    'insurerReference': insurerReference,
    'notes': notes,
  };

  factory InsuranceClaim.fromJson(Map<String, dynamic> j) => InsuranceClaim(
    id: j['id'],
    number: j['number'],
    invoiceId: j['invoiceId'],
    insurerId: j['insurerId'],
    patientId: j['patientId'],
    amountClaimed: (j['amountClaimed'] as num).toDouble(),
    createdAt: DateTime.parse(j['createdAt']),
    status: _enumByName(ClaimStatus.values, j['status'], ClaimStatus.draft),
    submittedAt: _date(j['submittedAt']),
    decidedAt: _date(j['decidedAt']),
    approvedAmount: (j['approvedAmount'] as num?)?.toDouble(),
    amountPaid: (j['amountPaid'] as num?)?.toDouble() ?? 0,
    insurerReference: j['insurerReference'] ?? '',
    notes: j['notes'] ?? '',
  );
}

class Supplier {
  Supplier({
    required this.id,
    required this.name,
    this.contactPerson = '',
    this.phone = '',
    this.email = '',
    this.address = '',
  });

  final String id;
  String name;
  String contactPerson;
  String phone;
  String email;
  String address;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'contactPerson': contactPerson,
    'phone': phone,
    'email': email,
    'address': address,
  };

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
    id: j['id'],
    name: j['name'],
    contactPerson: j['contactPerson'] ?? '',
    phone: j['phone'] ?? '',
    email: j['email'] ?? '',
    address: j['address'] ?? '',
  );
}

class PurchaseItem {
  PurchaseItem({
    required this.medicineId,
    required this.medicineName,
    required this.quantity,
    required this.unitCost,
    this.receivedQuantity = 0,
  });

  final String medicineId;
  final String medicineName;
  int quantity;
  double unitCost;
  int receivedQuantity;

  int get outstanding => quantity - receivedQuantity;
  double get total => quantity * unitCost;

  Map<String, dynamic> toJson() => {
    'medicineId': medicineId,
    'medicineName': medicineName,
    'quantity': quantity,
    'unitCost': unitCost,
    'receivedQuantity': receivedQuantity,
  };

  factory PurchaseItem.fromJson(Map<String, dynamic> j) => PurchaseItem(
    medicineId: j['medicineId'],
    medicineName: j['medicineName'],
    quantity: j['quantity'],
    unitCost: (j['unitCost'] as num).toDouble(),
    receivedQuantity: j['receivedQuantity'] ?? 0,
  );
}

/// One line of a delivery: what arrived, with batch and expiry for
/// traceability.
class ReceivedLine {
  ReceivedLine({
    required this.medicineId,
    required this.quantity,
    this.batchNumber = '',
    this.expiryDate,
  });

  final String medicineId;
  final int quantity;
  final String batchNumber;
  final DateTime? expiryDate;

  Map<String, dynamic> toJson() => {
    'medicineId': medicineId,
    'quantity': quantity,
    'batchNumber': batchNumber,
    'expiryDate': expiryDate?.toIso8601String(),
  };

  factory ReceivedLine.fromJson(Map<String, dynamic> j) => ReceivedLine(
    medicineId: j['medicineId'],
    quantity: j['quantity'],
    batchNumber: j['batchNumber'] ?? '',
    expiryDate: _date(j['expiryDate']),
  );
}

class GoodsReceipt {
  GoodsReceipt({
    required this.receivedAt,
    required this.lines,
    this.receivedBy,
    this.deliveryNote = '',
  });

  final DateTime receivedAt;
  final List<ReceivedLine> lines;
  final String? receivedBy;

  /// The supplier's delivery note or invoice number.
  final String deliveryNote;

  Map<String, dynamic> toJson() => {
    'receivedAt': receivedAt.toIso8601String(),
    'lines': lines.map((l) => l.toJson()).toList(),
    'receivedBy': receivedBy,
    'deliveryNote': deliveryNote,
  };

  factory GoodsReceipt.fromJson(Map<String, dynamic> j) => GoodsReceipt(
    receivedAt: DateTime.parse(j['receivedAt']),
    lines: (j['lines'] as List).map((e) => ReceivedLine.fromJson(e)).toList(),
    receivedBy: j['receivedBy'],
    deliveryNote: j['deliveryNote'] ?? '',
  );
}

enum PurchaseStatus { draft, ordered, partiallyReceived, received, cancelled }

extension PurchaseStatusX on PurchaseStatus {
  String get label => switch (this) {
    PurchaseStatus.draft => 'Draft',
    PurchaseStatus.ordered => 'Ordered',
    PurchaseStatus.partiallyReceived => 'Partly received',
    PurchaseStatus.received => 'Received',
    PurchaseStatus.cancelled => 'Cancelled',
  };
}

class PurchaseOrder {
  PurchaseOrder({
    required this.id,
    required this.number,
    required this.supplierId,
    required this.items,
    required this.createdAt,
    this.status = PurchaseStatus.draft,
    this.orderedAt,
    this.expectedOn,
    this.createdBy,
    this.notes = '',
    List<GoodsReceipt>? receipts,
    this.paidAt,
    this.expenseId,
  }) : receipts = receipts ?? [];

  final String id;
  final String number;
  String supplierId;
  final List<PurchaseItem> items;
  final DateTime createdAt;
  PurchaseStatus status;
  DateTime? orderedAt;
  DateTime? expectedOn;
  final String? createdBy;
  String notes;
  final List<GoodsReceipt> receipts;

  /// Set when accounts pays the supplier; [expenseId] is the expense
  /// recorded for that payment.
  DateTime? paidAt;
  String? expenseId;

  double get total => items.fold(0, (s, i) => s + i.total);

  /// Value of what has actually been delivered (what the supplier bills).
  double get receivedValue =>
      items.fold(0, (s, i) => s + i.receivedQuantity * i.unitCost);

  bool get isPaid => paidAt != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'supplierId': supplierId,
    'items': items.map((i) => i.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'orderedAt': orderedAt?.toIso8601String(),
    'expectedOn': expectedOn?.toIso8601String(),
    'createdBy': createdBy,
    'notes': notes,
    'receipts': receipts.map((r) => r.toJson()).toList(),
    'paidAt': paidAt?.toIso8601String(),
    'expenseId': expenseId,
  };

  factory PurchaseOrder.fromJson(Map<String, dynamic> j) => PurchaseOrder(
    id: j['id'],
    number: j['number'],
    supplierId: j['supplierId'],
    items: (j['items'] as List).map((e) => PurchaseItem.fromJson(e)).toList(),
    createdAt: DateTime.parse(j['createdAt']),
    status: _enumByName(
      PurchaseStatus.values,
      j['status'],
      PurchaseStatus.draft,
    ),
    orderedAt: _date(j['orderedAt']),
    expectedOn: _date(j['expectedOn']),
    createdBy: j['createdBy'],
    notes: j['notes'] ?? '',
    receipts: ((j['receipts'] as List?) ?? [])
        .map((e) => GoodsReceipt.fromJson(e))
        .toList(),
    paidAt: _date(j['paidAt']),
    expenseId: j['expenseId'],
  );
}
