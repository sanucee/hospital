import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospital_store.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'billing/billing_screen.dart';
import 'doctor/consultation_screen.dart';
import 'inpatient/inpatients_screen.dart';
import 'reception/patients_screen.dart';
import '../print/print_button.dart';
import '../print/documents.dart';

/// The unified medical record: everything every department has done for a
/// patient, in one place.
class PatientDetailScreen extends StatelessWidget {
  const PatientDetailScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final p = store.patientById(patientId);
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState('Patient not found'),
      );
    }
    final user = store.currentUser!;
    final consultations = store.consultationsFor(p.id);
    final labs = store.labOrdersFor(patientId: p.id);
    final rxs = store.prescriptionsFor(patientId: p.id);
    final bills = store.invoicesFor(p.id);
    final canSeeBills = user.role != UserRole.labTechnician;
    final stays = store.admissionsFor(p.id);
    final ops = store.surgeriesFor(p.id);
    final admitted = store.activeAdmissionFor(p.id);
    final canAdmit = {
      UserRole.admin,
      UserRole.receptionist,
      UserRole.doctor,
      UserRole.nurse,
    }.contains(user.role);

    return DefaultTabController(
      length: canSeeBills ? 5 : 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(p.name),
          actions: [
            if (user.role == UserRole.admin ||
                user.role == UserRole.receptionist)
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit),
                onPressed: () => showPatientForm(context, existing: p),
              ),
            if (admitted != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: StatusChip(
                    'Admitted · ${admitted.currentStay.roomName}',
                    color: Colors.indigo,
                    icon: Icons.bed,
                  ),
                ),
              )
            else if (canAdmit)
              TextButton.icon(
                icon: const Icon(Icons.hotel),
                label: const Text('Admit'),
                onPressed: () => showAdmitDialog(context, patientId: p.id),
              ),
            if (user.role == UserRole.doctor)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.medical_services),
                  label: const Text('New consultation'),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    final c = await store.startConsultation(
                      patientId: p.id,
                      doctorId: user.id,
                    );
                    nav.push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ConsultationScreen(consultationId: c.id),
                      ),
                    );
                  },
                ),
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Visits (${consultations.length})'),
              Tab(text: 'Lab results (${labs.length})'),
              Tab(text: 'Prescriptions (${rxs.length})'),
              Tab(text: 'Inpatient & surgery (${stays.length + ops.length})'),
              if (canSeeBills) Tab(text: 'Bills (${bills.length})'),
            ],
          ),
        ),
        body: Column(
          children: [
            _Header(patient: p),
            Expanded(
              child: TabBarView(
                children: [
                  _VisitsTab(consultations: consultations),
                  _LabsTab(orders: labs),
                  _PrescriptionsTab(prescriptions: rxs),
                  _InpatientTab(admissions: stays, surgeries: ops),
                  if (canSeeBills) _BillsTab(invoices: bills),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final p = patient;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 4,
            children: [
              Text(p.mrn, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${p.age} yrs · ${p.gender}'),
              Text('DOB ${fmtDate(p.dateOfBirth)}'),
              Text('Blood ${p.bloodGroup.isEmpty ? '—' : p.bloodGroup}'),
              Text(p.phone),
              if (p.address.isNotEmpty) Text(p.address),
              if (p.insurerId != null)
                Builder(
                  builder: (context) {
                    final store = context.read<HospitalStore>();
                    final valid = p.policyValidOn(DateTime.now());
                    return StatusChip(
                      '${store.insurerById(p.insurerId)?.name ?? 'Insured'}'
                      '${p.policyNumber.isEmpty ? '' : ' · ${p.policyNumber}'}'
                      '${valid ? '' : ' · EXPIRED'}',
                      color: valid ? Colors.indigo : Colors.red,
                      icon: Icons.health_and_safety,
                    );
                  },
                ),
            ],
          ),
          if (p.allergies.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning, color: scheme.onErrorContainer, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Allergies: ${p.allergies}',
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VisitsTab extends StatelessWidget {
  const _VisitsTab({required this.consultations});

  final List<Consultation> consultations;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final isDoctor = store.currentUser!.role == UserRole.doctor;
    if (consultations.isEmpty) {
      return const EmptyState(
        'No visits recorded yet',
        icon: Icons.history_toggle_off,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final c in consultations)
          Card(
            child: ExpansionTile(
              leading: Icon(
                c.isOpen ? Icons.pending : Icons.check_circle,
                color: c.isOpen ? Colors.orange : Colors.green,
              ),
              title: Text(
                c.diagnosis.isEmpty ? 'No diagnosis yet' : c.diagnosis,
              ),
              subtitle: Text(
                '${fmtDateTime(c.startedAt)} · ${store.userName(c.doctorId)}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow('Complaints', c.complaints),
                if (!c.vitals.isEmpty)
                  InfoRow(
                    'Vitals',
                    [
                      if (c.vitals.temperature.isNotEmpty)
                        'T ${c.vitals.temperature}°C',
                      if (c.vitals.bloodPressure.isNotEmpty)
                        'BP ${c.vitals.bloodPressure}',
                      if (c.vitals.pulse.isNotEmpty) 'P ${c.vitals.pulse}',
                      if (c.vitals.spo2.isNotEmpty) 'SpO₂ ${c.vitals.spo2}%',
                      if (c.vitals.weight.isNotEmpty) 'Wt ${c.vitals.weight}kg',
                    ].join(' · '),
                  ),
                InfoRow('Notes', c.notes),
                InfoRow(
                  'Lab tests',
                  store
                      .labOrdersFor(consultationId: c.id)
                      .map((o) => o.testName)
                      .join(', '),
                ),
                InfoRow(
                  'Medicines',
                  store
                      .prescriptionsFor(consultationId: c.id)
                      .expand((r) => r.items)
                      .map((i) => i.medicineName)
                      .join(', '),
                ),
                if (c.followUpDate != null)
                  InfoRow('Follow-up', fmtDate(c.followUpDate)),
                if (isDoctor)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: Text(c.isOpen ? 'Continue' : 'Open'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ConsultationScreen(consultationId: c.id),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InpatientTab extends StatelessWidget {
  const _InpatientTab({required this.admissions, required this.surgeries});

  final List<Admission> admissions;
  final List<Surgery> surgeries;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final now = DateTime.now();
    if (admissions.isEmpty && surgeries.isEmpty) {
      return const EmptyState('No admissions or surgeries', icon: Icons.bed);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final a in admissions)
          Card(
            child: ListTile(
              leading: Icon(
                Icons.bed,
                color: a.isActive ? Colors.indigo : null,
              ),
              title: Text(
                a.isActive
                    ? 'Admitted in ${a.currentStay.roomName}'
                    : 'Admission (discharged ${fmtDate(a.dischargedAt)})',
              ),
              trailing: a.isActive
                  ? null
                  : PrintButton(
                      tooltip: 'Print discharge summary',
                      name: 'discharge-summary.pdf',
                      document: () => dischargeSummaryPdf(store, a),
                    ),
              subtitle: Text(
                [
                  'From ${fmtDateTime(a.admittedAt)}',
                  'Dr: ${store.userName(a.doctorId)}',
                  if (a.reason.isNotEmpty) a.reason,
                  a.stays.map((s) => s.roomName).join(' → '),
                  '${a.totalDays(now)} day(s), room ${money(a.roomCharges(now))}',
                  if (a.dischargeSummary.isNotEmpty) a.dischargeSummary,
                ].join(' · '),
              ),
            ),
          ),
        for (final s in surgeries)
          Card(
            child: ListTile(
              leading: const Icon(Icons.healing),
              title: Text(s.procedure),
              subtitle: Text(
                [
                  fmtDateTime(s.startedAt ?? s.scheduledAt),
                  store.theatreById(s.theatreId)?.name ?? '',
                  'Surgeon ${store.userName(s.surgeonId)}',
                  if (s.notes.isNotEmpty) s.notes,
                ].join(' · '),
              ),
              trailing: StatusChip(
                s.status.label,
                color: s.status == SurgeryStatus.completed
                    ? Colors.green
                    : s.status == SurgeryStatus.cancelled
                    ? Colors.grey
                    : Colors.deepPurple,
              ),
            ),
          ),
      ],
    );
  }
}

class _LabsTab extends StatelessWidget {
  const _LabsTab({required this.orders});

  final List<LabOrder> orders;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    if (orders.isEmpty) {
      return const EmptyState('No lab tests ordered', icon: Icons.science);
    }
    final done = orders
        .where((o) => o.status == LabOrderStatus.completed)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (done.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.print),
              label: const Text('Print all results'),
              onPressed: () => printPdf(
                context,
                'lab-results.pdf',
                () => labReportPdf(store, done),
              ),
            ),
          ),
        for (final o in orders)
          Card(
            child: ListTile(
              leading: Icon(
                Icons.science,
                color: o.abnormal ? Colors.red : null,
              ),
              title: Text(o.testName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ordered ${fmtDateTime(o.orderedAt)} by '
                    '${store.userName(o.doctorId)}',
                  ),
                  if (o.status == LabOrderStatus.completed) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Result: ${o.result}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: o.abnormal ? Colors.red : null,
                      ),
                    ),
                    if (o.resultRemarks.isNotEmpty)
                      Text('Remarks: ${o.resultRemarks}'),
                    Text(
                      'Reference: '
                      '${store.labTestById(o.testId)?.referenceRange ?? '—'}',
                    ),
                  ],
                ],
              ),
              isThreeLine: o.status == LabOrderStatus.completed,
              trailing: StatusChip.lab(o),
            ),
          ),
      ],
    );
  }
}

