import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';
import 'consultation_screen.dart';

class DoctorQueueScreen extends StatefulWidget {
  const DoctorQueueScreen({super.key});

  @override
  State<DoctorQueueScreen> createState() => _DoctorQueueScreenState();
}

class _DoctorQueueScreenState extends State<DoctorQueueScreen> {
  String? _doctorId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final user = store.currentUser!;
    final isDoctor = user.role == UserRole.doctor;
    final doctorId =
        isDoctor ? user.id : (_doctorId ?? store.doctors.firstOrNull?.id);
    if (doctorId == null) return const EmptyState('No doctors configured');

    final queue = store.doctorQueue(doctorId);
    final results = store.unreviewedResults(doctorId);
    final open = store.consultations
        .where((c) => c.doctorId == doctorId && c.isOpen)
        .toList();

    return DefaultTabController(
      length: 3,
      child: Column(children: [
        if (!isDoctor)
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              initialValue: doctorId,
              decoration: const InputDecoration(labelText: 'Viewing queue of'),
              items: [
                for (final d in store.doctors)
                  DropdownMenuItem(value: d.id, child: Text(d.name)),
              ],
              onChanged: (v) => setState(() => _doctorId = v),
            ),
          ),
        TabBar(tabs: [
          Tab(text: 'Waiting (${queue.length})'),
          Tab(text: 'New lab results (${results.length})'),
          Tab(text: 'Open visits (${open.length})'),
        ]),
        Expanded(
          child: TabBarView(children: [
            _queueList(context, store, queue, isDoctor),
            _resultsList(context, store, results, isDoctor),
            _openList(context, store, open, isDoctor),
          ]),
        ),
      ]),
    );
  }

  Widget _queueList(BuildContext context, HospitalStore store,
      List<Appointment> queue, bool isDoctor) {
    if (queue.isEmpty) {
      return const EmptyState('No patients waiting', icon: Icons.event_seat);
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final a in queue)
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Text('#${a.tokenNumber ?? '-'}')),
            title: Text(store.patientName(a.patientId)),
            subtitle: Text(a.reason.isEmpty ? 'No reason given' : a.reason),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip.appointment(a.status),
                if (isDoctor)
                  FilledButton(
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final c = await store.startConsultation(
                        patientId: a.patientId,
                        doctorId: a.doctorId,
                        appointmentId: a.id,
                      );
                      nav.push(MaterialPageRoute(
                          builder: (_) =>
                              ConsultationScreen(consultationId: c.id)));
                    },
                    child: Text(a.status == AppointmentStatus.inConsultation
                        ? 'Continue'
                        : 'Start'),
                  ),
              ],
            ),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        PatientDetailScreen(patientId: a.patientId))),
          ),
        ),
    ]);
  }

  Widget _resultsList(BuildContext context, HospitalStore store,
      List<LabOrder> results, bool isDoctor) {
    if (results.isEmpty) {
      return const EmptyState('All lab results reviewed',
          icon: Icons.fact_check);
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final o in results)
        Card(
          child: ListTile(
            leading: Icon(Icons.science,
                color: o.abnormal ? Colors.red : Colors.green),
            title: Text('${o.testName} – ${store.patientName(o.patientId)}'),
            subtitle: Text('${o.result}'
                '${o.resultRemarks.isEmpty ? '' : '\n${o.resultRemarks}'}'),
            isThreeLine: o.resultRemarks.isNotEmpty,
            trailing: isDoctor
                ? TextButton(
                    onPressed: () => store.markResultReviewed(o.id),
                    child: const Text('Mark reviewed'),
                  )
                : StatusChip.lab(o),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        ConsultationScreen(consultationId: o.consultationId))),
          ),
        ),
    ]);
  }

  Widget _openList(BuildContext context, HospitalStore store,
      List<Consultation> open, bool isDoctor) {
    if (open.isEmpty) {
      return const EmptyState('No open consultations', icon: Icons.task_alt);
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final c in open)
        Card(
          child: ListTile(
            leading: const Icon(Icons.pending_actions),
            title: Text(store.patientName(c.patientId)),
            subtitle: Text('Started ${fmtDateTime(c.startedAt)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ConsultationScreen(consultationId: c.id))),
          ),
        ),
    ]);
  }
}
