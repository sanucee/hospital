import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../print/documents.dart';
import '../../print/print_button.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';
import 'insurance_screens.dart';

/// Invoices, and (for front office and accounts) insurance claims and
/// insurers.
class BillingScreen extends StatelessWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final insurance = {
      UserRole.admin,
      UserRole.receptionist,
      UserRole.accountant,
    }.contains(store.currentUser!.role);
    if (!insurance) return const _InvoiceList();
    final pending = store.claims
        .where(
          (c) =>
              c.status == ClaimStatus.draft ||
              c.status == ClaimStatus.submitted ||
              c.status == ClaimStatus.approved,
        )
        .length;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              const Tab(text: 'Invoices'),
              Tab(
                text:
                    'Insurance claims${pending > 0 ? ' ($pending open)' : ''}',
              ),
              const Tab(text: 'Insurers'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [_InvoiceList(), ClaimsTab(), InsurersTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceList extends StatefulWidget {
  const _InvoiceList();

  @override
  State<_InvoiceList> createState() => _InvoiceListState();
}

class _InvoiceListState extends State<_InvoiceList> {
  bool _unpaidOnly = true;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final q = _query.toLowerCase();
    final list =
        store.invoices
            .where(
              (i) =>
                  i.lines.isNotEmpty &&
                  (!_unpaidOnly || !i.isPaid) &&
                  (q.isEmpty ||
                      i.number.toLowerCase().contains(q) ||
                      store.patientName(i.patientId).toLowerCase().contains(q)),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Invoice number or patient',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Unpaid only'),
                selected: _unpaidOnly,
                onSelected: (v) => setState(() => _unpaidOnly = v),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatTile(
                label: 'Outstanding',
                value: money(store.outstandingBalance),
                icon: Icons.pending_actions,
                color: Colors.red,
              ),
              StatTile(
                label: 'Collected today',
                value: money(store.revenueOn(DateTime.now())),
                icon: Icons.payments,
                color: Colors.green,
              ),
              if (store.dueFromInsurers > 0)
                StatTile(
                  label: 'Due from insurers',
                  value: money(store.dueFromInsurers),
                  icon: Icons.health_and_safety,
                  color: Colors.indigo,
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState('No invoices', icon: Icons.receipt)
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final inv in list)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            inv.insurerId == null
                                ? Icons.receipt_long
                                : Icons.health_and_safety,
                          ),
                          title: Text(
                            '${inv.number} · ${store.patientName(inv.patientId)}'
                            '${inv.insurerId == null ? '' : ' · ${store.insurerById(inv.insurerId)?.name ?? 'Insured'}'}',
                          ),
                          subtitle: Text(
                            [
                              fmtDate(inv.createdAt),
                              for (final d in BillingDepartment.values)
                                if (inv.totalFor(d) > 0)
                                  '${d.label} ${money(inv.totalFor(d))}',
                            ].join(' · '),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                money(inv.balance),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              StatusChip.invoice(inv),
                            ],
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InvoiceScreen(invoiceId: inv.id),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A single consolidated bill with charges from every department.
class InvoiceScreen extends StatelessWidget {
  const InvoiceScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final inv = store.invoices.firstWhere((i) => i.id == invoiceId);
    final p = store.patientById(inv.patientId);
    final role = store.currentUser!.role;
    final canCollect = {
      UserRole.admin,
      UserRole.receptionist,
      UserRole.pharmacist,
      UserRole.accountant,
    }.contains(role);
    final doctorId = inv.consultationId != null
        ? store.consultationById(inv.consultationId!)?.doctorId
        : inv.admissionId != null
        ? store.admissionById(inv.admissionId!)?.doctorId
        : inv.surgeryId != null
        ? store.surgeryById(inv.surgeryId!)?.surgeonId
        : null;
    final paymentsMade = store.paymentsFor(inv.id);

    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice ${inv.number}'),
        actions: [
          PrintButton(
            tooltip: inv.isPaid ? 'Print receipt' : 'Print invoice',
            name: '${inv.number}.pdf',
            document: () => invoicePdf(store, inv),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: p?.name ?? 'Unknown patient',
            icon: Icons.person,
            trailing: StatusChip.invoice(inv),
            child: Column(
              children: [
                InfoRow('MRN', p?.mrn ?? ''),
                InfoRow('Date', fmtDateTime(inv.createdAt)),
                InfoRow(
                  'Visit',
                  inv.admissionId != null
                      ? 'Inpatient admission'
                      : inv.surgeryId != null
                      ? 'Day-case surgery'
                      : 'Outpatient consultation',
                ),
                InfoRow(
                  'Doctor',
                  doctorId == null ? '' : store.userName(doctorId),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: p == null
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PatientDetailScreen(patientId: p.id),
                            ),
                          ),
                    child: const Text('Open medical record'),
                  ),
                ),
              ],
            ),
          ),
          for (final dept in BillingDepartment.values)
            if (inv.lines.any((l) => l.department == dept))
              SectionCard(
                title: dept.label,
                icon: switch (dept) {
                  BillingDepartment.consultation => Icons.medical_services,
                  BillingDepartment.laboratory => Icons.biotech,
                  BillingDepartment.pharmacy => Icons.local_pharmacy,
                  BillingDepartment.room => Icons.bed,
                  BillingDepartment.surgery => Icons.healing,
                  BillingDepartment.emergency => Icons.emergency,
                  BillingDepartment.radiology => Icons.monitor_heart,
                  BillingDepartment.bloodBank => Icons.bloodtype,
                  BillingDepartment.supplies => Icons.inventory_2,
                },
                trailing: Text(
                  money(inv.totalFor(dept)),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                child: Column(
                  children: [
                    for (final l in inv.lines.where(
                      (l) => l.department == dept,
                    ))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: Text(l.description)),
                            Text('${l.quantity} × ${money(l.unitPrice)}'),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 80,
                              child: Text(
                                money(l.total),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          if (role != UserRole.pharmacist) InvoiceInsuranceCard(invoice: inv),
          SectionCard(
            title: 'Summary',
            icon: Icons.calculate,
            child: Column(
              children: [
                _sumRow('Subtotal', inv.subtotal),
                _sumRow('Discount', -inv.discount),
                _sumRow('Total', inv.total, bold: true),
                if (inv.insurerId != null) ...[
                  _sumRow(
                    inv.insurerApproved == null
                        ? 'Insurance share (estimated)'
                        : 'Insurance share (approved)',
                    inv.insurerCovered,
                  ),
                  _sumRow('Patient share', inv.patientDue),
                  _sumRow('Paid by insurer', inv.insurerPaid),
                ],
                _sumRow(
                  inv.insurerId == null ? 'Paid' : 'Paid by patient',
                  inv.amountPaid,
                ),
                if (inv.insurerId != null)
                  _sumRow('Patient balance', inv.patientBalance, bold: true),
                _sumRow(
                  inv.insurerId == null ? 'Balance due' : 'Total outstanding',
                  inv.balance,
                  bold: inv.insurerId == null,
                ),
                if (inv.admissionId != null &&
                    (store.admissionById(inv.admissionId!)?.isActive ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Patient is still admitted: room charges so far '
                      '(${money(store.admissionById(inv.admissionId!)!.roomCharges(DateTime.now()))}) '
                      'are added at discharge.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (paymentsMade.isNotEmpty) ...[
                  const Divider(),
                  for (final pm in paymentsMade)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            pm.isRefund ? Icons.undo : Icons.check_circle,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${fmtDateTime(pm.receivedAt)} · ${pm.method}'
                              '${pm.isRefund ? ' refund ${pm.receiptNo ?? ''}' : ''}'
                              '${pm.receivedBy == null ? '' : ' · ${store.userName(pm.receivedBy!)}'}',
                            ),
                          ),
                          Text(money(pm.amount)),
                          if (!pm.isRefund)
                            PrintButton(
                              tooltip: 'Print receipt',
                              name: 'receipt-${inv.number}.pdf',
                              document: () => paymentReceiptPdf(store, pm),
                            )
                          else if (store.refundById(pm.refundId!) case final r?)
                            PrintButton(
                              tooltip: 'Print refund voucher',
                              name: '${pm.receiptNo}.pdf',
                              document: () => refundVoucherPdf(store, r),
                            ),
                        ],
                      ),
                    ),
                ],
                if (canCollect && inv.patientBalance > 0.004) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.payments),
                        label: const Text('Record payment'),
                        onPressed: () => _amountDialog(
                          context,
                          title: 'Record payment',
                          initial: inv.patientBalance,
                          withMethod: true,
                          onSubmit: (v, method) =>
                              store.recordPayment(inv.id, v, method: method),
                        ),
                      ),
                      if (role != UserRole.pharmacist)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.discount),
                          label: const Text('Discount'),
                          onPressed: () => _amountDialog(
                            context,
                            title: 'Apply discount',
                            initial: inv.discount,
                            onSubmit: (v, _) => store.applyDiscount(inv.id, v),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sumRow(String label, double v, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(money(v), style: style),
        ],
      ),
    );
  }

  Future<void> _amountDialog(
    BuildContext context, {
    required String title,
    required double initial,
    bool withMethod = false,
    required Future<void> Function(double amount, String method) onSubmit,
  }) async {
    final c = TextEditingController(text: initial.toStringAsFixed(2));
    var method = kPaymentMethods.first;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            if (withMethod) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Method'),
                items: [
                  for (final m in kPaymentMethods)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) => method = v!,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final ok = await guarded(ctx, () async {
                final v = double.tryParse(c.text);
                if (v == null) throw HospitalException('Enter a number');
                await onSubmit(v, method);
              });
              if (ok) nav.pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
