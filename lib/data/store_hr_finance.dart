part of 'hospital_store.dart';

/// Totals for one calendar month, for the finance overview.
class MonthlyFinance {
  MonthlyFinance({
    required this.month,
    required this.billedByDepartment,
    required this.collectedByMethod,
    required this.expensesByCategory,
    required this.payrollPaid,
    required this.payrollPending,
  });

  final DateTime month;

  /// Charges raised this month (by the invoice's date), per department.
  final Map<BillingDepartment, double> billedByDepartment;

  /// Payments received this month, per payment method.
  final Map<String, double> collectedByMethod;
  final Map<String, double> expensesByCategory;

  /// Net pay of this month's payslips, paid and not yet paid.
  final double payrollPaid;
  final double payrollPending;

  double get billed => billedByDepartment.values.fold(0, (a, b) => a + b);
  double get collected => collectedByMethod.values.fold(0, (a, b) => a + b);
  double get expenses => expensesByCategory.values.fold(0, (a, b) => a + b);

  /// Cash result: money received minus money spent (expenses and salaries
  /// actually paid).
  double get net => collected - expenses - payrollPaid;
}

extension HrFinanceOperations on HospitalStore {
  static bool _inMonth(DateTime d, DateTime month) =>
      d.year == month.year && d.month == month.month;

  // ---------------------------------------------------------------------------
  // Staff records
  // ---------------------------------------------------------------------------

  List<StaffUser> get activeStaff => users.where((u) => u.active).toList();

  SalaryStructure? salaryFor(String staffId) {
    for (final s in salaries) {
      if (s.staffId == staffId) return s;
    }
    return null;
  }

  Future<void> updateStaffProfile(
    String staffId, {
    required String name,
    String department = '',
    String designation = '',
    String phone = '',
    DateTime? joinedOn,
    String? specialization,
    double? consultationFee,
  }) async {
    final u = userById(staffId)!;
    u
      ..name = name.trim()
      ..department = department.trim()
      ..designation = designation.trim()
      ..phone = phone.trim()
      ..joinedOn = joinedOn;
    if (u.role == UserRole.doctor) {
      u.specialization = specialization;
      if (consultationFee != null) u.consultationFee = consultationFee;
    }
    await _commit();
  }

  /// Marks someone as having left (or rejoined). Leaving revokes their login
  /// and takes them off future payroll; their history is kept.
  Future<void> setStaffActive(String staffId, bool active) async {
    if (staffId == currentUser?.id) {
      throw HospitalException('You cannot deactivate your own account');
    }
    final u = userById(staffId)!;
    if (!active && isRemote && u.authUid != null) {
      await backend.revokeLogin(u.authUid!);
      u.authUid = null;
    }
    u.active = active;
    await _commit();
  }

