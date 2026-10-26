import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';

class LabScreen extends StatelessWidget {
  const LabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final queue = store.labQueue;
    final done = store.labOrders
        .where((o) =>
            o.status == LabOrderStatus.completed ||
            o.status == LabOrderStatus.cancelled)
        .toList()
      ..sort((a, b) => (b.completedAt ?? b.orderedAt)
          .compareTo(a.completedAt ?? a.orderedAt));

    return DefaultTabController(
      length: 3,
      child: Column(children: [
        TabBar(tabs: [
          Tab(text: 'Work queue (${queue.length})'),
          Tab(text: 'Completed (${done.length})'),
          const Tab(text: 'Test catalogue'),
        ]),
        Expanded(
          child: TabBarView(children: [
            queue.isEmpty
                ? const EmptyState('No pending tests', icon: Icons.biotech)
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final o in queue) _OrderCard(order: o),
                  ]),
            done.isEmpty
                ? const EmptyState('No completed tests yet')
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final o in done) _OrderCard(order: o),
                  ]),
            const _Catalogue(),
          ]),
        ),
      ]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final LabOrder order;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final o = order;
    final p = store.patientById(o.patientId);
    final test = store.labTestById(o.testId);
    return Card(
      shape: o.urgent && o.status != LabOrderStatus.completed
          ? RoundedRectangleBorder(
              side: const BorderSide(color: Colors.red, width: 1.5),
              borderRadius: BorderRadius.circular(12))
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (o.urgent)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: StatusChip('URGENT', color: Colors.red),
              ),
            Expanded(
              child: Text(o.testName,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            StatusChip.lab(o),
          ]),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PatientDetailScreen(patientId: o.patientId))),
            child: Text(
                '${p?.name ?? 'Unknown'} · ${p?.mrn} · '
                '${p?.age}y ${p?.gender}',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline)),
          ),
          Text('Requested by ${store.userName(o.doctorId)} at '
              '${fmtDateTime(o.orderedAt)}'),
          Text('Sample: ${test?.sampleType ?? '—'} · '
              'Reference: ${test?.referenceRange ?? '—'} ${test?.unit ?? ''}'),
          if (o.clinicalNotes.isNotEmpty) Text('Notes: ${o.clinicalNotes}'),
          if (o.status == LabOrderStatus.completed) ...[
            const Divider(),
            Text('Result: ${o.result}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: o.abnormal ? Colors.red : null)),
            if (o.resultRemarks.isNotEmpty) Text('Remarks: ${o.resultRemarks}'),
            Text('Reported ${fmtDateTime(o.completedAt)}'
                '${o.technicianId == null ? '' : ' by ${store.userName(o.technicianId!)}'}'),
          ],
          if (o.status == LabOrderStatus.ordered ||
              o.status == LabOrderStatus.sampleCollected)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, children: [
                if (o.status == LabOrderStatus.ordered)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.colorize),
                    label: const Text('Collect sample'),
                    onPressed: () => guarded(
                        context, () => store.collectSample(o.id),
                        success: 'Sample collected'),
                  ),
                FilledButton.icon(
                  icon: const Icon(Icons.assignment_turned_in),
                  label: const Text('Enter result'),
                  onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _ResultDialog(order: o, test: test)),
                ),
                TextButton(
                  onPressed: () => guarded(
                      context, () => store.cancelLabOrder(o.id),
                      success: 'Order cancelled and removed from bill'),
                  child: const Text('Cancel order'),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _ResultDialog extends StatefulWidget {
  const _ResultDialog({required this.order, this.test});

  final LabOrder order;
  final LabTest? test;

  @override
  State<_ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<_ResultDialog> {
  final _result = TextEditingController();
  final _remarks = TextEditingController();
  bool _abnormal = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.test;
    return AlertDialog(
      title: Text('Result – ${widget.order.testName}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (t != null)
            InfoRow('Reference', '${t.referenceRange} ${t.unit}'.trim()),
          const SizedBox(height: 8),
          TextField(
            controller: _result,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Result',
              suffixText: t?.unit,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remarks,
            decoration: const InputDecoration(labelText: 'Remarks'),
          ),
          CheckboxListTile(
            value: _abnormal,
            title: const Text('Flag as abnormal'),
            subtitle: const Text('The doctor is alerted with high priority'),
            onChanged: (v) => setState(() => _abnormal = v!),
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
                () => context.read<HospitalStore>().enterLabResult(
                      labOrderId: widget.order.id,
                      result: _result.text,
                      remarks: _remarks.text,
                      abnormal: _abnormal,
                    ),
                success: 'Result sent to the doctor');
            if (ok) nav.pop();
          },
          child: const Text('Submit result'),
        ),
      ],
    );
  }
}

class _Catalogue extends StatelessWidget {
  const _Catalogue();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final tests = [...store.labTests]
      ..sort((a, b) => '${a.category}${a.name}'.compareTo('${b.category}${b.name}'));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editTest(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Add test'),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
        for (final t in tests)
          ListTile(
            title: Text(t.name),
            subtitle: Text('${t.category} · ${t.sampleType} · '
                'Ref ${t.referenceRange} ${t.unit}'),
            trailing: Text(money(t.price)),
            onTap: () => _editTest(context, t),
          ),
      ]),
    );
  }

  Future<void> _editTest(BuildContext context, LabTest? existing) async {
    final store = context.read<HospitalStore>();
    final name = TextEditingController(text: existing?.name);
    final category = TextEditingController(text: existing?.category);
    final price = TextEditingController(text: existing?.price.toString());
    final unit = TextEditingController(text: existing?.unit);
    final range = TextEditingController(text: existing?.referenceRange);
    final sample =
        TextEditingController(text: existing?.sampleType ?? 'Blood');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add lab test' : 'Edit lab test'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (c, l) in [
                (name, 'Name'),
                (category, 'Category'),
                (price, 'Price'),
                (unit, 'Unit'),
                (range, 'Reference range'),
                (sample, 'Sample type'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                      controller: c,
                      decoration: InputDecoration(labelText: l)),
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
                final t = (existing == null
                        ? null
                        : store.labTestById(existing.id)) ??
                    LabTest(
                        id: store.newId('LT'),
                        name: '',
                        category: '',
                        price: 0);
                t
                  ..name = name.text.trim()
                  ..category = category.text.trim().isEmpty
                      ? 'General'
                      : category.text.trim()
                  ..price = p
                  ..unit = unit.text.trim()
                  ..referenceRange = range.text.trim()
                  ..sampleType = sample.text.trim();
                await store.upsertLabTest(t);
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
