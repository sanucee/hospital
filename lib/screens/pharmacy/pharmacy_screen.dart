import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';

class PharmacyScreen extends StatelessWidget {
  const PharmacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final queue = store.pharmacyQueue;
    final history = store.prescriptions
        .where((p) =>
            p.status == PrescriptionStatus.dispensed ||
            p.status == PrescriptionStatus.cancelled)
        .toList()
      ..sort((a, b) => (b.dispensedAt ?? b.createdAt)
          .compareTo(a.dispensedAt ?? a.createdAt));
    final alerts = store.medicines
        .where((m) => m.isLowStock || m.isExpired || m.expiresSoon)
        .length;

    return DefaultTabController(
      length: 3,
      child: Column(children: [
        TabBar(tabs: [
          Tab(text: 'To dispense (${queue.length})'),
          Tab(text: 'History (${history.length})'),
          Tab(
            child: Badge(
              isLabelVisible: alerts > 0,
              label: Text('$alerts'),
              child: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text('Inventory'),
              ),
            ),
          ),
        ]),
        Expanded(
          child: TabBarView(children: [
            queue.isEmpty
                ? const EmptyState('No prescriptions waiting',
                    icon: Icons.local_pharmacy)
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final rx in queue) _RxCard(rx: rx),
                  ]),
            history.isEmpty
                ? const EmptyState('Nothing dispensed yet')
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final rx in history) _RxCard(rx: rx),
                  ]),
            const _Inventory(),
          ]),
        ),
      ]),
    );
  }
}

class _RxCard extends StatelessWidget {
  const _RxCard({required this.rx});

