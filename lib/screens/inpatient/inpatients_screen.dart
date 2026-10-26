import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';
import 'nursing_chart_screen.dart';
import '../../print/print_button.dart';
import '../../print/documents.dart';

/// Wards and admissions: who is admitted where, bed occupancy, transfers,
/// and discharge (which bills the room charges).
class InpatientsScreen extends StatelessWidget {
  const InpatientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final active = store.activeAdmissions;
    final discharged = store.admissions.where((a) => !a.isActive).toList()
      ..sort((a, b) => b.dischargedAt!.compareTo(a.dischargedAt!));
    final occupied = active.length;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showAdmitDialog(context),
          icon: const Icon(Icons.hotel),
          label: const Text('Admit patient'),
        ),
        body: Column(
          children: [
            TabBar(
              tabs: [
                Tab(text: 'Admitted ($occupied)'),
                Tab(text: 'Rooms ($occupied/${store.totalBeds} beds used)'),
                const Tab(text: 'Discharged'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  active.isEmpty
                      ? const EmptyState(
                          'No patients admitted',
                          icon: Icons.bed,
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          children: [
                            for (final a in active)
                              _AdmissionCard(admission: a),
                          ],
                        ),
                  const _Rooms(),
                  discharged.isEmpty
                      ? const EmptyState('No discharges yet')
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final a in discharged)
                              _AdmissionCard(admission: a),
                          ],
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdmissionCard extends StatelessWidget {
  const _AdmissionCard({required this.admission});

  final Admission admission;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final a = admission;
    final now = DateTime.now();
    final p = store.patientById(a.patientId);
    final dueDoses = store
        .dosesNeedingAttention()
        .where((x) => x.$1.id == a.id)
        .length;
    final upcoming = store
        .surgeriesFor(a.patientId)
        .where((s) => s.status == SurgeryStatus.scheduled)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PatientDetailScreen(patientId: a.patientId),
                      ),
                    ),
                    child: Text(
                      '${p?.name ?? 'Unknown'} · ${p?.mrn ?? ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                a.isActive
                    ? StatusChip(
                        a.currentStay.roomName,
                        color: Colors.indigo,
                        icon: Icons.bed,
                      )
                    : StatusChip(
                        'Discharged ${fmtDate(a.dischargedAt)}',
                        color: Colors.green,
                      ),
                if (!a.isActive)
                  PrintButton(
                    tooltip: 'Print discharge summary',
                    name: 'discharge-summary.pdf',
                    document: () => dischargeSummaryPdf(store, a),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Admitted ${fmtDateTime(a.admittedAt)} by '
              '${store.userName(a.doctorId)}'
              '${a.reason.isEmpty ? '' : ' · ${a.reason}'}',
            ),
            if (p != null && p.allergies.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: StatusChip(
                  'Allergies: ${p.allergies}',
                  color: Colors.red,
                  icon: Icons.warning,
                ),
              ),
            const SizedBox(height: 6),
            for (final (i, s) in a.stays.indexed)
              Text(
                '• ${s.roomName}: ${a.billableDays(now)[i]} day(s) × '
                '${money(s.dailyRate)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Text(
              '${a.isActive ? 'Room charges so far' : 'Room charges'}: '
              '${money(a.roomCharges(now))} (${a.totalDays(now)} day(s))',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final s in upcoming)
              Text(
                'Surgery: ${s.procedure}, ${fmtDateTime(s.scheduledAt)}',
                style: const TextStyle(color: Colors.deepPurple),
              ),
            if (a.dischargeSummary.isNotEmpty)
              Text('Discharge notes: ${a.dischargeSummary}'),
            if (a.isActive)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (store.latestVitals(a.id) case final v?)
                      newsChip(v)
                    else
                      const StatusChip(
                        'No observations yet',
                        color: Colors.blueGrey,
                      ),
                    if (dueDoses > 0)
                      StatusChip(
                        '$dueDoses dose(s) due',
                        color: Colors.orange,
                        icon: Icons.medication,
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.monitor_heart),
                    label: const Text('Nursing chart'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NursingChartScreen(admissionId: a.id),
                      ),
                    ),
                  ),
                  if (a.isActive) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Transfer'),
                      onPressed: () => _transfer(context, a),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.logout),
                      label: const Text('Discharge'),
                      onPressed: () => _discharge(context, a),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _transfer(BuildContext context, Admission a) async {
    final store = context.read<HospitalStore>();
    String? roomId;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Transfer ${store.patientName(a.patientId)}'),
          content: SizedBox(
            width: 400,
            child: _RoomPicker(
              value: roomId,
              exclude: a.currentStay.roomId,
              onChanged: (v) => setState(() => roomId = v),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: roomId == null
                  ? null
                  : () async {
                      final nav = Navigator.of(ctx);
                      if (await guarded(
                        ctx,
                        () => store.transferRoom(a.id, roomId!),
                        success: 'Patient transferred',
                      )) {
                        nav.pop();
                      }
                    },
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _discharge(BuildContext context, Admission a) async {
    final store = context.read<HospitalStore>();
    final summary = TextEditingController();
    final now = DateTime.now();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Discharge ${store.patientName(a.patientId)}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfoRow('Days', '${a.totalDays(now)}'),
              InfoRow('Room charges', money(a.roomCharges(now))),
              const SizedBox(height: 8),
              TextField(
                controller: summary,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Discharge summary',
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
              if (await guarded(
                ctx,
                () => store.dischargePatient(a.id, summary: summary.text),
                success: 'Discharged; room charges added to the bill',
              )) {
                nav.pop();
              }
            },
            child: const Text('Discharge'),
          ),
        ],
      ),
    );
  }
}

