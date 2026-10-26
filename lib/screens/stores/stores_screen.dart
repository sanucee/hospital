import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../print/documents.dart';
import '../../print/print_button.dart';
import '../../widgets/common.dart';

Color requisitionColor(RequisitionStatus s) => switch (s) {
  RequisitionStatus.pending => Colors.orange,
  RequisitionStatus.partlyIssued => Colors.deepPurple,
  RequisitionStatus.issued => Colors.green,
  RequisitionStatus.rejected => Colors.red,
  RequisitionStatus.cancelled => Colors.grey,
};

bool _isStorekeeper(HospitalStore s) =>
    {UserRole.admin, UserRole.storekeeper}.contains(s.currentUser?.role);

/// The general store: requisitions from departments, and the inventory.
class StoresScreen extends StatelessWidget {
  const StoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final keeper = _isStorekeeper(store);
    final low = store.lowStockStoreItems.length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'new-requisition',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const RequisitionDialog(),
          ),
          icon: const Icon(Icons.playlist_add),
          label: const Text('New requisition'),
        ),
        body: Column(
          children: [
            TabBar(
              tabs: [
                Tab(
                  text: keeper
                      ? 'Requisitions (${store.openRequisitions.length})'
                      : 'My requisitions',
                ),
                Tab(
                  text:
                      'Items (${store.storeItems.length})'
                      '${low > 0 ? ' · $low low' : ''}',
                ),
              ],
            ),
            const Expanded(
              child: TabBarView(children: [_RequisitionsTab(), _ItemsTab()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequisitionsTab extends StatelessWidget {
  const _RequisitionsTab();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final keeper = _isStorekeeper(store);
    final open = keeper
        ? store.openRequisitions
        : store.requisitionsBy(store.currentUser!.id).where((r) => r.isOpen);
    final closed =
        (keeper
                ? store.requisitions
                : store.requisitionsBy(store.currentUser!.id))
            .where((r) => !r.isOpen)
            .toList()
          ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    if (open.isEmpty && closed.isEmpty) {
      return const EmptyState('No requisitions', icon: Icons.inventory_2);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        for (final r in open) _RequisitionCard(requisition: r),
        if (closed.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Text(
              'Issued, rejected and cancelled',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final r in closed.take(40)) _RequisitionCard(requisition: r),
        ],
      ],
    );
  }
}

class _RequisitionCard extends StatelessWidget {
  const _RequisitionCard({required this.requisition});

  final Requisition requisition;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final r = requisition;
    final keeper = _isStorekeeper(store);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${r.number} · ${r.department}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusChip(r.status.label, color: requisitionColor(r.status)),
                PrintButton(
                  tooltip: 'Print requisition',
                  name: 'requisition.pdf',
                  document: () => requisitionPdf(store, r),
                ),
              ],
            ),
            Text(
              '${store.userName(r.requestedBy)} · ${fmtDateTime(r.requestedAt)}'
              '${r.patientId == null ? '' : ' · for ${store.patientName(r.patientId!)}'}',
            ),
            if (r.notes.isNotEmpty) Text(r.notes),
            if (r.decisionNote.isNotEmpty) Text('Store: ${r.decisionNote}'),
            const SizedBox(height: 4),
            for (final l in r.lines)
              Text(
                '• ${l.itemName}: ${l.quantity}'
                '${l.issuedQuantity > 0 ? ' (issued ${l.issuedQuantity})' : ''}'
                '${keeper && r.isOpen ? ' · in stock ${store.storeItemById(l.itemId)?.stock ?? 0}' : ''}',
              ),
            if (r.isOpen)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (keeper)
                      FilledButton.icon(
                        icon: const Icon(Icons.outbox),
                        label: const Text('Issue'),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => _IssueDialog(requisition: r),
                        ),
                      ),
                    if (keeper && r.status == RequisitionStatus.pending)
                      TextButton(
                        onPressed: () => _reject(context, store, r),
                        child: const Text('Reject'),
                      ),
                    if (r.requestedBy == store.currentUser?.id &&
                        r.status == RequisitionStatus.pending)
                      TextButton(
                        onPressed: () => guarded(
                          context,
                          () => store.cancelRequisition(r.id),
                          success: 'Requisition cancelled',
                        ),
                        child: const Text('Withdraw'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _reject(
    BuildContext context,
    HospitalStore store,
    Requisition r,
  ) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject ${r.number}'),
        content: TextField(
          controller: note,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await guarded(
      context,
      () => store.rejectRequisition(r.id, note.text),
      success: 'Requisition rejected',
    );
  }
}

class _IssueDialog extends StatefulWidget {
  const _IssueDialog({required this.requisition});

  final Requisition requisition;

  @override
  State<_IssueDialog> createState() => _IssueDialogState();
}

class _IssueDialogState extends State<_IssueDialog> {
  late final _qty = [
    for (final l in widget.requisition.lines)
      TextEditingController(text: '${l.outstanding}'),
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final r = widget.requisition;
    return AlertDialog(
      title: Text('Issue ${r.number}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r.patientId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Billable items are charged to '
                  '${store.patientName(r.patientId!)}.',
                ),
              ),
            for (final (i, l) in r.lines.indexed)
              if (l.outstanding > 0)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.itemName),
                  subtitle: Text(
                    'Outstanding ${l.outstanding} · in stock '
                    '${store.storeItemById(l.itemId)?.stock ?? 0}',
                  ),
                  trailing: SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _qty[i],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Issue',
                        isDense: true,
                      ),
                    ),
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
          onPressed: () async {
            final nav = Navigator.of(context);
            final ok = await guarded(
              context,
              () => store.issueRequisition(
                r.id,
                quantities: {
                  for (final (i, c) in _qty.indexed)
                    i: int.tryParse(c.text.trim()) ?? 0,
                },
              ),
              success: 'Supplies issued',
            );
            if (ok) nav.pop();
          },
          child: const Text('Issue'),
        ),
      ],
    );
  }
}