  final Prescription rx;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final p = store.patientById(rx.patientId);
    final active = rx.status == PrescriptionStatus.pending ||
        rx.status == PrescriptionStatus.partiallyDispensed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            PatientDetailScreen(patientId: rx.patientId))),
                child: Text('${p?.name ?? 'Unknown'} · ${p?.mrn}',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            StatusChip.prescription(rx.status),
          ]),
          Text('Prescribed by ${store.userName(rx.doctorId)} at '
              '${fmtDateTime(rx.createdAt)}'),
          if (p != null && p.allergies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: StatusChip('Allergies: ${p.allergies}',
                  color: Colors.red, icon: Icons.warning),
            ),
          const Divider(),
          for (final i in rx.items)
            Builder(builder: (context) {
              final med = store.medicineById(i.medicineId);
              final short = med != null && med.stock < i.outstanding;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(i.medicineName),
                subtitle: Text('${i.dosage} · ${i.frequency} · '
                    '${i.durationDays} days'
                    '${i.instructions.isEmpty ? '' : ' · ${i.instructions}'}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${i.dispensedQuantity}/${i.quantity} given'),
                    if (active)
                      Text('Stock: ${med?.stock ?? 0}',
                          style: TextStyle(
                              color: short || (med?.isExpired ?? true)
                                  ? Colors.red
                                  : Colors.green)),
                  ],
                ),
              );
            }),
          if (active)
            Wrap(spacing: 8, children: [
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Dispense'),
                onPressed: () => showDialog(
                    context: context, builder: (_) => _DispenseDialog(rx: rx)),
              ),
            ]),
          if (rx.dispensedAt != null)
            Text('Last dispensed ${fmtDateTime(rx.dispensedAt)}'
                '${rx.pharmacistId == null ? '' : ' by ${store.userName(rx.pharmacistId!)}'}',
                style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _DispenseDialog extends StatefulWidget {
  const _DispenseDialog({required this.rx});

  final Prescription rx;

  @override
  State<_DispenseDialog> createState() => _DispenseDialogState();
}

class _DispenseDialogState extends State<_DispenseDialog> {
  late final List<TextEditingController> _qty;

  @override
  void initState() {
    super.initState();
    final store = context.read<HospitalStore>();
    _qty = [
      for (final i in widget.rx.items)
        TextEditingController(
          text: () {
            final stock = store.medicineById(i.medicineId)?.stock ?? 0;
            final q = i.outstanding < stock ? i.outstanding : stock;
            return '${q < 0 ? 0 : q}';
          }(),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    var total = 0.0;
    for (var i = 0; i < widget.rx.items.length; i++) {
      final med = store.medicineById(widget.rx.items[i].medicineId);
      total += (int.tryParse(_qty[i].text) ?? 0) * (med?.unitPrice ?? 0);
    }
    return AlertDialog(
      title: const Text('Dispense medicines'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < widget.rx.items.length; i++)
            Builder(builder: (_) {
              final item = widget.rx.items[i];
              final med = store.medicineById(item.medicineId);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.medicineName),
                subtitle: Text('Outstanding ${item.outstanding} · '
                    'In stock ${med?.stock ?? 0} · '
                    '${money(med?.unitPrice ?? 0)} each'),
                trailing: SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _qty[i],
                    enabled: item.outstanding > 0,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Qty', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              );
            }),
          const Divider(),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Added to bill: ${money(total)}',
                style: Theme.of(context).textTheme.titleMedium),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            final ok = await guarded(
                context,
                () => store.dispense(widget.rx.id, quantities: {
                      for (var i = 0; i < _qty.length; i++)
                        i: int.tryParse(_qty[i].text) ?? 0,
                    }),
                success: 'Dispensed and billed');
            if (ok) nav.pop();
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

class _Inventory extends StatefulWidget {
  const _Inventory();

  @override
  State<_Inventory> createState() => _InventoryState();
}

class _InventoryState extends State<_Inventory> {
  String _query = '';
  bool _alertsOnly = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final q = _query.toLowerCase();
    final meds = store.medicines
        .where((m) =>
            m.displayName.toLowerCase().contains(q) &&
            (!_alertsOnly || m.isLowStock || m.isExpired || m.expiresSoon))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editMedicine(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search medicines'),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Alerts only'),
              selected: _alertsOnly,
              onSelected: (v) => setState(() => _alertsOnly = v),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            for (final m in meds)
              ListTile(
                title: Text(m.displayName),
                subtitle: Text('${money(m.unitPrice)} / unit · '
                    'Reorder at ${m.reorderLevel} · '
                    'Expiry ${fmtDate(m.expiryDate)}'),
                leading: CircleAvatar(
                  backgroundColor: m.isExpired || m.stock == 0
                      ? Colors.red.withValues(alpha: 0.2)
                      : m.isLowStock || m.expiresSoon
                          ? Colors.orange.withValues(alpha: 0.2)
                          : Colors.green.withValues(alpha: 0.2),
                  child: Text('${m.stock}', style: const TextStyle(fontSize: 12)),
                ),
                trailing: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (m.isExpired)
                      const StatusChip('Expired', color: Colors.red)
                    else if (m.expiresSoon)
                      const StatusChip('Expiring', color: Colors.orange),
                    if (m.isLowStock)
                      const StatusChip('Low', color: Colors.deepOrange),
                    IconButton(
                      tooltip: 'Restock',
                      icon: const Icon(Icons.add_box),
                      onPressed: () => _restock(context, m),
                    ),
                  ],
                ),
                onTap: () => _editMedicine(context, m),
              ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _restock(BuildContext context, Medicine m) async {
    final store = context.read<HospitalStore>();
    final qty = TextEditingController();
    DateTime? expiry;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Restock ${m.displayName}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: qty,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity received'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(expiry == null
                  ? 'New batch expiry (optional)'
                  : 'Expiry ${fmtDate(expiry)}'),
              onPressed: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100));
                if (d != null) setState(() => expiry = d);
              },
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final nav = Navigator.of(ctx);
                final ok = await guarded(
                    ctx,
                    () => store.restock(m.id, int.tryParse(qty.text) ?? 0,
                        expiryDate: expiry),
                    success: 'Stock updated');
                if (ok) nav.pop();
              },
              child: const Text('Add stock'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMedicine(BuildContext context, Medicine? existing) async {
    final store = context.read<HospitalStore>();
    final name = TextEditingController(text: existing?.name);
    final form = TextEditingController(text: existing?.form ?? 'Tablet');
    final strength = TextEditingController(text: existing?.strength);
    final price = TextEditingController(text: existing?.unitPrice.toString());
    final stock = TextEditingController(text: '${existing?.stock ?? 0}');
    final reorder =
        TextEditingController(text: '${existing?.reorderLevel ?? 20}');
    final mfr = TextEditingController(text: existing?.manufacturer);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add medicine' : 'Edit medicine'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (c, l, numeric) in [
                (name, 'Name', false),
                (form, 'Form (Tablet, Syrup…)', false),
                (strength, 'Strength', false),
                (price, 'Unit price', true),
                if (existing == null) (stock, 'Opening stock', true),
                (reorder, 'Reorder level', true),
                (mfr, 'Manufacturer', false),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: c,
                    keyboardType: numeric ? TextInputType.number : null,
                    decoration: InputDecoration(labelText: l),
                  ),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final ok = await guarded(ctx, () async {
                final p = double.tryParse(price.text);
                if (name.text.trim().isEmpty || p == null || p < 0) {
                  throw HospitalException('Name and a valid price are required');
                }
                final m = existing ??
                    Medicine(
                      id: store.newId('MED'),
                      name: '',
                      form: '',
                      strength: '',
                      unitPrice: 0,
                      stock: int.tryParse(stock.text) ?? 0,
                      expiryDate:
                          DateTime.now().add(const Duration(days: 365)),
                    );
                m
                  ..name = name.text.trim()
                  ..form = form.text.trim()
                  ..strength = strength.text.trim()
                  ..unitPrice = p
                  ..reorderLevel = int.tryParse(reorder.text) ?? 20
                  ..manufacturer = mfr.text.trim();
                await store.upsertMedicine(m);
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
