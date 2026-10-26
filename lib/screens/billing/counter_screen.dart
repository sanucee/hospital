import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../print/documents.dart';
import '../../print/print_button.dart';
import '../../widgets/common.dart';

/// The cashier's counter: take payments for a patient's bills and run the
/// till.
class CounterScreen extends StatelessWidget {
  const CounterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: 'Take payment'),
              Tab(text: 'Tills and cash-up'),
            ],
          ),
          Expanded(child: TabBarView(children: [_TakePayment(), _Tills()])),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Till bar
// -----------------------------------------------------------------------------

class _TillBar extends StatelessWidget {
  const _TillBar();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final till = store.myOpenTill;
    final scheme = Theme.of(context).colorScheme;
    if (till == null) {
      return Card(
        color: scheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.point_of_sale),
          title: const Text('Your till is closed'),
          subtitle: const Text(
            'Open it with the cash float in the drawer to take payments.',
          ),
          trailing: FilledButton.icon(
            key: const Key('open-till'),
            icon: const Icon(Icons.lock_open),
            label: const Text('Open till'),
            onPressed: () => _openTill(context, store),
          ),
        ),
      );
    }
    final totals = store.tillTotals(till.id);
    final taken = totals.values.fold<double>(0, (a, b) => a + b);
    return Card(
      color: scheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.point_of_sale),
        title: Text(
          'Till open since ${fmtTime(till.openedAt)} · taken ${money(taken)}',
        ),
        subtitle: Text(
          [
            'Float ${money(till.openingFloat)}',
            for (final MapEntry(key: m, value: v) in totals.entries)
              '$m ${money(v)}',
            'Cash in drawer ${money(store.expectedCash(till))}',
          ].join(' · '),
        ),
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PrintButton(
              tooltip: 'Print cash-up so far',
              name: 'till-${fmtDate(till.openedAt)}.pdf',
              document: () => tillReportPdf(store, till),
            ),
            FilledButton.tonalIcon(
              key: const Key('close-till'),
              icon: const Icon(Icons.lock),
              label: const Text('Close till'),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _CloseTillDialog(till: till),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTill(BuildContext context, HospitalStore store) async {
    final float = TextEditingController(text: '0');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open till'),
        content: TextField(
          key: const Key('till-float'),
          controller: float,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Opening float (cash in the drawer)',
            prefixText: '\$ ',
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
                () => store.openTill(
                  openingFloat: double.tryParse(float.text.trim()) ?? -1,
                ),
                success: 'Till opened',
              )) {
                nav.pop();
              }
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

class _CloseTillDialog extends StatefulWidget {
  const _CloseTillDialog({required this.till});

  final CashTill till;

  @override
  State<_CloseTillDialog> createState() => _CloseTillDialogState();
}

class _CloseTillDialogState extends State<_CloseTillDialog> {
  final _counted = TextEditingController();
  final _notes = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final expected = store.expectedCash(widget.till);
    final counted = double.tryParse(_counted.text.trim());
    final diff = counted == null ? null : counted - expected;
    return AlertDialog(
      title: Text('Close till – ${store.userName(widget.till.cashierId)}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cash expected in the drawer: ${money(expected)}'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('till-counted'),
              controller: _counted,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Cash counted',
                prefixText: '\$ ',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (diff != null) ...[
              const SizedBox(height: 8),
              Text(
                diff.abs() < 0.005
                    ? 'The drawer balances.'
                    : diff < 0
                    ? 'Short by ${money(-diff)}'
                    : 'Over by ${money(diff)}',
                style: TextStyle(
                  color: diff.abs() < 0.005 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notes (explain any difference)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: counted == null
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  if (await guarded(
                    context,
                    () => store.closeTill(
                      widget.till.id,
                      countedCash: counted,
                      notes: _notes.text,
                    ),
                    success: 'Till closed',
                  )) {
                    nav.pop();
                  }
                },
          child: const Text('Close till'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Taking a payment
// -----------------------------------------------------------------------------

class _TakePayment extends StatefulWidget {
  const _TakePayment();

  @override
  State<_TakePayment> createState() => _TakePaymentState();
}

class _TakePaymentState extends State<_TakePayment> {
  String? _patientId;
  final _selected = <String>{};
  String _method = 'Cash';
  final _amount = TextEditingController();
  final _tendered = TextEditingController();
  final _reference = TextEditingController();

  /// Until the cashier types an amount, it follows the bills selected.
  bool _amountEdited = false;

  void _choose(Patient p, HospitalStore store) {
    setState(() {
      _patientId = p.id;
      _selected
        ..clear()
        ..addAll(store.outstandingFor(p.id).map((i) => i.id));
      _amountEdited = false;
      _tendered.clear();
      _reference.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _TillBar(),
        const SizedBox(height: 12),
        if (_patientId == null)
          _patientList(store)
        else
          _payment(store, store.patientById(_patientId!)!),
      ],
    );
  }

  /// Patients who owe something, most recent bill first, plus search.
  Widget _patientList(HospitalStore store) {
    final owing = <String, double>{};
    final latest = <String, DateTime>{};
    for (final i in store.invoices) {
      if (i.patientBalance <= 0.004) continue;
      owing[i.patientId] = (owing[i.patientId] ?? 0) + i.patientBalance;
      if (latest[i.patientId] == null ||
          i.createdAt.isAfter(latest[i.patientId]!)) {
        latest[i.patientId] = i.createdAt;
      }
    }
    final ids = owing.keys.toList()
      ..sort((a, b) => latest[b]!.compareTo(latest[a]!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Patients with bills to pay',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Find patient'),
              onPressed: () async {
                final p = await pickPatient(context, store);
                if (p != null) _choose(p, store);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (ids.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: EmptyState('Nobody owes anything', icon: Icons.check),
          ),
        for (final id in ids)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text(store.patientName(id)),
              subtitle: Text(
                '${store.patientById(id)?.mrn ?? ''} · '
                '${store.outstandingFor(id).length} bill(s) · '
                'last ${fmtDate(latest[id])}',
              ),
              trailing: Text(
                money(owing[id]!),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () => _choose(store.patientById(id)!, store),
            ),
          ),
      ],
    );
  }

  Widget _payment(HospitalStore store, Patient p) {
    final bills = store.outstandingFor(p.id);
    _selected.removeWhere((id) => !bills.any((b) => b.id == id));
    final due = bills
        .where((b) => _selected.contains(b.id))
        .fold<double>(0, (s, b) => s + b.patientBalance);
    if (!_amountEdited) _amount.text = due.toStringAsFixed(2);
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final tendered = double.tryParse(_tendered.text.trim());
    final cash = _method == 'Cash';
    final change = cash && tendered != null ? tendered - amount : null;
    final till = store.myOpenTill;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${p.name} · ${p.mrn}', style: text.titleMedium),
            ),
            TextButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Another patient'),
              onPressed: () => setState(() => _patientId = null),
            ),
          ],
        ),
        if (bills.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: EmptyState('All bills are paid', icon: Icons.check_circle),
          ),
        for (final b in bills)
          CheckboxListTile(
            value: _selected.contains(b.id),
            onChanged: (v) => setState(() {
              v! ? _selected.add(b.id) : _selected.remove(b.id);
              _amountEdited = false;
            }),
            title: Text('${b.number} · ${fmtDate(b.createdAt)}'),
            subtitle: Text(
              'Total ${money(b.total)}'
              '${b.insurerCovered > 0 ? ' · insurer pays ${money(b.insurerCovered)}' : ''}'
              '${b.amountPaid > 0 ? ' · paid ${money(b.amountPaid)}' : ''}',
            ),
            controlAffinity: ListTileControlAffinity.leading,
            secondary: Text(money(b.patientBalance), style: text.titleSmall),
          ),
        if (bills.isNotEmpty) ...[
          const Divider(),
          Text('Selected: ${money(due)}', style: text.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              for (final m in CounterOperations.counterMethods)
                ChoiceChip(
                  label: Text(m),
                  selected: _method == m,
                  onSelected: (_) => setState(() => _method = m),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('pay-amount'),
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount to pay',
                    prefixText: '\$ ',
                    helperText: 'Less than the total for a part-payment',
                  ),
                  onChanged: (_) => setState(() => _amountEdited = true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: cash
                    ? TextField(
                        key: const Key('pay-tendered'),
                        controller: _tendered,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Cash handed over',
                          prefixText: '\$ ',
                        ),
                        onChanged: (_) => setState(() {}),
                      )
                    : TextField(
                        key: const Key('pay-reference'),
                        controller: _reference,
                        decoration: InputDecoration(
                          labelText: '$_method reference',
                          helperText: 'From the card slip or transfer message',
                        ),
                      ),
              ),
            ],
          ),
          if (change != null) ...[
            const SizedBox(height: 8),
            Text(
              change < -0.004
                  ? 'Not enough: ${money(-change)} more needed'
                  : 'Change to give: ${money(change)}',
              style: text.titleLarge?.copyWith(
                color: change < -0.004 ? Colors.red : Colors.green.shade700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('take-payment'),
              icon: const Icon(Icons.payments),
              label: Text('Take ${money(amount)}'),
              onPressed: till == null || _selected.isEmpty || amount <= 0
                  ? null
                  : () => _take(store, p, amount, tendered),
            ),
          ),
          if (till == null)
            const Align(
              alignment: Alignment.centerRight,
              child: Text('Open your till first.'),
            ),
        ],
      ],
    );
  }

  Future<void> _take(
    HospitalStore store,
    Patient p,
    double amount,
    double? tendered,
  ) async {
    CounterReceipt? receipt;
    final ok = await guarded(context, () async {
      receipt = await store.takeCounterPayment(
        patientId: p.id,
        invoiceIds: _selected.toList(),
        amount: amount,
        method: _method,
        tendered: tendered,
        reference: _reference.text,
      );
    });
    if (!ok || !mounted) return;
    final r = receipt!;
    setState(() {
      _amountEdited = false;
      _tendered.clear();
      _reference.clear();
    });
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Paid · ${r.receiptNo}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Received ${money(r.total)} from ${p.name}'),
            if (r.tendered != null) ...[
              const SizedBox(height: 8),
              Text(
                'Change to give: ${money(r.change)}',
                style: Theme.of(ctx).textTheme.headlineSmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Print receipt'),
            onPressed: () => printPdf(
              ctx,
              '${r.receiptNo}.pdf',
              () => counterReceiptPdf(
                store,
                r.receiptNo,
                tendered: r.tendered,
                change: r.change,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Tills
// -----------------------------------------------------------------------------

class _Tills extends StatelessWidget {
  const _Tills();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final me = store.currentUser!;
    final manager = me.role == UserRole.admin || me.role == UserRole.accountant;
    final list = store.tillsNewestFirst
        .where((t) => manager || t.cashierId == me.id)
        .toList();
    if (list.isEmpty) {
      return const EmptyState('No tills yet', icon: Icons.point_of_sale);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final t in list)
          Card(
            child: ListTile(
              leading: Icon(
                t.isOpen ? Icons.lock_open : Icons.lock,
                color: t.isOpen ? Colors.orange : null,
              ),
              title: Text(
                '${store.userName(t.cashierId)} · ${fmtDateTime(t.openedAt)}'
                '${t.isOpen ? ' · open' : ' – ${fmtTime(t.closedAt)}'}',
              ),
              subtitle: Text(
                [
                  for (final MapEntry(key: m, value: v)
                      in store.tillTotals(t.id).entries)
                    '$m ${money(v)}',
                  'expected cash ${money(t.expectedCash ?? store.expectedCash(t))}',
                  if (t.countedCash != null) 'counted ${money(t.countedCash!)}',
                  if (t.notes.isNotEmpty) t.notes,
                ].join(' · '),
              ),
              trailing: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (t.variance != null)
                    t.variance!.abs() < 0.005
                        ? const StatusChip('Balanced', color: Colors.green)
                        : StatusChip(
                            '${t.variance! < 0 ? 'Short' : 'Over'} '
                            '${money(t.variance!.abs())}',
                            color: Colors.red,
                          ),
                  PrintButton(
                    tooltip: 'Print cash-up',
                    name: 'till-${fmtDate(t.openedAt)}.pdf',
                    document: () => tillReportPdf(store, t),
                  ),
                  if (t.isOpen && manager && t.cashierId != me.id)
                    TextButton(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _CloseTillDialog(till: t),
                      ),
                      child: const Text('Close'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
