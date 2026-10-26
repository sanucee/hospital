import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../print/documents.dart';
import '../../print/print_button.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';

Color bloodRequestColor(BloodRequestStatus s) => switch (s) {
  BloodRequestStatus.pending => Colors.orange,
  BloodRequestStatus.reserved => Colors.blue,
  BloodRequestStatus.issued => Colors.green,
  BloodRequestStatus.cancelled => Colors.grey,
};

/// Lets a doctor ask the blood bank for blood for [patientId].
Future<void> showBloodRequestDialog(
  BuildContext context, {
  String? patientId,
  String? consultationId,
}) async {
  final store = context.read<HospitalStore>();
  final patient = patientId != null
      ? store.patientById(patientId)
      : await pickPatient(context, store);
  if (patient == null || !context.mounted) return;
  final user = store.currentUser!;
  var component = BloodComponent.redCells;
  var urgency = kBloodUrgencies.first;
  String? doctorId = user.role == UserRole.doctor ? user.id : null;
  final units = TextEditingController(text: '1');
  final indication = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Request blood – ${patient.name}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InfoRow(
                  'Blood group',
                  patient.bloodGroup.isEmpty
                      ? 'Not known – the lab will group the sample'
                      : patient.bloodGroup,
                ),
                if (doctorId == null || user.role != UserRole.doctor)
                  DropdownButtonFormField<String>(
                    initialValue: doctorId,
                    decoration: const InputDecoration(
                      labelText: 'Requesting doctor',
                    ),
                    items: [
                      for (final d in store.doctors)
                        DropdownMenuItem(value: d.id, child: Text(d.name)),
                    ],
                    onChanged: (d) => setState(() => doctorId = d),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BloodComponent>(
                  initialValue: component,
                  decoration: const InputDecoration(labelText: 'Component'),
                  items: [
                    for (final c in BloodComponent.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (c) => setState(() => component = c!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: units,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Units'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: urgency,
                        decoration: const InputDecoration(labelText: 'Urgency'),
                        items: [
                          for (final u in kBloodUrgencies)
                            DropdownMenuItem(value: u, child: Text(u)),
                        ],
                        onChanged: (u) => setState(() => urgency = u!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: indication,
                  decoration: const InputDecoration(
                    labelText: 'Indication (e.g. Hb 6.2 g/dL, bleeding)',
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
                if (doctorId == null) {
                  throw HospitalException('Choose the requesting doctor');
                }
                await store.requestBlood(
                  patientId: patient.id,
                  doctorId: doctorId!,
                  component: component,
                  units: int.tryParse(units.text) ?? 0,
                  urgency: urgency,
                  indication: indication.text,
                  consultationId: consultationId,
                );
              }, success: 'Request sent to the blood bank');
              if (ok) nav.pop();
            },
            child: const Text('Send request'),
          ),
        ],
      ),
    ),
  );
}