/// Room dropdown showing type, rate and free beds.
class _RoomPicker extends StatelessWidget {
  const _RoomPicker({
    required this.value,
    required this.onChanged,
    this.exclude,
  });

  final String? value;
  final String? exclude;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Room'),
      items: [
        for (final r in store.rooms)
          if (r.id != exclude)
            DropdownMenuItem(
              value: r.id,
              enabled: store.freeBeds(r.id) > 0,
              child: Text(
                '${r.name} · ${r.type} · ${money(r.dailyRate)}/day · '
                '${store.freeBeds(r.id)} free',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: store.freeBeds(r.id) > 0 ? null : Colors.grey,
                ),
              ),
            ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Admits a patient. [patientId] skips the patient picker (e.g. from a
/// consultation).
Future<void> showAdmitDialog(BuildContext context, {String? patientId}) async {
  final store = context.read<HospitalStore>();
  final patient = patientId != null
      ? store.patientById(patientId)
      : await pickPatient(context, store);
  if (patient == null || !context.mounted) return;
  final user = store.currentUser!;
  String? roomId;
  String? doctorId = user.role == UserRole.doctor ? user.id : null;
  final reason = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Admit ${patient.name}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoomPicker(
                value: roomId,
                onChanged: (v) => setState(() => roomId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: doctorId,
                decoration: const InputDecoration(
                  labelText: 'Admitting doctor',
                ),
                items: [
                  for (final d in store.doctors)
                    DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (v) => setState(() => doctorId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Reason / provisional diagnosis',
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
            onPressed: roomId == null || doctorId == null
                ? null
                : () async {
                    final nav = Navigator.of(ctx);
                    if (await guarded(
                      ctx,
                      () => store.admitPatient(
                        patientId: patient.id,
                        roomId: roomId!,
                        doctorId: doctorId!,
                        reason: reason.text,
                      ),
                      success: '${patient.name} admitted',
                    )) {
                      nav.pop();
                    }
                  },
            child: const Text('Admit'),
          ),
        ],
      ),
    ),
  );
}

class _Rooms extends StatelessWidget {
  const _Rooms();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final isAdmin = store.currentUser!.role == UserRole.admin;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in store.rooms)
              SizedBox(
                width: 240,
                child: Card(
                  child: InkWell(
                    onTap: isAdmin ? () => _editRoom(context, r) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text('${r.type} · ${money(r.dailyRate)}/day'),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: store.occupiedBeds(r.id) / r.beds,
                            color: store.freeBeds(r.id) == 0
                                ? Colors.red
                                : Colors.teal,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${store.occupiedBeds(r.id)} of ${r.beds} beds '
                            'occupied',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (isAdmin)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add room'),
                onPressed: () => _editRoom(context, null),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editRoom(BuildContext context, Room? existing) async {
    final store = context.read<HospitalStore>();
    final name = TextEditingController(text: existing?.name);
    final rate = TextEditingController(
      text: existing?.dailyRate.toStringAsFixed(2),
    );
    final beds = TextEditingController(text: '${existing?.beds ?? 1}');
    var type = existing?.type ?? kRoomTypes.first;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add room' : 'Edit ${existing.name}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name / number'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: kRoomTypes.contains(type) ? type : null,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final t in kRoomTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => type = v!,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Daily rate',
                  helperText: 'Applies to new admissions and transfers',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: beds,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Beds'),
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
                final r = double.tryParse(rate.text);
                final b = int.tryParse(beds.text);
                if (name.text.trim().isEmpty || r == null || b == null) {
                  throw HospitalException('Enter a name, rate and bed count');
                }
                if (existing != null && b < store.occupiedBeds(existing.id)) {
                  throw HospitalException(
                    '${existing.name} has ${store.occupiedBeds(existing.id)} '
                    'patients; transfer some first',
                  );
                }
                if (b < 1 || r < 0) {
                  throw HospitalException('Beds must be 1+ and rate 0+');
                }
                final room =
                    (existing == null ? null : store.roomById(existing.id)) ??
                    Room(
                      id: store.newId('RM'),
                      name: '',
                      type: type,
                      dailyRate: 0,
                    );
                room
                  ..name = name.text.trim()
                  ..type = type
                  ..dailyRate = r
                  ..beds = b;
                await store.upsertRoom(room);
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
