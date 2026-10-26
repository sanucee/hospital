part of 'hospital_store.dart';

/// Over-the-counter payments: cashiers open a till with a float, take
/// payments against a patient's bills (several at once, with change for
/// cash), print a receipt, and count the cash when they close.
extension CounterOperations on HospitalStore {
  static const cashierRoles = {
    UserRole.admin,
    UserRole.receptionist,
    UserRole.pharmacist,
    UserRole.accountant,
  };

  /// Methods taken at the counter; insurers pay through claims.
  static List<String> get counterMethods =>
      kPaymentMethods.where((m) => m != 'Insurance').toList();

  // ---------------------------------------------------------------------------
  // Tills
  // ---------------------------------------------------------------------------

  /// The signed-in cashier's open till, if any.
  CashTill? get myOpenTill {
    final me = currentUser?.id;
    if (me == null) return null;
    return _find(tills, (t) => t.cashierId == me && t.isOpen);
  }

  CashTill? tillById(String id) => _find(tills, (t) => t.id == id);

  Invoice? invoiceById(String id) => _find(invoices, (i) => i.id == id);

  List<CashTill> get tillsNewestFirst =>
      [...tills]..sort((a, b) => b.openedAt.compareTo(a.openedAt));

  Future<CashTill> openTill({double openingFloat = 0}) async {
    final me = currentUser;
    if (me == null || !cashierRoles.contains(me.role)) {
      throw HospitalException('Only cashiers can open a till');
    }
    if (myOpenTill != null) {
      throw HospitalException('Your till is already open');
    }
    if (openingFloat < 0) {
      throw HospitalException('The float cannot be negative');
    }
    final t = CashTill(
      id: newId('TIL'),
      cashierId: me.id,
      openedAt: DateTime.now(),
      openingFloat: openingFloat,
    );
    tills.add(t);
    await _commit();
    return t;
  }

  List<Payment> paymentsInTill(String tillId) =>
      payments.where((p) => p.tillId == tillId).toList()
        ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

  /// Takings by payment method.
  Map<String, double> tillTotals(String tillId) {
    final totals = <String, double>{};
    for (final p in paymentsInTill(tillId)) {
      totals[p.method] = (totals[p.method] ?? 0) + p.amount;
    }
    return totals;
  }

  /// What should be in the drawer: the float plus cash taken.
  double expectedCash(CashTill t) =>
      t.openingFloat + (tillTotals(t.id)['Cash'] ?? 0);

  /// Counts the drawer and closes the till. A cashier closes their own;
  /// administrators and accounts can close anyone's (e.g. a forgotten one).
  Future<void> closeTill(
    String tillId, {
    required double countedCash,
    String notes = '',
  }) async {
    final t = tillById(tillId)!;
    final me = currentUser;
    final manager =
        me?.role == UserRole.admin || me?.role == UserRole.accountant;
    if (me?.id != t.cashierId && !manager) {
      throw HospitalException('You can only close your own till');
    }
    if (!t.isOpen) throw HospitalException('This till is already closed');
    if (countedCash < 0) throw HospitalException('Enter the cash counted');
    t
      ..expectedCash = expectedCash(t)
      ..countedCash = countedCash
      ..closedAt = DateTime.now()
      ..notes = notes.trim();
    final v = t.variance!;
    if (v.abs() > 0.004) {
      _notify(
        title: v < 0 ? 'Till short' : 'Till over',
        body:
            '${userName(t.cashierId)}\'s till closed '
            '${v < 0 ? 'short' : 'over'} by ${v.abs().toStringAsFixed(2)}'
            '${t.notes.isEmpty ? '' : ': ${t.notes}'}',
        role: UserRole.accountant,
      );
    }
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Taking payment
  // ---------------------------------------------------------------------------

  /// A patient's bills with something left for them to pay, oldest first.
  List<Invoice> outstandingFor(String patientId) =>
      invoices
          .where((i) => i.patientId == patientId && i.patientBalance > 0.004)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Takes one payment over the counter for [invoiceIds], applying [amount]
  /// to the oldest bill first. For cash, [tendered] is what the patient
  /// handed over and the change is worked out.
  Future<CounterReceipt> takeCounterPayment({
    required String patientId,
    required List<String> invoiceIds,
    required double amount,
    required String method,
    double? tendered,
    String reference = '',
  }) async {
    final till = myOpenTill;
    if (till == null) {
      throw HospitalException('Open your till before taking payments');
    }
    if (!counterMethods.contains(method)) {
      throw HospitalException('$method is not taken at the counter');
    }
    final bills = outstandingFor(patientId)
        .where((i) => invoiceIds.contains(i.id))
        .toList();
    if (bills.isEmpty) throw HospitalException('Select a bill to pay');
    final due = bills.fold<double>(0, (s, i) => s + i.patientBalance);
    if (amount <= 0) throw HospitalException('Enter the amount');
    if (amount > due + 0.004) {
      throw HospitalException(
        'That is more than the ${due.toStringAsFixed(2)} due',
      );
    }
    final cash = method == 'Cash';
    if (cash && (tendered ?? amount) < amount - 0.004) {
      throw HospitalException('The cash handed over is less than the amount');
    }
    if (!cash && reference.trim().isEmpty) {
      throw HospitalException(
        'Enter the ${method.toLowerCase()} reference from the slip or message',
      );
    }

    final n = await _next('receipt');
    final receiptNo = n == null
        ? 'RCT-T${_offlineNumber()}'
        : 'RCT-${n.toString().padLeft(5, '0')}';
    final now = DateTime.now();
    var left = amount;
    final taken = <Payment>[];
    for (final inv in bills) {
      // Another device may have taken a payment meanwhile.
      final share = double.parse(
        min(left, inv.patientBalance).toStringAsFixed(2),
      );
      if (share <= 0.004) continue;
      inv.amountPaid += share;
      left -= share;
      final p = Payment(
        id: newId('PMT'),
        invoiceId: inv.id,
        patientId: patientId,
        amount: share,
        method: method,
        receivedAt: now,
        receivedBy: currentUser?.id,
        reference: reference.trim(),
        receiptNo: receiptNo,
        tillId: till.id,
      );
      payments.add(p);
      taken.add(p);
      if (left <= 0.004) break;
    }
    if (taken.isEmpty) {
      throw HospitalException('These bills have just been paid');
    }
    await _commit();
    final paid = taken.fold<double>(0, (s, p) => s + p.amount);
    return CounterReceipt(
      receiptNo: receiptNo,
      payments: taken,
      tendered: cash ? (tendered ?? paid) : null,
      change: cash ? max(0, (tendered ?? paid) - paid) : 0,
    );
  }

  /// The payments on one counter receipt.
  List<Payment> paymentsOnReceipt(String receiptNo) =>
      payments.where((p) => p.receiptNo == receiptNo).toList();
}
