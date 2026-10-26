import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../print/documents.dart';
import '../../print/print_button.dart';
import '../../widgets/common.dart';

StatusChip _poChip(PurchaseOrder po) => StatusChip(
  po.status.label,
  color: switch (po.status) {
    PurchaseStatus.draft => Colors.blueGrey,
    PurchaseStatus.ordered => Colors.orange,
    PurchaseStatus.partiallyReceived => Colors.deepPurple,
    PurchaseStatus.received => Colors.green,
    PurchaseStatus.cancelled => Colors.grey,
  },
);

class PurchaseOrdersTab extends StatelessWidget {
  const PurchaseOrdersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final orders = store.purchaseOrdersByDate;
    final low = store.reorderSuggestions().length;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: store.suppliers.isEmpty
            ? null
            : () => showDialog(
                context: context,
                builder: (_) => const _NewOrderDialog(),
              ),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('New purchase order'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        children: [
          if (store.suppliers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Add a supplier first (Suppliers tab).'),
            ),
          if (low > 0)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.inventory_2),
                title: Text('$low medicine(s) at or below reorder level'),
                subtitle: const Text(
                  'New purchase orders can be pre-filled with them.',
                ),
              ),
            ),
          if (orders.isEmpty)
            const EmptyState(
              'No purchase orders yet',
              icon: Icons.local_shipping,
            ),
          for (final po in orders) _OrderCard(order: po),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final po = order;
    final supplier = store.supplierById(po.supplierId);
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.local_shipping),
        title: Text('${po.number} · ${supplier?.name ?? 'Unknown supplier'}'),
        subtitle: Text(
          [
            'Created ${fmtDate(po.createdAt)}',
            '${po.items.length} item(s)',
            money(po.total),
            if (po.expectedOn != null) 'due ${fmtDate(po.expectedOn)}',
            if (po.isPaid) 'supplier paid',
          ].join(' · '),
        ),
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _poChip(po),
            PrintButton(
              tooltip: 'Print purchase order',
              name: '${po.number}.pdf',
              document: () => purchaseOrderPdf(store, po),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final i in po.items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(i.medicineName),
              subtitle: Text('${money(i.unitCost)} each'),
              trailing: Text(
                '${i.receivedQuantity}/${i.quantity} received',
                style: TextStyle(
                  color: i.outstanding > 0 ? Colors.orange : Colors.green,
                ),
              ),
            ),
          for (final r in po.receipts)
            Text(
              'Delivery ${fmtDateTime(r.receivedAt)}'
              '${r.deliveryNote.isEmpty ? '' : ' (${r.deliveryNote})'}: '
              '${r.lines.map((l) => '${l.quantity}'
                  '${l.batchNumber.isEmpty ? '' : ' batch ${l.batchNumber}'}'
                  '${l.expiryDate == null ? '' : ' exp ${fmtDate(l.expiryDate)}'}').join('; ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (po.notes.isNotEmpty) Text('Notes: ${po.notes}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (po.status == PurchaseStatus.draft)
                FilledButton(
                  onPressed: () => guarded(
                    context,
                    () => store.placePurchaseOrder(po.id),
                    success: 'Order placed',
                  ),
                  child: const Text('Place order'),
                ),
              if (po.status == PurchaseStatus.ordered ||
                  po.status == PurchaseStatus.partiallyReceived)
                FilledButton.icon(
                  icon: const Icon(Icons.move_to_inbox),
                  label: const Text('Receive goods'),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => _ReceiveDialog(order: po),
                  ),
                ),
              if (po.status != PurchaseStatus.cancelled &&
                  po.status != PurchaseStatus.received &&
                  po.items.every((i) => i.receivedQuantity == 0))
                TextButton(
                  onPressed: () =>
                      guarded(context, () => store.cancelPurchaseOrder(po.id)),
                  child: const Text('Cancel order'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DraftLine {
  _DraftLine({this.medicine, int qty = 0, double cost = 0})
    : qty = TextEditingController(text: qty == 0 ? '' : '$qty'),
      cost = TextEditingController(
        text: cost == 0 ? '' : cost.toStringAsFixed(2),
      );

  Medicine? medicine;
  final TextEditingController qty;
  final TextEditingController cost;
}

class _NewOrderDialog extends StatefulWidget {
  const _NewOrderDialog();

  @override
  State<_NewOrderDialog> createState() => _NewOrderDialogState();
}

class _NewOrderDialogState extends State<_NewOrderDialog> {
  String? _supplierId;
  final _lines = <_DraftLine>[];
  final _notes = TextEditingController();
  DateTime? _expected;

  void _addLowStock() {
    final store = context.read<HospitalStore>();
    final have = _lines.map((l) => l.medicine?.id).toSet();
    setState(() {
      _lines.removeWhere((l) => l.medicine == null);
      for (final s in store.reorderSuggestions()) {
        if (have.contains(s.medicineId)) continue;
        _lines.add(
          _DraftLine(
            medicine: store.medicineById(s.medicineId),
            qty: s.quantity,
            cost: s.unitCost,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final meds = [...store.medicines]..sort((a, b) => a.name.compareTo(b.name));
    var total = 0.0;
    for (final l in _lines) {
      total +=
          (int.tryParse(l.qty.text) ?? 0) * (double.tryParse(l.cost.text) ?? 0);
    }
    return AlertDialog(
      title: const Text('New purchase order'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _supplierId,
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: [
                  for (final s in store.suppliers)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _supplierId = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Add low-stock items'),
                    onPressed: _addLowStock,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add item'),
                    onPressed: () => setState(() => _lines.add(_DraftLine())),
                  ),
                ],
              ),
              for (final (i, l) in _lines.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: DropdownButtonFormField<Medicine>(
                          initialValue: l.medicine,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Medicine',
                            isDense: true,
                          ),
                          items: [
                            for (final m in meds)
                              DropdownMenuItem(
                                value: m,
                                child: Text(
                                  '${m.displayName} (stock ${m.stock})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (m) => setState(() {
                            l.medicine = m;
                            if (l.cost.text.isEmpty && m != null) {
                              l.cost.text =
                                  (m.costPrice > 0
                                          ? m.costPrice
                                          : m.unitPrice * 0.6)
                                      .toStringAsFixed(2);
                            }
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: l.qty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Qty',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: l.cost,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Unit cost',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _lines.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(
                        _expected == null
                            ? 'Expected delivery (optional)'
                            : 'Expected ${fmtDate(_expected)}',
                      ),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().add(
                            const Duration(days: 3),
                          ),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => _expected = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Total ${money(total)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _supplierId == null
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  if (await guarded(context, () async {
                    final items = <PurchaseItem>[];
                    for (final l in _lines) {
                      if (l.medicine == null) {
                        throw HospitalException(
                          'Choose a medicine for every row',
                        );
                      }
                      final qty = int.tryParse(l.qty.text) ?? 0;
                      final cost = double.tryParse(l.cost.text);
                      if (qty <= 0 || cost == null) {
                        throw HospitalException(
                          '${l.medicine!.name}: enter a quantity and unit cost',
                        );
                      }
                      items.add(
                        PurchaseItem(
                          medicineId: l.medicine!.id,
                          medicineName: l.medicine!.displayName,
                          quantity: qty,
                          unitCost: cost,
                        ),
                      );
                    }
                    await store.createPurchaseOrder(
                      supplierId: _supplierId!,
                      items: items,
                      expectedOn: _expected,
                      notes: _notes.text,
                    );
                  }, success: 'Purchase order created as a draft')) {
                    nav.pop();
                  }
                },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _ReceiveDialog extends StatefulWidget {
  const _ReceiveDialog({required this.order});

  final PurchaseOrder order;

  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  late final _qty = [
    for (final i in widget.order.items)
      TextEditingController(text: '${i.outstanding}'),
  ];
  late final _batch = [
    for (final _ in widget.order.items) TextEditingController(),
  ];
  late final _expiry = List<DateTime?>.filled(widget.order.items.length, null);
  final _note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final items = widget.order.items;
    return AlertDialog(
      title: Text('Receive ${widget.order.number}'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++)
                if (items[i].outstanding > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${items[i].medicineName} '
                          '(${items[i].outstanding} outstanding)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _qty[i],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Qty received',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _batch[i],
                                decoration: const InputDecoration(
                                  labelText: 'Batch no.',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime(2100),
                                  );
                                  if (d != null) setState(() => _expiry[i] = d);
                                },
                                child: Text(
                                  _expiry[i] == null
                                      ? 'Expiry'
                                      : fmtDate(_expiry[i]),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Supplier delivery note / invoice no.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            final store = context.read<HospitalStore>();
            if (await guarded(
              context,
              () => store.receiveGoods(widget.order.id, {
                for (var i = 0; i < items.length; i++)
                  if (items[i].outstanding > 0)
                    i: (
                      int.tryParse(_qty[i].text) ?? 0,
                      _batch[i].text,
                      _expiry[i],
                    ),
              }, deliveryNote: _note.text),
              success: 'Stock updated',
            )) {
              nav.pop();
            }
          },
          child: const Text('Receive into stock'),
        ),
      ],
    );
  }
}

class SuppliersTab extends StatelessWidget {
  const SuppliersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_business),
        label: const Text('Add supplier'),
      ),
      body: store.suppliers.isEmpty
          ? const EmptyState('No suppliers yet', icon: Icons.store)
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final s in store.suppliers)
                  ListTile(
                    leading: const Icon(Icons.store),
                    title: Text(s.name),
                    subtitle: Text(
                      [
                        if (s.contactPerson.isNotEmpty) s.contactPerson,
                        if (s.phone.isNotEmpty) s.phone,
                        if (s.email.isNotEmpty) s.email,
                        '${store.purchaseOrders.where((p) => p.supplierId == s.id).length} order(s)',
                      ].join(' · '),
                    ),
                    onTap: () => _edit(context, s),
                  ),
              ],
            ),
    );
  }

  Future<void> _edit(BuildContext context, Supplier? existing) async {
    final store = context.read<HospitalStore>();
    final fields = [
      ('Name', TextEditingController(text: existing?.name)),
      ('Contact person', TextEditingController(text: existing?.contactPerson)),
      ('Phone', TextEditingController(text: existing?.phone)),
      ('Email', TextEditingController(text: existing?.email)),
      ('Address', TextEditingController(text: existing?.address)),
    ];
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add supplier' : 'Edit supplier'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (label, c) in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: c,
                      decoration: InputDecoration(labelText: label),
                    ),
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
              if (await guarded(ctx, () async {
                if (fields[0].$2.text.trim().isEmpty) {
                  throw HospitalException('Enter a name');
                }
                final s =
                    (existing == null
                        ? null
                        : store.supplierById(existing.id)) ??
                    Supplier(id: store.newId('SUP'), name: '');
                s
                  ..name = fields[0].$2.text.trim()
                  ..contactPerson = fields[1].$2.text.trim()
                  ..phone = fields[2].$2.text.trim()
                  ..email = fields[3].$2.text.trim()
                  ..address = fields[4].$2.text.trim();
                await store.upsertSupplier(s);
              })) {
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