class BloodBankScreen extends StatelessWidget {
  const BloodBankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final open = store.openBloodRequests;
    final quarantine = store.bloodUnits
        .where((u) => u.status == BloodUnitStatus.quarantine)
        .length;
    final canRequest = {
      UserRole.admin,
      UserRole.doctor,
    }.contains(store.currentUser?.role);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        floatingActionButton: canRequest
            ? FloatingActionButton.extended(
                onPressed: () => showBloodRequestDialog(context),
                icon: const Icon(Icons.bloodtype),
                label: const Text('Request blood'),
              )
            : null,
        body: Column(
          children: [
            TabBar(
              tabs: [
                Tab(text: 'Requests (${open.length})'),
                Tab(
                  text:
                      'Stock (${store.usableBloodUnits().length})'
                      '${quarantine > 0 ? ' · $quarantine to screen' : ''}',
                ),
                Tab(text: 'Donors (${store.bloodDonors.length})'),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: [_RequestsTab(), _StockTab(), _DonorsTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isBloodBank(HospitalStore s) =>
    {UserRole.admin, UserRole.labTechnician}.contains(s.currentUser?.role);

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final open = store.openBloodRequests;
    final recent = store.bloodRequests.where((r) => !r.isOpen).toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    if (open.isEmpty && recent.isEmpty) {
      return const EmptyState('No blood requests', icon: Icons.bloodtype);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        for (final r in open) _RequestCard(request: r),
        if (recent.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Text(
              'Completed and cancelled',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final r in recent.take(30)) _RequestCard(request: r),
        ],
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final r = request;
    final p = store.patientById(r.patientId);
    final bank = _isBloodBank(store);
    final units = [for (final id in r.unitIds) ?store.bloodUnitById(id)];
    return Card(
      shape: r.isOpen && r.urgency == 'Emergency'
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
                if (r.urgency != 'Routine')
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: StatusChip(
                      r.urgency.toUpperCase(),
                      color: r.urgency == 'Emergency'
                          ? Colors.red
                          : Colors.orange,
                    ),
                  ),
                Expanded(
                  child: Text(
                    '${r.units} × ${r.component.label}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusChip(r.status.label, color: bloodRequestColor(r.status)),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PatientDetailScreen(patientId: r.patientId),
                ),
              ),
              child: Text(
                '${p?.name ?? 'Unknown'} · ${p?.mrn} · Group '
                '${(p?.bloodGroup.isEmpty ?? true) ? 'not known' : p!.bloodGroup}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Text(
              'Requested by ${store.userName(r.doctorId)} at '
              '${fmtDateTime(r.requestedAt)}'
              '${r.admissionId == null ? '' : ' · inpatient'}',
            ),
            Text('Indication: ${r.indication}'),
            if (units.isNotEmpty)
              Text(
                'Units: ${units.map((u) => '${u.unitNumber} (${u.bloodGroup})').join(', ')}',
              ),
            if (r.cancelReason.isNotEmpty) Text('Cancelled: ${r.cancelReason}'),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (bank &&
                      r.status == BloodRequestStatus.pending &&
                      (p?.bloodGroup.isEmpty ?? true))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.science),
                      label: const Text('Record blood group'),
                      onPressed: () => _group(context, store, r.patientId),
                    ),
                  if (bank && r.status == BloodRequestStatus.pending)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.compare_arrows),
                      label: const Text('Cross-match'),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _CrossmatchDialog(request: r),
                      ),
                    ),
                  if (bank && r.status == BloodRequestStatus.reserved)
                    FilledButton.icon(
                      icon: const Icon(Icons.outbox),
                      label: const Text('Issue'),
                      onPressed: () => guarded(
                        context,
                        () => store.issueBlood(r.id),
                        success: 'Blood issued and billed',
                      ),
                    ),
                  if (r.unitIds.isNotEmpty)
                    PrintButton(
                      tooltip: 'Print issue form',
                      name: 'blood-issue.pdf',
                      document: () => bloodIssuePdf(store, r),
                    ),
                  // Doctors may only withdraw a request before cross-match.
                  if (bank && r.isOpen ||
                      store.currentUser?.id == r.doctorId &&
                          r.status == BloodRequestStatus.pending)
                    TextButton(
                      onPressed: () => _cancel(context, store, r),
                      child: const Text('Cancel request'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _group(
    BuildContext context,
    HospitalStore store,
    String patientId,
  ) async {
    final group = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Patient blood group'),
        children: [
          for (final g in kBloodGroups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g),
              child: Text(g),
            ),
        ],
      ),
    );
    if (group == null || !context.mounted) return;
    await guarded(
      context,
      () => store.setPatientBloodGroup(patientId, group),
      success: 'Blood group recorded',
    );
  }

  Future<void> _cancel(
    BuildContext context,
    HospitalStore store,
    BloodRequest r,
  ) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel blood request'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await guarded(
      context,
      () => store.cancelBloodRequest(r.id, reason: reason.text),
      success: 'Request cancelled; reserved units returned to stock',
    );
  }
}

