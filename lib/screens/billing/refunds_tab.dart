import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../print/documents.dart';
import '../../print/print_button.dart';
import '../../widgets/common.dart';

/// Refunds: requested at the counter, approved by administration or
/// accounts, then paid out from the till (cash) or by reversal/transfer.
class RefundsTab extends StatelessWidget {
  const RefundsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final me = store.currentUser!;
    final manager = me.role == UserRole.admin || me.role == UserRole.accountant;
    final all = store.refundsNewestFirst;
    List<Refund> withStatus(Set<RefundStatus> s) =>
        all.where((r) => s.contains(r.status)).toList();
    final pending = withStatus({RefundStatus.pending});
    final approved = withStatus({RefundStatus.approved});
    final done = withStatus({RefundStatus.paid, RefundStatus.rejected});
    final text = Theme.of(context).textTheme;

    Widget heading(String title, int n) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text('$title ($n)', style: text.titleMedium),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                manager
                    ? 'Refunds you request are approved straight away.'
                    : 'Refunds need approval by administration or accounts '
                          'before they are paid out.',
                style: text.bodySmall,
              ),
            ),
            FilledButton.icon(
              key: const Key('new-refund'),
              icon: const Icon(Icons.undo),
              label: const Text('New refund'),
              onPressed: () async {
                final p = await pickPatient(context, store);
                if (p == null || !context.mounted) return;
                await showDialog(
                  context: context,
                  builder: (_) => _NewRefundDialog(patient: p),
                );
              },
            ),
          ],
        ),
        heading('Awaiting approval', pending.length),
        if (pending.isEmpty) const Text('None'),
        for (final r in pending) _tile(context, store, r, manager: manager),
        heading('Approved – to pay out', approved.length),
        if (approved.isEmpty) const Text('None'),
        for (final r in approved) _tile(context, store, r, manager: manager),
        heading('History', done.length),
        if (done.isEmpty) const Text('None'),
        for (final r in done.take(100))
          _tile(context, store, r, manager: manager),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    HospitalStore store,
    Refund r, {
    required bool manager,
  }) {
    final me = store.currentUser!;
    return Card(
      child: ListTile(
        leading: Icon(switch (r.status) {
          RefundStatus.pending => Icons.hourglass_top,
          RefundStatus.approved => Icons.thumb_up,
          RefundStatus.rejected => Icons.block,
          RefundStatus.paid => Icons.check_circle,
        }),
        title: Text(
          '${money(r.amount)} to ${store.patientName(r.patientId)} · '
          '${r.method}${r.number == null ? '' : ' · ${r.number}'}',
        ),
        subtitle: Text(
          [
            r.reason,
            'asked by ${store.userName(r.requestedBy)} '
                '${fmtDateTime(r.requestedAt)}',
            if (r.decidedBy != null)
              '${r.status == RefundStatus.rejected ? 'rejected' : 'approved'} '
                  'by ${store.userName(r.decidedBy!)}'
                  '${r.decisionNote.isEmpty ? '' : ': ${r.decisionNote}'}',
            if (r.paidAt != null)
              'paid out by ${store.userName(r.paidBy!)} '
                  '${fmtDateTime(r.paidAt)}',
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (r.status == RefundStatus.pending && manager) ...[
              TextButton(
                onPressed: () => _decide(context, store, r, approve: false),
                child: const Text('Reject'),
              ),
              FilledButton(
                onPressed: r.requestedBy == me.id && me.role != UserRole.admin
                    ? null
                    : () => _decide(context, store, r, approve: true),
                child: const Text('Approve'),
              ),
            ],
            if (r.status == RefundStatus.approved)
              FilledButton.icon(
                key: Key('pay-refund-${r.id}'),
                icon: const Icon(Icons.payments),
                label: const Text('Pay out'),
                onPressed: () => _payOut(context, store, r),
              ),
            if (r.status == RefundStatus.paid)
              PrintButton(
                tooltip: 'Print refund voucher',
                name: '${r.number}.pdf',
                document: () => refundVoucherPdf(store, r),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    HospitalStore store,
    Refund r, {
    required bool approve,
  }) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve refund' : 'Reject refund'),
        content: TextField(
          controller: note,
          decoration: InputDecoration(
            labelText: approve ? 'Note (optional)' : 'Reason for rejecting',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await guarded(
        context,
        () => store.decideRefund(r.id, approve: approve, note: note.text),
        success: approve ? 'Refund approved' : 'Refund rejected',
      );
    }
  }

  Future<void> _payOut(
    BuildContext context,
    HospitalStore store,
    Refund r,
  ) async {
    final reference = TextEditingController();
    final cash = r.method == 'Cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pay out ${money(r.amount)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cash
                  ? 'Give ${money(r.amount)} in cash from your till to '
                        '${store.patientName(r.patientId)} and ask them to '
                        'sign the voucher.'
                  : 'Refund ${money(r.amount)} by ${r.method.toLowerCase()} '
                        'to ${store.patientName(r.patientId)}, then enter the '
                        'reference.',
            ),
            if (!cash) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reference,
                decoration: InputDecoration(labelText: '${r.method} reference'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Paid out'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final paid = await guarded(
      context,
      () => store.payRefund(r.id, reference: reference.text),
      success: 'Refund paid out',
    );
    if (paid && context.mounted) {
      await printPdf(
        context,
        '${r.number}.pdf',
        () => refundVoucherPdf(store, r),
      );
    }
  }
}

class _NewRefundDialog extends StatefulWidget {
  const _NewRefundDialog({required this.patient});

  final Patient patient;

  @override
  State<_NewRefundDialog> createState() => _NewRefundDialogState();
}

class _NewRefundDialogState extends State<_NewRefundDialog> {
  Payment? _payment;
  String? _method;
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final payments = store.refundablePayments(widget.patient.id);
    return AlertDialog(
      title: Text('Refund ${widget.patient.name}'),
      content: SizedBox(
        width: 480,
        child: payments.isEmpty
            ? const Text('This patient has no payments that can be refunded.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Which payment?'),
                    RadioGroup<Payment>(
                      groupValue: _payment,
                      onChanged: (p) => setState(() {
                        _payment = p;
                        _method = p!.method == 'Insurance' ? 'Cash' : p.method;
                        _amount.text = store.refundableOn(p).toStringAsFixed(2);
                      }),
                      child: Column(
                        children: [
                          for (final p in payments)
                            RadioListTile<Payment>(
                              value: p,
                              title: Text(
                                '${money(p.amount)} ${p.method} · '
                                '${fmtDateTime(p.receivedAt)}',
                              ),
                              subtitle: Text(
                                '${store.invoiceById(p.invoiceId)?.number ?? ''}'
                                '${p.receiptNo == null ? '' : ' · ${p.receiptNo}'}'
                                ' · up to ${money(store.refundableOn(p))} '
                                'refundable',
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_payment != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('refund-amount'),
                              controller: _amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Amount',
                                prefixText: '\$ ',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _method,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Refund by',
                              ),
                              items: [
                                for (final m
                                    in CounterOperations.counterMethods)
                                  DropdownMenuItem(value: m, child: Text(m)),
                              ],
                              onChanged: (v) => setState(() => _method = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('refund-reason'),
                        controller: _reason,
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          hintText: 'e.g. Test cancelled, paid twice',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Refunding a bill that is still charged leaves the '
                        'patient owing that amount again. Remove the charge '
                        'or give a discount first if it should not be paid.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (payments.isNotEmpty)
          FilledButton(
            key: const Key('request-refund'),
            onPressed: _payment == null
                ? null
                : () async {
                    final nav = Navigator.of(context);
                    if (await guarded(
                      context,
                      () => store.requestRefund(
                        _payment!.id,
                        amount: double.tryParse(_amount.text.trim()) ?? 0,
                        reason: _reason.text,
                        method: _method,
                      ),
                      success: 'Refund requested',
                    )) {
                      nav.pop();
                    }
                  },
            child: const Text('Request refund'),
          ),
      ],
    );
  }
}
