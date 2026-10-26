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

  // ---------------------------------------------------------------------------
  // Refunds
  // ---------------------------------------------------------------------------

  bool get _isManager =>
      currentUser?.role == UserRole.admin ||
      currentUser?.role == UserRole.accountant;

  Refund? refundById(String id) => _find(refunds, (r) => r.id == id);

  List<Refund> get refundsNewestFirst =>
      [...refunds]..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

  /// How much of [p] can still be refunded: what was paid less refunds
  /// already requested, approved or paid.
  double refundableOn(Payment p) {
    if (p.amount <= 0 || p.isRefund || p.fromInsurer) return 0;
    final taken = refunds
        .where((r) => r.paymentId == p.id && r.status != RefundStatus.rejected)
        .fold<double>(0, (s, r) => s + r.amount);
    return max(0, double.parse((p.amount - taken).toStringAsFixed(2)));
  }

  /// A patient's payments that can still be (partly) refunded, newest first.
  List<Payment> refundablePayments(String patientId) =>
      payments
          .where((p) => p.patientId == patientId && refundableOn(p) > 0.004)
          .toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

  /// Asks for money back against [paymentId]. Administrators and accounts
  /// approve their own requests; anyone else's wait for them.
  Future<Refund> requestRefund(
    String paymentId, {
    required double amount,
    required String reason,
    String? method,
  }) async {
    final me = currentUser;
    if (me == null || !cashierRoles.contains(me.role)) {
      throw HospitalException('Only cashiers can request refunds');
    }
    final p = _find(payments, (p) => p.id == paymentId);
    if (p == null) throw HospitalException('Payment not found');
    final max = refundableOn(p);
    if (amount <= 0) throw HospitalException('Enter the amount to refund');
    if (amount > max + 0.004) {
      throw HospitalException(
        'At most ${max.toStringAsFixed(2)} of this payment can be refunded',
      );
    }
    if (reason.trim().length < 3) {
      throw HospitalException('Give the reason for the refund');
    }
    final how = method ?? p.method;
    if (!counterMethods.contains(how)) {
      throw HospitalException('Refunds can\'t be paid by $how');
    }
    final now = DateTime.now();
    final r = Refund(
      id: newId('RFD'),
      paymentId: p.id,
      invoiceId: p.invoiceId,
      patientId: p.patientId,
      amount: double.parse(amount.toStringAsFixed(2)),
      method: how,
      reason: reason.trim(),
      requestedBy: me.id,
      requestedAt: now,
    );
    if (_isManager) {
      r
        ..status = RefundStatus.approved
        ..decidedBy = me.id
        ..decidedAt = now;
    } else {
      _notify(
        title: 'Refund to approve',
        body:
            '${me.name} asks to refund ${r.amount.toStringAsFixed(2)} to '
            '${patientName(r.patientId)}: ${r.reason}',
        role: UserRole.accountant,
        patientId: r.patientId,
      );
    }
    refunds.add(r);
    await _commit();
    return r;
  }

  /// Administrators and accounts approve or reject a refund request. An
  /// accountant can't approve their own.
  Future<void> decideRefund(
    String refundId, {
    required bool approve,
    String note = '',
  }) async {
    final me = currentUser;
    if (!_isManager) {
      throw HospitalException(
        'Only administrators and accounts approve refunds',
      );
    }
    final r = refundById(refundId)!;
    if (r.status != RefundStatus.pending) {
      throw HospitalException('This refund is already ${r.status.label}');
    }
    if (approve && r.requestedBy == me!.id && me.role != UserRole.admin) {
      throw HospitalException('Someone else must approve your own refund');
    }
    r
      ..status = approve ? RefundStatus.approved : RefundStatus.rejected
      ..decidedBy = me!.id
      ..decidedAt = DateTime.now()
      ..decisionNote = note.trim();
    _notify(
      title: approve ? 'Refund approved' : 'Refund rejected',
      body:
          '${r.amount.toStringAsFixed(2)} to ${patientName(r.patientId)}'
          '${r.decisionNote.isEmpty ? '' : ': ${r.decisionNote}'}',
      userId: r.requestedBy,
      patientId: r.patientId,
    );
    await _commit();
  }

  /// Pays out an approved refund. Cash comes out of the cashier's open
  /// till; other methods need the reversal or transfer reference.
  Future<Refund> payRefund(String refundId, {String reference = ''}) async {
    final me = currentUser;
    if (me == null || !cashierRoles.contains(me.role)) {
      throw HospitalException('Only cashiers pay out refunds');
    }
    final r = refundById(refundId)!;
    if (r.status != RefundStatus.approved) {
      throw HospitalException(
        r.status == RefundStatus.pending
            ? 'This refund has not been approved yet'
            : 'This refund is ${r.status.label.toLowerCase()}',
      );
    }
    final till = myOpenTill;
    final cash = r.method == 'Cash';
    if (cash && till == null) {
      throw HospitalException('Open your till to pay out cash');
    }
    if (cash && expectedCash(till!) < r.amount - 0.004) {
      throw HospitalException('There is not enough cash in your till');
    }
    if (!cash && reference.trim().isEmpty) {
      throw HospitalException('Enter the ${r.method.toLowerCase()} reference');
    }
    final n = await _next('refund');
    final number = n == null
        ? 'RFD-T${_offlineNumber()}'
        : 'RFD-${n.toString().padLeft(5, '0')}';
    final now = DateTime.now();
    final inv = invoiceById(r.invoiceId);
    if (inv != null) inv.amountPaid -= r.amount;
    payments.add(
      Payment(
        id: newId('PMT'),
        invoiceId: r.invoiceId,
        patientId: r.patientId,
        amount: -r.amount,
        method: r.method,
        receivedAt: now,
        receivedBy: me.id,
        reference: reference.trim(),
        receiptNo: number,
        tillId: till?.id,
        refundId: r.id,
      ),
    );
    r
      ..status = RefundStatus.paid
      ..paidBy = me.id
      ..paidAt = now
      ..reference = reference.trim()
      ..number = number;
    await _commit();
    return r;
  }

  /// Refunds paid out of a till, by method (positive amounts).
  Map<String, double> tillRefunds(String tillId) {
    final totals = <String, double>{};
    for (final p in paymentsInTill(tillId)) {
      if (!p.isRefund) continue;
      totals[p.method] = (totals[p.method] ?? 0) - p.amount;
    }
    return totals;
  }

  // ---------------------------------------------------------------------------
  // Day end
  // ---------------------------------------------------------------------------

  /// Everything taken and paid back on [day], with that day's tills.
  DayEnd dayEnd(DateTime day) {
    final collected = <String, double>{};
    final refunded = <String, double>{};
    var insurer = 0.0;
    final taken = <Payment>[];
    for (final p in payments) {
      if (!HospitalStore._sameDay(p.receivedAt, day)) continue;
      if (p.fromInsurer) {
        insurer += p.amount;
      } else if (p.isRefund) {
        refunded[p.method] = (refunded[p.method] ?? 0) - p.amount;
      } else {
        collected[p.method] = (collected[p.method] ?? 0) + p.amount;
        taken.add(p);
      }
    }
    taken.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    return DayEnd(
      day: _dayOnly(day),
      collected: collected,
      refunded: refunded,
      insurer: insurer,
      payments: taken,
      refunds: refunds
          .where(
            (r) =>
                r.status == RefundStatus.paid &&
                HospitalStore._sameDay(r.paidAt!, day),
          )
          .toList(),
      tills:
          tills.where((t) => HospitalStore._sameDay(t.openedAt, day)).toList()
            ..sort((a, b) => a.openedAt.compareTo(b.openedAt)),
    );
  }
}