class _CrossmatchDialog extends StatefulWidget {
  const _CrossmatchDialog({required this.request});

  final BloodRequest request;

  @override
  State<_CrossmatchDialog> createState() => _CrossmatchDialogState();
}

class _CrossmatchDialogState extends State<_CrossmatchDialog> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final r = widget.request;
    final group = store.patientById(r.patientId)?.bloodGroup ?? '';
    final candidates = group.isEmpty
        ? <BloodUnit>[]
        : store.compatibleUnits(r.id);
    return AlertDialog(
      title: Text('Cross-match – ${r.units} × ${r.component.label}'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: group.isEmpty
            ? const EmptyState("Record the patient's blood group first")
            : candidates.isEmpty
            ? EmptyState(
                'No compatible ${r.component.label.toLowerCase()} in stock '
                'for group $group',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Patient group $group. Select ${r.units} compatible '
                    'unit(s) that passed the cross-match; oldest are listed '
                    'first.',
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final u in candidates)
                          CheckboxListTile(
                            dense: true,
                            value: _selected.contains(u.id),
                            title: Text('${u.unitNumber} · ${u.bloodGroup}'),
                            subtitle: Text(
                              '${u.volumeMl} ml · expires '
                              '${fmtDate(u.expiresAt)} · ${u.source}',
                            ),
                            secondary: u.bloodGroup == group
                                ? const StatusChip(
                                    'Same group',
                                    color: Colors.green,
                                  )
                                : const StatusChip(
                                    'Compatible',
                                    color: Colors.blue,
                                  ),
                            onChanged: (v) => setState(
                              () => v!
                                  ? _selected.add(u.id)
                                  : _selected.remove(u.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        Text('${_selected.length} of ${r.units}'),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.length != r.units
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  final ok = await guarded(
                    context,
                    () => store.crossmatchBlood(r.id, _selected.toList()),
                    success: 'Units reserved; the doctor has been told',
                  );
                  if (ok) nav.pop();
                },
          child: const Text('Reserve units'),
        ),
      ],
    );
  }
}