/// Asks the store for supplies. Anyone may raise one.
class RequisitionDialog extends StatefulWidget {
  const RequisitionDialog({super.key, this.patientId, this.department});

  final String? patientId;
  final String? department;

  @override
  State<RequisitionDialog> createState() => _RequisitionDialogState();
}

class _RequisitionDialogState extends State<RequisitionDialog> {
  late String _department = widget.department ?? _defaultDepartment();
  late String? _patientId = widget.patientId;
  final _qty = <String, int>{};
  final _notes = TextEditingController();
  var _query = '';

  String _defaultDepartment() {
    final role = context.read<HospitalStore>().currentUser?.role;
    return switch (role) {
      UserRole.nurse => 'Wards',
      UserRole.labTechnician => 'Laboratory',
      UserRole.radiographer => 'Radiology',
      UserRole.pharmacist => 'Pharmacy',
      UserRole.receptionist => 'Reception',
      _ => kStoreDepartments.first,
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final q = _query.trim().toLowerCase();
    final items =
        store.storeItems
            .where((i) => q.isEmpty || i.name.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return AlertDialog(
      title: const Text('Store requisition'),
      content: SizedBox(
        width: 520,
        height: 560,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _department,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: [
                      for (final d in kStoreDepartments)
                        DropdownMenuItem(value: d, child: Text(d)),
                    ],
                    onChanged: (d) => setState(() => _department = d!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'For patient (optional)',
                    ),
                    child: InkWell(
                      onTap: () async {
                        final p = await pickPatient(context, store);
                        if (p != null) setState(() => _patientId = p.id);
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _patientId == null
                                  ? 'None'
                                  : store.patientName(_patientId!),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_patientId != null)
                            InkWell(
                              onTap: () => setState(() => _patientId = null),
                              child: const Icon(Icons.clear, size: 18),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Find item',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final i in items)
                    ListTile(
                      dense: true,
                      title: Text(i.name),
                      subtitle: Text(
                        '${i.category} · ${i.stock} ${i.unit} in store'
                        '${i.billable ? ' · billable ${money(i.patientPrice)}' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: (_qty[i.id] ?? 0) == 0
                                ? null
                                : () => setState(
                                    () => _qty[i.id] = _qty[i.id]! - 1,
                                  ),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${_qty[i.id] ?? 0}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () => setState(
                              () => _qty[i.id] = (_qty[i.id] ?? 0) + 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
      actions: [
        Text('${_qty.values.where((q) => q > 0).length} item(s)'),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            final ok = await guarded(
              context,
              () => store.createRequisition(
                department: _department,
                quantities: _qty,
                patientId: _patientId,
                notes: _notes.text,
              ),
              success: 'Requisition sent to the store',
            );
            if (ok) nav.pop();
          },
          child: const Text('Send'),
        ),
      ],
    );
  }
}

class _ItemsTab extends StatefulWidget {
  const _ItemsTab();

  @override
  State<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends State<_ItemsTab> {
  var _query = '';
  var _lowOnly = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final keeper = _isStorekeeper(store);
    final q = _query.trim().toLowerCase();
    final items =
        store.storeItems
            .where(
              (i) =>
                  (!_lowOnly || i.isLowStock) &&
                  (q.isEmpty ||
                      i.name.toLowerCase().contains(q) ||
                      i.category.toLowerCase().contains(q)),
            )
            .toList()
          ..sort(
            (a, b) =>
                '${a.category}${a.name}'.compareTo('${b.category}${b.name}'),
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Item or category',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            FilterChip(
              label: const Text('Low stock only'),
              selected: _lowOnly,
              onSelected: (v) => setState(() => _lowOnly = v),
            ),
            if (keeper) Text('Stock value ${money(store.storeStockValue)}'),
            if (keeper)
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
                onPressed: () => _edit(context, store, null),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final i in items)
          Card(
            child: ListTile(
              title: Text(i.name),
              subtitle: Text(
                '${i.category} · reorder at ${i.reorderLevel} · cost '
                '${money(i.unitCost)}'
                '${i.billable ? ' · patient price ${money(i.patientPrice)}' : ''}',
              ),
              leading: i.isLowStock
                  ? const Icon(Icons.warning_amber, color: Colors.orange)
                  : const Icon(Icons.inventory_2_outlined),
              trailing: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${i.stock} ${i.unit}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: i.isLowStock ? Colors.orange : null,
                    ),
                  ),
                  if (keeper)
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'receive') _receive(context, store, i);
                        if (v == 'count') _count(context, store, i);
                        if (v == 'edit') _edit(context, store, i);
                        if (v == 'card') _card(context, store, i);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'receive',
                          child: Text('Receive stock'),
                        ),
                        PopupMenuItem(
                          value: 'count',
                          child: Text('Stock count'),
                        ),
                        PopupMenuItem(value: 'card', child: Text('Stock card')),
                        PopupMenuItem(value: 'edit', child: Text('Edit item')),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (items.isEmpty) const EmptyState('No matching items'),
      ],
    );
  }

  Future<void> _receive(
    BuildContext context,
    HospitalStore store,
    StoreItem i,
  ) async {
    final qty = TextEditingController();
    final cost = TextEditingController(text: i.unitCost.toString());
    final ref = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Receive ${i.name}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qty,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  suffixText: i.unit,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Unit cost'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ref,
                decoration: const InputDecoration(
                  labelText: 'Supplier / delivery note',
                ),
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
              final ok = await guarded(
                ctx,
                () => store.receiveStoreStock(
                  i.id,
                  int.tryParse(qty.text.trim()) ?? 0,
                  unitCost: double.tryParse(cost.text.trim()) ?? 0,
                  reference: ref.text,
                ),
                success: 'Stock received',
              );
              if (ok) nav.pop();
            },
            child: const Text('Receive'),
          ),
        ],
      ),
    );
  }

  Future<void> _count(
    BuildContext context,
    HospitalStore store,
    StoreItem i,
  ) async {
    final counted = TextEditingController(text: '${i.stock}');
    final reason = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stock count – ${i.name}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfoRow('On record', '${i.stock} ${i.unit}'),
              TextField(
                controller: counted,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Counted'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Reason for difference',
                ),
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
              final ok = await guarded(ctx, () async {
                final n = int.tryParse(counted.text.trim());
                if (n == null) throw HospitalException('Enter the count');
                await store.countStoreStock(i.id, n, reason: reason.text);
              }, success: 'Stock updated');
              if (ok) nav.pop();
            },
            child: const Text('Save count'),
          ),
        ],
      ),
    );
  }

  Future<void> _card(
    BuildContext context,
    HospitalStore store,
    StoreItem i,
  ) async {
    final moves = store.stockCard(i.id);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stock card – ${i.name}'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: moves.isEmpty
              ? const EmptyState('No movements yet')
              : ListView(
                  children: [
                    for (final m in moves)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          m.quantity >= 0
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          color: m.quantity >= 0 ? Colors.green : Colors.red,
                        ),
                        title: Text(
                          '${m.kind.label}: ${m.quantity > 0 ? '+' : ''}'
                          '${m.quantity} → ${m.balance}',
                        ),
                        subtitle: Text(
                          '${fmtDateTime(m.at)} · ${m.reference}'
                          '${m.by == null ? '' : ' · ${store.userName(m.by!)}'}',
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    HospitalStore store,
    StoreItem? existing,
  ) async {
    final name = TextEditingController(text: existing?.name);
    final unit = TextEditingController(text: existing?.unit ?? 'piece');
    final stock = TextEditingController(text: '${existing?.stock ?? 0}');
    final reorder = TextEditingController(
      text: '${existing?.reorderLevel ?? 0}',
    );
    final cost = TextEditingController(text: '${existing?.unitCost ?? 0}');
    final price = TextEditingController(text: '${existing?.patientPrice ?? 0}');
    var category = existing?.category ?? kStoreCategories.first;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Add store item' : 'Edit store item'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: kStoreCategories.contains(category)
                        ? category
                        : kStoreCategories.first,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final c in kStoreCategories)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (c) => setState(() => category = c!),
                  ),
                  const SizedBox(height: 12),
                  for (final (c, l, enabled) in [
                    (unit, 'Unit (piece, box, pack...)', true),
                    (stock, 'Opening stock', existing == null),
                    (reorder, 'Reorder level', true),
                    (cost, 'Unit cost', true),
                    (price, 'Patient price (0 = not billed)', true),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: c,
                        enabled: enabled,
                        decoration: InputDecoration(labelText: l),
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
                final ok = await guarded(ctx, () async {
                  final item =
                      (existing == null
                          ? null
                          : store.storeItemById(existing.id)) ??
                      StoreItem(
                        id: store.newId('ST'),
                        name: '',
                        category: category,
                        stock: int.tryParse(stock.text.trim()) ?? 0,
                      );
                  item
                    ..name = name.text.trim()
                    ..category = category
                    ..unit = unit.text.trim().isEmpty
                        ? 'piece'
                        : unit.text.trim()
                    ..reorderLevel = int.tryParse(reorder.text.trim()) ?? 0
                    ..unitCost = double.tryParse(cost.text.trim()) ?? 0
                    ..patientPrice = double.tryParse(price.text.trim()) ?? 0;
                  await store.upsertStoreItem(item);
                });
                if (ok) nav.pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
