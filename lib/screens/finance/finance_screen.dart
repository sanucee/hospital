import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

final _monthFmt = DateFormat('MMMM yyyy');

/// Accounts: monthly income and spending, expenses, payroll and salaries.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1),
              ),
              SizedBox(
                width: 160,
                child: Text(
                  _monthFmt.format(_month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shift(1),
              ),
            ],
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Expenses'),
              Tab(text: 'Payroll'),
              Tab(text: 'Salaries'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _Overview(month: _month),
                _Expenses(month: _month),
                _Payroll(month: _month),
                const _Salaries(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final f = store.financeFor(month);
    Widget row(String label, double v, {bool bold = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                money(v),
                style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : null,
                  color: color,
                ),
              ),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatTile(
              label: 'Billed',
              value: money(f.billed),
              icon: Icons.receipt_long,
              color: Colors.indigo,
            ),
            StatTile(
              label: 'Collected',
              value: money(f.collected),
              icon: Icons.payments,
              color: Colors.green,
            ),
            StatTile(
              label: 'Expenses',
              value: money(f.expenses),
              icon: Icons.shopping_cart,
              color: Colors.deepOrange,
            ),
            StatTile(
              label: 'Salaries paid',
              value: money(f.payrollPaid),
              icon: Icons.badge,
              color: Colors.brown,
            ),
            StatTile(
              label: 'Net cash',
              value: money(f.net),
              icon: f.net >= 0 ? Icons.trending_up : Icons.trending_down,
              color: f.net >= 0 ? Colors.teal : Colors.red,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Billed by department',
          icon: Icons.account_tree,
          child: Column(
            children: [
              for (final d in BillingDepartment.values)
                row(d.label, f.billedByDepartment[d] ?? 0),
              const Divider(),
              row('Total billed', f.billed, bold: true),
              row('Outstanding on all bills', store.outstandingBalance),
            ],
          ),
        ),
        SectionCard(
          title: 'Collected by method',
          icon: Icons.point_of_sale,
          child: f.collectedByMethod.isEmpty
              ? const Text('No payments received this month.')
              : Column(
                  children: [
                    for (final e in f.collectedByMethod.entries)
                      row(e.key, e.value),
                  ],
                ),
        ),
        SectionCard(
          title: 'Cash flow',
          icon: Icons.calculate,
          child: Column(
            children: [
              row('Collected', f.collected),
              for (final e in f.expensesByCategory.entries)
                row('− ${e.key}', -e.value),
              row('− Salaries paid', -f.payrollPaid),
              const Divider(),
              row(
                'Net',
                f.net,
                bold: true,
                color: f.net >= 0 ? Colors.green : Colors.red,
              ),
              if (f.payrollPending > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${money(f.payrollPending)} of payroll for this month is '
                    'not yet paid.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Expenses extends StatelessWidget {
  const _Expenses({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final list = store.expensesIn(month);
    final total = list.fold<double>(0, (s, e) => s + e.amount);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: list.isEmpty
          ? const EmptyState('No expenses this month', icon: Icons.receipt)
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Total ${money(total)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final e in list)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt),
                      title: Text(e.description),
                      subtitle: Text(
                        [
                          fmtDate(e.date),
                          e.category,
                          if (e.vendor.isNotEmpty) e.vendor,
                          e.paymentMethod,
                        ].join(' · '),
                      ),
                      trailing: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            money(e.amount),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => guarded(
                              context,
                              () => store.deleteExpense(e.id),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final store = context.read<HospitalStore>();
    final description = TextEditingController();
    final amount = TextEditingController();
    final vendor = TextEditingController();
    var category = kExpenseCategories.first;
    var method = 'Bank transfer';
    final now = DateTime.now();
    var date = month.year == now.year && month.month == now.month
        ? now
        : DateTime(month.year, month.month, 1);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add expense'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final c in kExpenseCategories)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => category = v!,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: vendor,
                    decoration: const InputDecoration(
                      labelText: 'Vendor / payee',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(labelText: 'Paid by'),
                    items: [
                      for (final m in kPaymentMethods)
                        if (m != 'Insurance')
                          DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: (v) => method = v!,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(fmtDate(date)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => date = d);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final nav = Navigator.of(ctx);
                if (await guarded(
                  ctx,
                  () => store.addExpense(
                    date: date,
                    category: category,
                    description: description.text,
                    amount: double.tryParse(amount.text) ?? 0,
                    vendor: vendor.text,
                    paymentMethod: method,
                  ),
                  success: 'Expense recorded',
                )) {
                  nav.pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Payroll extends StatelessWidget {
  const _Payroll({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final slips = store.payslipsFor(month);
    final total = slips.fold<double>(0, (s, p) => s + p.net);
    final unpaid = slips.where((p) => p.status == PayslipStatus.draft).length;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.playlist_add),
              label: Text('Generate payroll for ${_monthFmt.format(month)}'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final n = await store.generatePayroll(month);
                  messenger.showSnackBar(
                    SnackBar(content: Text('$n payslip(s) created')),
                  );
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('$e')));
                }
              },
            ),
            Text(
              '${slips.length} payslip(s) · total ${money(total)}'
              '${unpaid > 0 ? ' · $unpaid unpaid' : ''}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (slips.isEmpty)
          const EmptyState(
            'No payslips for this month yet. Set salaries, then generate '
            'payroll.',
            icon: Icons.badge,
          ),
        for (final p in slips)
          Card(
            child: ExpansionTile(
              leading: Icon(
                p.status == PayslipStatus.paid
                    ? Icons.check_circle
                    : Icons.pending,
                color: p.status == PayslipStatus.paid
                    ? Colors.green
                    : Colors.orange,
              ),
              title: Text(store.userName(p.staffId)),
              subtitle: Text(
                '${store.userById(p.staffId)?.role.label ?? ''} · net '
                '${money(p.net)}'
                '${p.status == PayslipStatus.paid ? ' · paid ${fmtDate(p.paidAt)}' : ''}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                InfoRow('Basic', money(p.basic)),
                InfoRow('Allowances', money(p.allowances)),
                InfoRow('Deductions', '− ${money(p.deductions)}'),
                if (p.unpaidLeaveDays > 0)
                  InfoRow(
                    'Unpaid leave',
                    '${p.unpaidLeaveDays} day(s): − ${money(p.leaveDeduction)}',
                  ),
                InfoRow('Net pay', money(p.net)),
                if (p.status == PayslipStatus.paid)
                  InfoRow('Paid by', p.paymentMethod)
                else
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () =>
                              guarded(context, () => store.deletePayslip(p.id)),
                          child: const Text('Delete'),
                        ),
                        FilledButton(
                          onPressed: () => guarded(
                            context,
                            () => store.markPayslipPaid(p.id),
                            success: 'Marked as paid',
                          ),
                          child: const Text('Mark paid'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Salaries extends StatelessWidget {
  const _Salaries();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final staff = [...store.activeStaff]
      ..sort((a, b) => a.role.index.compareTo(b.role.index));
    final total = staff.fold<double>(
      0,
      (s, u) => s + (store.salaryFor(u.id)?.net ?? 0),
    );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Monthly net payroll ${money(total)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final u in staff)
          Builder(
            builder: (context) {
              final s = store.salaryFor(u.id);
              return ListTile(
                leading: CircleAvatar(child: Text(u.name[0])),
                title: Text(u.name),
                subtitle: Text(
                  s == null
                      ? '${u.role.label} · no salary set'
                      : '${u.role.label} · basic ${money(s.basic)} + '
                            '${money(s.allowances)} − ${money(s.deductions)}',
                ),
                trailing: Text(
                  s == null ? '—' : money(s.net),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () => _edit(context, u, s),
              );
            },
          ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    StaffUser u,
    SalaryStructure? s,
  ) async {
    final store = context.read<HospitalStore>();
    String text(double? v) => v == null ? '' : v.toStringAsFixed(2);
    final basic = TextEditingController(text: text(s?.basic));
    final allow = TextEditingController(text: text(s?.allowances ?? 0));
    final deduct = TextEditingController(text: text(s?.deductions ?? 0));
    final bank = TextEditingController(text: s?.bankAccount);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Salary: ${u.name}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (c, label) in [
                (basic, 'Basic (monthly)'),
                (allow, 'Allowances (monthly)'),
                (deduct, 'Deductions: tax, pension… (monthly)'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: c,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: label),
                  ),
                ),
              TextField(
                controller: bank,
                decoration: const InputDecoration(labelText: 'Bank account'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              if (await guarded(ctx, () async {
                final b = double.tryParse(basic.text);
                if (b == null) {
                  throw HospitalException('Enter the basic salary');
                }
                await store.setSalary(
                  u.id,
                  basic: b,
                  allowances: double.tryParse(allow.text) ?? 0,
                  deductions: double.tryParse(deduct.text) ?? 0,
                  bankAccount: bank.text,
                );
              }, success: 'Salary saved')) {
                nav.pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