class _StockTab extends StatelessWidget {
  const _StockTab();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final bank = _isBloodBank(store);
    final stock = store.bloodStock;
    final quarantine = store.bloodUnits
        .where((u) => u.status == BloodUnitStatus.quarantine)
        .toList();
    final expiring = store.expiringBloodUnits();
    final shelf = [
      ...store.bloodUnits.where(
        (u) =>
            u.status == BloodUnitStatus.available ||
            u.status == BloodUnitStatus.reserved,
      ),
    ]..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
    final now = DateTime.now();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        SectionCard(
          title: 'Usable units by group',
          icon: Icons.grid_on,
          trailing: bank
              ? FilledButton.tonalIcon(
                  icon: const Icon(Icons.add),
                  label: const Text('Receive units'),
                  onPressed: () => _receive(context, store),
                )
              : null,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              columns: [
                const DataColumn(label: Text('Group')),
                for (final c in BloodComponent.values)
                  DataColumn(label: Text(c.label), numeric: true),
              ],
              rows: [
                for (final g in kBloodGroups)
                  DataRow(
                    cells: [
                      DataCell(Text(g)),
                      for (final c in BloodComponent.values)
                        DataCell(
                          Text(
                            '${stock[g]![c]}',
                            style: TextStyle(
                              color: stock[g]![c] == 0 ? Colors.grey : null,
                              fontWeight: stock[g]![c] == 0
                                  ? null
                                  : FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (quarantine.isNotEmpty)
          SectionCard(
            title: 'Awaiting screening (${quarantine.length})',
            icon: Icons.biotech,
            child: Column(
              children: [
                for (final u in quarantine)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${u.unitNumber} · ${u.bloodGroup} · ${u.component.label}',
                    ),
                    subtitle: Text(
                      'Collected ${fmtDateTime(u.collectedAt)}'
                      '${u.donorId == null ? '' : ' from ${store.bloodDonorById(u.donorId!)?.name ?? 'donor'}'}',
                    ),
                    trailing: bank
                        ? Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Screening passed',
                                icon: const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                ),
                                onPressed: () => guarded(
                                  context,
                                  () =>
                                      store.screenBloodUnit(u.id, passed: true),
                                  success: '${u.unitNumber} added to stock',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Screening failed',
                                icon: const Icon(
                                  Icons.cancel,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  final reason = await _askReason(
                                    context,
                                    'Failed screening',
                                    hint: 'e.g. HBsAg reactive',
                                  );
                                  if (reason == null || !context.mounted) {
                                    return;
                                  }
                                  await guarded(
                                    context,
                                    () => store.screenBloodUnit(
                                      u.id,
                                      passed: false,
                                      reason: reason,
                                    ),
                                    success: '${u.unitNumber} discarded',
                                  );
                                },
                              ),
                            ],
                          )
                        : null,
                  ),
              ],
            ),
          ),
        if (expiring.isNotEmpty)
          SectionCard(
            title: 'Expired or expiring within 3 days (${expiring.length})',
            icon: Icons.warning_amber,
            child: Text(
              expiring
                  .map(
                    (u) =>
                        '${u.unitNumber} ${u.bloodGroup} ${u.component.label} – '
                        '${u.isExpired(now) ? 'EXPIRED' : fmtDate(u.expiresAt)}',
                  )
                  .join('\n'),
            ),
          ),
        SectionCard(
          title: 'Units on the shelf (${shelf.length})',
          icon: Icons.inventory,
          child: shelf.isEmpty
              ? const Text('No units in stock.')
              : Column(
                  children: [
                    for (final u in shelf)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.withValues(alpha: 0.12),
                          foregroundColor: Colors.red,
                          child: Text(
                            u.bloodGroup,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        title: Text('${u.unitNumber} · ${u.component.label}'),
                        subtitle: Text(
                          '${u.volumeMl} ml · ${u.source} · expires '
                          '${fmtDate(u.expiresAt)}',
                          style: TextStyle(
                            color: u.isExpired(now) ? Colors.red : null,
                          ),
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusChip(
                              u.isExpired(now) ? 'Expired' : u.status.label,
                              color: u.isExpired(now)
                                  ? Colors.red
                                  : u.status == BloodUnitStatus.reserved
                                  ? Colors.blue
                                  : Colors.green,
                            ),
                            if (bank)
                              IconButton(
                                tooltip: 'Discard',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final reason = await _askReason(
                                    context,
                                    'Discard ${u.unitNumber}',
                                    hint: 'e.g. expired, bag damaged',
                                  );
                                  if (reason == null || !context.mounted) {
                                    return;
                                  }
                                  await guarded(
                                    context,
                                    () => store.discardBloodUnit(u.id, reason),
                                    success: '${u.unitNumber} discarded',
                                  );
                                },
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

  Future<void> _receive(BuildContext context, HospitalStore store) async {
    var group = kBloodGroups.first;
    var component = BloodComponent.redCells;
    final count = TextEditingController(text: '1');
    final source = TextEditingController(text: 'National Blood Service');
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Receive screened units'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: group,
                  decoration: const InputDecoration(labelText: 'Blood group'),
                  items: [
                    for (final g in kBloodGroups)
                      DropdownMenuItem(value: g, child: Text(g)),
                  ],
                  onChanged: (g) => setState(() => group = g!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BloodComponent>(
                  initialValue: component,
                  decoration: const InputDecoration(labelText: 'Component'),
                  items: [
                    for (final c in BloodComponent.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (c) => setState(() => component = c!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: count,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Number of units',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: source,
                  decoration: const InputDecoration(labelText: 'Supplied by'),
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
                  () => store.receiveBloodUnits(
                    bloodGroup: group,
                    component: component,
                    count: int.tryParse(count.text) ?? 0,
                    source: source.text,
                  ),
                  success: 'Units added to stock',
                );
                if (ok) nav.pop();
              },
              child: const Text('Add to stock'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _askReason(
  BuildContext context,
  String title, {
  String hint = '',
}) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: 'Reason', hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return ok == true ? c.text : null;
}

class _DonorsTab extends StatelessWidget {
  const _DonorsTab();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final bank = _isBloodBank(store);
    final donors = [...store.bloodDonors]
      ..sort((a, b) => a.name.compareTo(b.name));
    final today = DateTime.now();
    return Scaffold(
      floatingActionButton: bank
          ? FloatingActionButton.extended(
              heroTag: 'add-donor',
              onPressed: () => _edit(context, store, null),
              icon: const Icon(Icons.person_add),
              label: const Text('Add donor'),
            )
          : null,
      body: donors.isEmpty
          ? const EmptyState(
              'No donors registered',
              icon: Icons.volunteer_activism,
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final d in donors)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.red.withValues(alpha: 0.12),
                      foregroundColor: Colors.red,
                      child: Text(
                        d.bloodGroup,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    title: Text(d.name),
                    subtitle: Text(
                      [
                        if (d.phone.isNotEmpty) d.phone,
                        'Last donated ${fmtDate(d.lastDonationAt)}',
                        d.canDonateOn(today)
                            ? 'Can donate now'
                            : 'Next ${fmtDate(d.nextEligible())}',
                      ].join(' · '),
                    ),
                    onTap: bank ? () => _edit(context, store, d) : null,
                    trailing: bank
                        ? FilledButton.tonal(
                            onPressed: d.canDonateOn(today)
                                ? () => guarded(
                                    context,
                                    () => store.recordDonation(d.id),
                                    success:
                                        'Donation recorded; unit awaiting '
                                        'screening',
                                  )
                                : null,
                            child: const Text('Record donation'),
                          )
                        : null,
                  ),
              ],
            ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    HospitalStore store,
    BloodDonor? existing,
  ) async {
    final name = TextEditingController(text: existing?.name);
    final phone = TextEditingController(text: existing?.phone);
    final notes = TextEditingController(text: existing?.notes);
    var group = existing?.bloodGroup ?? kBloodGroups.first;
    var gender = existing?.gender.isNotEmpty == true
        ? existing!.gender
        : 'Male';
    var deferred = existing?.deferredUntil;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Add donor' : 'Edit donor'),
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
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: kBloodGroups.contains(group)
                              ? group
                              : kBloodGroups.first,
                          decoration: const InputDecoration(
                            labelText: 'Blood group',
                          ),
                          items: [
                            for (final g in kBloodGroups)
                              DropdownMenuItem(value: g, child: Text(g)),
                          ],
                          onChanged: (g) => setState(() => group = g!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: gender,
                          decoration: const InputDecoration(labelText: 'Sex'),
                          items: [
                            for (final g in ['Male', 'Female'])
                              DropdownMenuItem(value: g, child: Text(g)),
                          ],
                          onChanged: (g) => setState(() => gender = g!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      deferred == null
                          ? 'Not deferred'
                          : 'Deferred until ${fmtDate(deferred)}',
                    ),
                    trailing: Wrap(
                      children: [
                        if (deferred != null)
                          IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => deferred = null),
                          ),
                        IconButton(
                          tooltip: 'Defer donor',
                          icon: const Icon(Icons.event_busy),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: DateTime.now().add(
                                const Duration(days: 30),
                              ),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) setState(() => deferred = d);
                          },
                        ),
                      ],
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
                final d =
                    (existing == null
                        ? null
                        : store.bloodDonorById(existing.id)) ??
                    BloodDonor(
                      id: store.newId('DON'),
                      name: '',
                      bloodGroup: group,
                    );
                final ok = await guarded(ctx, () {
                  d
                    ..name = name.text.trim()
                    ..bloodGroup = group
                    ..gender = gender
                    ..phone = phone.text.trim()
                    ..notes = notes.text.trim()
                    ..deferredUntil = deferred;
                  return store.upsertBloodDonor(d);
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
