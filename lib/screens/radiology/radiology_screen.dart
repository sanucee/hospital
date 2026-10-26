import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../print/documents.dart';
import '../../print/print_button.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';

Color imagingColor(ImagingOrder o) => switch (o.status) {
  ImagingStatus.ordered => Colors.orange,
  ImagingStatus.scheduled => Colors.teal,
  ImagingStatus.performed => Colors.blue,
  ImagingStatus.reported => o.abnormal ? Colors.red : Colors.green,
  ImagingStatus.cancelled => Colors.grey,
};

/// The imaging department: requests to book, perform and report.
class RadiologyScreen extends StatelessWidget {
  const RadiologyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final queue = store.imagingQueue;
    final done = store.imagingOrders.where((o) => !o.isPending).toList()
      ..sort(
        (a, b) => (b.reportedAt ?? b.orderedAt).compareTo(
          a.reportedAt ?? a.orderedAt,
        ),
      );
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: 'Work list (${queue.length})'),
              Tab(text: 'Reported (${done.length})'),
              const Tab(text: 'Examinations'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                queue.isEmpty
                    ? const EmptyState(
                        'No imaging requests waiting',
                        icon: Icons.monitor_heart,
                      )
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [for (final o in queue) _OrderCard(order: o)],
                      ),
                done.isEmpty
                    ? const EmptyState('No reports yet')
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [for (final o in done) _OrderCard(order: o)],
                      ),
                const _Catalogue(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final ImagingOrder order;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final o = order;
    final p = store.patientById(o.patientId);
    final study = store.imagingStudyById(o.studyId);
    final canAct = {
      UserRole.admin,
      UserRole.radiographer,
    }.contains(store.currentUser?.role);
    final notYetDone =
        o.status == ImagingStatus.ordered ||
        o.status == ImagingStatus.scheduled;
    return Card(
      shape: o.urgent && o.isPending
          ? RoundedRectangleBorder(
              side: const BorderSide(color: Colors.red, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (o.urgent)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: StatusChip('URGENT', color: Colors.red),
                  ),
                Expanded(
                  child: Text(
                    '${o.studyName} · ${o.modality}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusChip(o.status.label, color: imagingColor(o)),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PatientDetailScreen(patientId: o.patientId),
                ),
              ),
              child: Text(
                '${p?.name ?? 'Unknown'} · ${p?.mrn} · ${p?.age}y ${p?.gender}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Text(
              'Requested by ${store.userName(o.doctorId)} at '
              '${fmtDateTime(o.orderedAt)}',
            ),
            if (o.clinicalNotes.isNotEmpty)
              Text('Clinical details: ${o.clinicalNotes}'),
            if (study != null && study.preparation.isNotEmpty && notYetDone)
              Text('Preparation: ${study.preparation}'),
            if (o.scheduledAt != null && notYetDone)
              Text('Booked for ${fmtDateTime(o.scheduledAt)}'),
            if (o.performedAt != null)
              Text(
                'Performed ${fmtDateTime(o.performedAt)}'
                '${o.radiographerId == null ? '' : ' by ${store.userName(o.radiographerId!)}'}',
              ),
            if (o.status == ImagingStatus.reported) ...[
              const Divider(),
              if (o.findings.isNotEmpty) Text('Findings: ${o.findings}'),
              Text(
                'Impression: ${o.impression}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: o.abnormal ? Colors.red : null,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Reported ${fmtDateTime(o.reportedAt)}'
                      '${o.reportedBy == null ? '' : ' by ${store.userName(o.reportedBy!)}'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  PrintButton(
                    tooltip: 'Print report',
                    name: 'imaging-report.pdf',
                    document: () => imagingReportPdf(store, o),
                  ),
                ],
              ),
            ],
            if (canAct && o.isPending)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (notYetDone) ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.event),
                        label: Text(
                          o.scheduledAt == null ? 'Book time' : 'Rebook',
                        ),
                        onPressed: () => _book(context, store, o),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.camera),
                        label: const Text('Mark performed'),
                        onPressed: () => guarded(
                          context,
                          () => store.markImagingPerformed(o.id),
                          success: 'Study performed; ready to report',
                        ),
                      ),
                      TextButton(
                        onPressed: () => guarded(
                          context,
                          () => store.cancelImagingOrder(o.id),
                          success: 'Request cancelled and removed from bill',
                        ),
                        child: const Text('Cancel request'),
                      ),
                    ],
                    if (o.status == ImagingStatus.performed)
                      FilledButton.icon(
                        icon: const Icon(Icons.description),
                        label: const Text('Write report'),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => _ReportDialog(order: o),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _book(
    BuildContext context,
    HospitalStore store,
    ImagingOrder o,
  ) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: o.scheduledAt ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null || !context.mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(o.scheduledAt ?? now),
    );
    if (t == null || !context.mounted) return;
    await guarded(
      context,
      () => store.scheduleImaging(
        o.id,
        DateTime(d.year, d.month, d.day, t.hour, t.minute),
      ),
      success: 'Study booked',
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.order});

  final ImagingOrder order;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _findings = TextEditingController();
  final _impression = TextEditingController();
  bool _abnormal = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report – ${widget.order.studyName}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.order.clinicalNotes.isNotEmpty)
              InfoRow('Clinical details', widget.order.clinicalNotes),
            TextField(
              controller: _findings,
              autofocus: true,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Findings'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _impression,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Impression'),
            ),
            CheckboxListTile(
              value: _abnormal,
              title: const Text('Flag as abnormal'),
              subtitle: const Text('The doctor is alerted with high priority'),
              onChanged: (v) => setState(() => _abnormal = v!),
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
              () => context.read<HospitalStore>().reportImaging(
                widget.order.id,
                findings: _findings.text,
                impression: _impression.text,
                abnormal: _abnormal,
              ),
              success: 'Report sent to the doctor',
            );
            if (ok) nav.pop();
          },
          child: const Text('Submit report'),
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
    final canEdit = {
      UserRole.admin,
      UserRole.radiographer,
    }.contains(store.currentUser?.role);
    final studies = [...store.imagingStudies]
      ..sort(
        (a, b) => '${a.modality}${a.name}'.compareTo('${b.modality}${b.name}'),
      );
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Add examination'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final s in studies)
            ListTile(
              title: Text(s.name),
              subtitle: Text(
                [
                  s.modality,
                  if (s.bodyPart.isNotEmpty) s.bodyPart,
                  if (s.preparation.isNotEmpty) 'Prep: ${s.preparation}',
                ].join(' · '),
              ),
              trailing: Text(money(s.price)),
              onTap: canEdit ? () => _edit(context, s) : null,
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, ImagingStudy? existing) async {
    final store = context.read<HospitalStore>();
    final name = TextEditingController(text: existing?.name);
    final price = TextEditingController(text: existing?.price.toString());
    final part = TextEditingController(text: existing?.bodyPart);
    final prep = TextEditingController(text: existing?.preparation);
    var modality = existing?.modality ?? kModalities.first;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing == null ? 'Add examination' : 'Edit examination',
          ),
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
                    initialValue: kModalities.contains(modality)
                        ? modality
                        : kModalities.first,
                    decoration: const InputDecoration(labelText: 'Modality'),
                    items: [
                      for (final m in kModalities)
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: (m) => setState(() => modality = m!),
                  ),
                  const SizedBox(height: 12),
                  for (final (c, l) in [
                    (price, 'Price'),
                    (part, 'Body part'),
                    (prep, 'Patient preparation'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: c,
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
                  final p = double.tryParse(price.text);
                  if (p == null) throw HospitalException('Enter a valid price');
                  final s =
                      (existing == null
                          ? null
                          : store.imagingStudyById(existing.id)) ??
                      ImagingStudy(
                        id: store.newId('IS'),
                        name: '',
                        modality: modality,
                        price: 0,
                      );
                  s
                    ..name = name.text.trim()
                    ..modality = modality
                    ..price = p
                    ..bodyPart = part.text.trim()
                    ..preparation = prep.text.trim();
                  await store.upsertImagingStudy(s);
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
