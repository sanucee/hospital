part of 'models.dart';

/// A cashier's cash drawer for one shift: opened with a float, closed by
/// counting the cash, so any difference shows up at the cash-up.
class CashTill {
  CashTill({
    required this.id,
    required this.cashierId,
    required this.openedAt,
    this.openingFloat = 0,
    this.closedAt,
    this.countedCash,
    this.expectedCash,
    this.notes = '',
  });

  final String id;
  final String cashierId;
  final DateTime openedAt;
  final double openingFloat;
  DateTime? closedAt;

  /// Cash counted in the drawer at closing.
  double? countedCash;

  /// Float plus cash taken, worked out at closing.
  double? expectedCash;
  String notes;

  bool get isOpen => closedAt == null;

  /// Counted minus expected: negative when cash is missing.
  double? get variance => countedCash == null || expectedCash == null
      ? null
      : countedCash! - expectedCash!;

  Map<String, dynamic> toJson() => {
    'id': id,
    'cashierId': cashierId,
    'openedAt': openedAt.toIso8601String(),
    'openingFloat': openingFloat,
    'closedAt': closedAt?.toIso8601String(),
    'countedCash': countedCash,
    'expectedCash': expectedCash,
    'notes': notes,
  };

  factory CashTill.fromJson(Map<String, dynamic> j) => CashTill(
    id: j['id'],
    cashierId: j['cashierId'],
    openedAt: DateTime.parse(j['openedAt']),
    openingFloat: (j['openingFloat'] as num?)?.toDouble() ?? 0,
    closedAt: _date(j['closedAt']),
    countedCash: (j['countedCash'] as num?)?.toDouble(),
    expectedCash: (j['expectedCash'] as num?)?.toDouble(),
    notes: j['notes'] ?? '',
  );
}

/// The outcome of one counter transaction.
class CounterReceipt {
  CounterReceipt({
    required this.receiptNo,
    required this.payments,
    required this.tendered,
    required this.change,
  });

  final String receiptNo;
  final List<Payment> payments;

  /// Cash handed over (cash payments only).
  final double? tendered;
  final double change;

  double get total => payments.fold(0, (s, p) => s + p.amount);
}

enum RefundStatus { pending, approved, rejected, paid }

extension RefundStatusX on RefundStatus {
  String get label => switch (this) {
    RefundStatus.pending => 'Awaiting approval',
    RefundStatus.approved => 'Approved – to pay out',
    RefundStatus.rejected => 'Rejected',
    RefundStatus.paid => 'Refunded',
  };
}

/// Money given back to a patient against an earlier payment: requested at
/// the counter, approved by administration or accounts, then paid out.
class Refund {
  Refund({
    required this.id,
    required this.paymentId,
    required this.invoiceId,
    required this.patientId,
    required this.amount,
    required this.method,
    required this.reason,
    required this.requestedBy,
    required this.requestedAt,
    this.status = RefundStatus.pending,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote = '',
    this.paidBy,
    this.paidAt,
    this.reference = '',
    this.number,
  });

  final String id;

  /// The payment being refunded.
  final String paymentId;
  final String invoiceId;
  final String patientId;
  final double amount;

  /// How the money goes back: cash from the till, or a card reversal,
  /// transfer or mobile-money payment with a reference.
  final String method;
  final String reason;
  final String requestedBy;
  final DateTime requestedAt;
  RefundStatus status;
  String? decidedBy;
  DateTime? decidedAt;
  String decisionNote;
  String? paidBy;
  DateTime? paidAt;
  String reference;

  /// Refund voucher number, e.g. RFD-00001, given at payout.
  String? number;

  Map<String, dynamic> toJson() => {
    'id': id,
    'paymentId': paymentId,
    'invoiceId': invoiceId,
    'patientId': patientId,
    'amount': amount,
    'method': method,
    'reason': reason,
    'requestedBy': requestedBy,
    'requestedAt': requestedAt.toIso8601String(),
    'status': status.name,
    'decidedBy': decidedBy,
    'decidedAt': decidedAt?.toIso8601String(),
    'decisionNote': decisionNote,
    'paidBy': paidBy,
    'paidAt': paidAt?.toIso8601String(),
    'reference': reference,
    'number': number,
  };

  factory Refund.fromJson(Map<String, dynamic> j) => Refund(
    id: j['id'],
    paymentId: j['paymentId'],
    invoiceId: j['invoiceId'],
    patientId: j['patientId'],
    amount: (j['amount'] as num).toDouble(),
    method: j['method'] ?? 'Cash',
    reason: j['reason'] ?? '',
    requestedBy: j['requestedBy'],
    requestedAt: DateTime.parse(j['requestedAt']),
    status: _enumByName(RefundStatus.values, j['status'], RefundStatus.pending),
    decidedBy: j['decidedBy'],
    decidedAt: _date(j['decidedAt']),
    decisionNote: j['decisionNote'] ?? '',
    paidBy: j['paidBy'],
    paidAt: _date(j['paidAt']),
    reference: j['reference'] ?? '',
    number: j['number'],
  );
}

/// Money in and out for one day, for the day-end cash report.
class DayEnd {
  DayEnd({
    required this.day,
    required this.collected,
    required this.refunded,
    required this.insurer,
    required this.payments,
    required this.refunds,
    required this.tills,
  });

  final DateTime day;

  /// Patient payments by method (before refunds).
  final Map<String, double> collected;

  /// Refunds paid out by method (positive amounts).
  final Map<String, double> refunded;

  /// Insurer settlements received.
  final double insurer;

  /// Patient payments taken (not refunds or insurer settlements).
  final List<Payment> payments;
  final List<Refund> refunds;

  /// Tills opened that day.
  final List<CashTill> tills;

  double get totalCollected => collected.values.fold(0, (a, b) => a + b);
  double get totalRefunded => refunded.values.fold(0, (a, b) => a + b);
  double get net => totalCollected - totalRefunded + insurer;
  double get netCash => (collected['Cash'] ?? 0) - (refunded['Cash'] ?? 0);
  List<CashTill> get openTills => tills.where((t) => t.isOpen).toList();

  /// Sum of over (+) / short (-) across closed tills.
  double get variance => tills.fold(0, (a, t) => a + (t.variance ?? 0));
}