class _PrescriptionsTab extends StatelessWidget {
  const _PrescriptionsTab({required this.prescriptions});

  final List<Prescription> prescriptions;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    if (prescriptions.isEmpty) {
      return const EmptyState('No prescriptions', icon: Icons.medication);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final rx in prescriptions)
          SectionCard(
            title:
                '${fmtDateTime(rx.createdAt)} · ${store.userName(rx.doctorId)}',
            icon: Icons.medication,
            trailing: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip.prescription(rx.status),
                PrintButton(
                  tooltip: 'Print prescription',
                  name: 'prescription.pdf',
                  document: () => prescriptionPdf(store, rx),
                ),
              ],
            ),
            child: Column(
              children: [
                for (final i in rx.items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(i.medicineName),
                    subtitle: Text(
                      '${i.dosage} · ${i.frequency} · '
                      '${i.durationDays} days'
                      '${i.instructions.isEmpty ? '' : ' · ${i.instructions}'}',
                    ),
                    trailing: Text('${i.dispensedQuantity}/${i.quantity}'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BillsTab extends StatelessWidget {
  const _BillsTab({required this.invoices});

  final List<Invoice> invoices;

  @override
  Widget build(BuildContext context) {
    if (invoices.isEmpty) {
      return const EmptyState('No bills', icon: Icons.receipt);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final inv in invoices)
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long),
              title: Text('${inv.number} · ${money(inv.total)}'),
              subtitle: Text(
                '${fmtDate(inv.createdAt)} · '
                'Balance ${money(inv.balance)}',
              ),
              trailing: StatusChip.invoice(inv),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InvoiceScreen(invoiceId: inv.id),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
