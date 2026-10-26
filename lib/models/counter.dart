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