  Future<void> setSalary(
    String staffId, {
    required double basic,
    double allowances = 0,
    double deductions = 0,
    String bankAccount = '',
  }) async {
    if (basic < 0 || allowances < 0 || deductions < 0) {
      throw HospitalException('Amounts cannot be negative');
    }
    final s = salaryFor(staffId) ?? SalaryStructure(staffId: staffId);
    if (!salaries.contains(s)) salaries.add(s);
    s
      ..basic = basic
      ..allowances = allowances
      ..deductions = deductions
      ..bankAccount = bankAccount.trim();
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Leave
  // ---------------------------------------------------------------------------

  List<LeaveRequest> leavesFor(String staffId) =>
      leaves.where((l) => l.staffId == staffId).toList()
        ..sort((a, b) => b.from.compareTo(a.from));

  List<LeaveRequest> get pendingLeaves =>
      leaves.where((l) => l.status == LeaveStatus.pending).toList()
        ..sort((a, b) => a.from.compareTo(b.from));

  /// Staff on approved leave today.
  List<LeaveRequest> get onLeaveToday {
    final today = DateTime.now();
    return leaves
        .where(
          (l) =>
              l.status == LeaveStatus.approved &&
              !_dayOnly(l.from).isAfter(today) &&
              !_dayOnly(l.to).isBefore(_dayOnly(today)),
        )
        .toList();
  }

  Future<LeaveRequest> requestLeave({
    required String staffId,
    required LeaveType type,
    required DateTime from,
    required DateTime to,
    String reason = '',
  }) async {
    if (to.isBefore(from)) {
      throw HospitalException('The end date is before the start date');
    }
    final l = LeaveRequest(
      id: newId('LV'),
      staffId: staffId,
      type: type,
      from: _dayOnly(from),
      to: _dayOnly(to),
      reason: reason.trim(),
      requestedAt: DateTime.now(),
    );
    leaves.add(l);
    _notify(
      title: 'Leave request',
      body:
          '${userName(staffId)} requests ${l.days} day(s) of '
          '${type.label.toLowerCase()} leave from ${_fmt(l.from)}',
      role: UserRole.admin,
    );
    await _commit();
    return l;
  }

  Future<void> decideLeave(String leaveId, {required bool approve}) async {
    final l = leaves.firstWhere((l) => l.id == leaveId);
    if (l.status != LeaveStatus.pending) {
      throw HospitalException('This request was already decided');
    }
    l
      ..status = approve ? LeaveStatus.approved : LeaveStatus.rejected
      ..decidedBy = currentUser?.id;
    final clashes = approve ? appointmentsDuring(l) : const <Appointment>[];
    if (clashes.isNotEmpty) {
      _notify(
        title: 'Appointments to rebook',
        body:
            '${userName(l.staffId)} is on leave ${_fmt(l.from)} – ${_fmt(l.to)}; '
            '${clashes.length} booked appointment(s) need a new time',
        role: UserRole.receptionist,
      );
    }
    _notify(
      title: approve ? 'Leave approved' : 'Leave declined',
      body: '${l.type.label} leave ${_fmt(l.from)} – ${_fmt(l.to)}',
      userId: l.staffId,
    );
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Payroll
  // ---------------------------------------------------------------------------

  List<Payslip> payslipsFor(DateTime month) =>
      payslips.where((p) => _inMonth(p.month, month)).toList()
        ..sort((a, b) => userName(a.staffId).compareTo(userName(b.staffId)));

  /// Creates draft payslips for [month] for every active staff member with a
  /// salary who doesn't have one yet. Approved unpaid leave in the month is
  /// deducted pro rata from the basic salary. Returns how many were created.
  Future<int> generatePayroll(DateTime month) async {
    final start = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final existing = payslipsFor(start).map((p) => p.staffId).toSet();
    var created = 0;
    for (final u in activeStaff) {
      final s = salaryFor(u.id);
      if (s == null || s.basic <= 0 || existing.contains(u.id)) continue;
      final unpaid = leaves
          .where(
            (l) =>
                l.staffId == u.id &&
                l.status == LeaveStatus.approved &&
                l.type == LeaveType.unpaid,
          )
          .fold(0, (sum, l) => sum + l.daysIn(start));
      payslips.add(
        Payslip(
          id: newId('PAY'),
          staffId: u.id,
          month: start,
          basic: s.basic,
          allowances: s.allowances,
          deductions: s.deductions,
          unpaidLeaveDays: unpaid,
          leaveDeduction: _round2(s.basic / daysInMonth * unpaid),
        ),
      );
      created++;
    }
    if (created == 0) {
      throw HospitalException(
        'Nothing to generate: every active staff member with a salary '
        'already has a payslip for this month',
      );
    }
    await _commit();
    return created;
  }

  Future<void> markPayslipPaid(
    String payslipId, {
    String method = 'Bank transfer',
  }) async {
    final p = payslips.firstWhere((p) => p.id == payslipId);
    if (p.status == PayslipStatus.paid) {
      throw HospitalException('Already paid');
    }
    p
      ..status = PayslipStatus.paid
      ..paidAt = DateTime.now()
      ..paymentMethod = method;
    await _commit();
  }

  /// Removes an unpaid payslip, e.g. to regenerate it after a salary change.
  Future<void> deletePayslip(String payslipId) async {
    final p = payslips.firstWhere((p) => p.id == payslipId);
    if (p.status == PayslipStatus.paid) {
      throw HospitalException('Paid payslips cannot be deleted');
    }
    payslips.remove(p);
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Expenses
  // ---------------------------------------------------------------------------

  List<Expense> expensesIn(DateTime month) =>
      expenses.where((e) => _inMonth(e.date, month)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  Future<Expense> addExpense({
    required DateTime date,
    required String category,
    required String description,
    required double amount,
    String vendor = '',
    String paymentMethod = 'Cash',
  }) async {
    if (amount <= 0) throw HospitalException('Amount must be positive');
    if (description.trim().isEmpty) {
      throw HospitalException('Describe the expense');
    }
    final e = Expense(
      id: newId('EXP'),
      date: date,
      category: category,
      description: description.trim(),
      amount: amount,
      vendor: vendor.trim(),
      paymentMethod: paymentMethod,
      recordedBy: currentUser?.id,
    );
    expenses.add(e);
    await _commit();
    return e;
  }

  Future<void> deleteExpense(String expenseId) async {
    expenses.removeWhere((e) => e.id == expenseId);
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Reports
  // ---------------------------------------------------------------------------

  List<Payment> paymentsFor(String invoiceId) =>
      payments.where((p) => p.invoiceId == invoiceId).toList()
        ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

  MonthlyFinance financeFor(DateTime month) {
    final billed = {for (final d in BillingDepartment.values) d: 0.0};
    for (final inv in invoices.where((i) => _inMonth(i.createdAt, month))) {
      for (final l in inv.lines) {
        billed[l.department] = billed[l.department]! + l.total;
      }
    }
    final collected = <String, double>{};
    for (final p in payments.where((p) => _inMonth(p.receivedAt, month))) {
      collected[p.method] = (collected[p.method] ?? 0) + p.amount;
    }
    final spent = <String, double>{};
    for (final e in expensesIn(month)) {
      spent[e.category] = (spent[e.category] ?? 0) + e.amount;
    }
    final slips = payslipsFor(month);
    double sum(Iterable<Payslip> ps) => ps.fold(0, (a, p) => a + p.net);
    return MonthlyFinance(
      month: DateTime(month.year, month.month),
      billedByDepartment: billed,
      collectedByMethod: collected,
      expensesByCategory: spent,
      payrollPaid: sum(slips.where((p) => p.status == PayslipStatus.paid)),
      payrollPending: sum(slips.where((p) => p.status == PayslipStatus.draft)),
    );
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  static String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
