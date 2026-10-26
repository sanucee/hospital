import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospital_store.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'home_shell.dart';
import 'patient_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final user = store.currentUser!;
    final nav = ShellNavigator.of(context);
    final now = DateTime.now();
    final todays = store.appointmentsOn(now);
    final waiting = todays
        .where((a) => a.status == AppointmentStatus.checkedIn)
        .length;

    final tiles = <Widget>[
      if (user.role != UserRole.doctor)
        StatTile(
          label: 'Patients registered',
          value: '${store.patients.length}',
          icon: Icons.people,
          color: Colors.teal,
          onTap: () => nav?.goTo('Patients'),
        ),
      if ({UserRole.admin, UserRole.receptionist}.contains(user.role)) ...[
        StatTile(
          label: "Today's appointments",
          value: '${todays.length}',
          icon: Icons.event,
          color: Colors.indigo,
          onTap: () => nav?.goTo('Appointments'),
        ),
        StatTile(
          label: 'Waiting for doctor',
          value: '$waiting',
          icon: Icons.hourglass_top,
          color: Colors.orange,
          onTap: () => nav?.goTo('Appointments'),
        ),
      ],
      if (user.role == UserRole.doctor) ...[
        StatTile(
          label: 'In my queue',
          value: '${store.doctorQueue(user.id).length}',
          icon: Icons.groups,
          color: Colors.orange,
          onTap: () => nav?.goTo('Consultations'),
        ),
        StatTile(
          label: 'New lab results',
          value: '${store.unreviewedResults(user.id).length}',
          icon: Icons.science,
          color: Colors.purple,
          onTap: () => nav?.goTo('Consultations'),
        ),
        StatTile(
          label: 'Appointments today',
          value: '${store.appointmentsOn(now, doctorId: user.id).length}',
          icon: Icons.event,
          color: Colors.indigo,
          onTap: () => nav?.goTo('Appointments'),
        ),
      ],
      if ({UserRole.admin, UserRole.labTechnician}.contains(user.role)) ...[
        StatTile(
          label: 'Lab tests pending',
          value: '${store.labQueue.length}',
          icon: Icons.biotech,
          color: Colors.blue,
          onTap: () => nav?.goTo('Laboratory'),
        ),
        StatTile(
          label: 'Urgent lab tests',
          value: '${store.labQueue.where((o) => o.urgent).length}',
          icon: Icons.priority_high,
          color: Colors.red,
          onTap: () => nav?.goTo('Laboratory'),
        ),
      ],
      if ({UserRole.admin, UserRole.pharmacist}.contains(user.role)) ...[
        StatTile(
          label: 'Prescriptions to dispense',
          value: '${store.pharmacyQueue.length}',
          icon: Icons.local_pharmacy,
          color: Colors.green,
          onTap: () => nav?.goTo('Pharmacy'),
        ),
        StatTile(
          label: 'Low-stock medicines',
          value: '${store.lowStockMedicines.length}',
          icon: Icons.inventory_2,
          color: Colors.deepOrange,
          onTap: () => nav?.goTo('Pharmacy'),
        ),
      ],
      if ({
        UserRole.admin,
        UserRole.receptionist,
        UserRole.doctor,
        UserRole.nurse,
      }.contains(user.role)) ...[
        StatTile(
          label: 'Inpatients',
          value: '${store.activeAdmissions.length}',
          icon: Icons.bed,
          color: Colors.indigo,
          onTap: () => nav?.goTo('Inpatients'),
        ),
        StatTile(
          label: 'Free beds',
          value:
              '${store.totalBeds - store.activeAdmissions.length}'
              '/${store.totalBeds}',
          icon: Icons.single_bed,
          color: Colors.teal,
          onTap: () => nav?.goTo('Inpatients'),
        ),
      ],
      if ({UserRole.admin, UserRole.doctor, UserRole.nurse}.contains(user.role))
        StatTile(
          label: 'Surgeries today',
          value: '${store.surgeriesOn(now).length}',
          icon: Icons.healing,
          color: Colors.deepPurple,
          onTap: () => nav?.goTo('Operation theatre'),
        ),
      if ({
        UserRole.admin,
        UserRole.receptionist,
        UserRole.pharmacist,
        UserRole.accountant,
      }.contains(user.role))
        StatTile(
          label: 'Outstanding bills',
          value: money(store.outstandingBalance),
          icon: Icons.receipt_long,
          color: Colors.brown,
          onTap: () => nav?.goTo('Billing'),
        ),
      if ({UserRole.admin, UserRole.accountant}.contains(user.role)) ...[
        StatTile(
          label: 'Expenses this month',
          value: money(store.financeFor(now).expenses),
          icon: Icons.shopping_cart,
          color: Colors.deepOrange,
          onTap: () => nav?.goTo('Finance'),
        ),
        StatTile(
          label: 'Net cash this month',
          value: money(store.financeFor(now).net),
          icon: Icons.account_balance,
          color: Colors.green,
          onTap: () => nav?.goTo('Finance'),
        ),
      ],
      if (user.role == UserRole.admin)
        StatTile(
          label: 'Leave requests',
          value: '${store.pendingLeaves.length}',
          icon: Icons.beach_access,
          color: Colors.orange,
          onTap: () => nav?.goTo('Staff'),
        ),
    ];

    final activity = store.notificationsFor(user).take(8).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Welcome, ${user.name}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          '${user.role.label} · ${fmtDate(now)}',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: tiles),
        const SizedBox(height: 16),
        if (user.role == UserRole.admin) const _DepartmentFlow(),
        SectionCard(
          title: 'Recent activity for you',
          icon: Icons.notifications_active,
          child: activity.isEmpty
              ? const Text(
                  'Nothing yet. Activity from other departments '
                  'will appear here.',
                )
              : Column(
                  children: [
                    for (final n in activity)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.bolt),
                        title: Text(n.title),
                        subtitle: Text(n.body),
                        trailing: Text(fmtTime(n.createdAt)),
                        onTap: n.patientId == null
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PatientDetailScreen(
                                    patientId: n.patientId!,
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

/// Shows the admin how a patient moves through the departments today.
class _DepartmentFlow extends StatelessWidget {
  const _DepartmentFlow();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final now = DateTime.now();
    final todays = store.appointmentsOn(now);
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    final steps = [
      ('Reception', Icons.badge, '${todays.length} booked'),
      (
        'Doctor',
        Icons.medical_services,
        '${store.consultations.where((c) => isToday(c.startedAt)).length} seen',
      ),
      (
        'Laboratory',
        Icons.biotech,
        '${store.labOrders.where((o) => isToday(o.orderedAt)).length} tests',
      ),
      (
        'Pharmacy',
        Icons.local_pharmacy,
        '${store.prescriptions.where((p) => isToday(p.createdAt)).length} Rx',
      ),
      ('Wards', Icons.bed, '${store.activeAdmissions.length} admitted'),
      ('Theatre', Icons.healing, '${store.surgeriesOn(now).length} surgeries'),
      ('Billing', Icons.payments, '${money(store.revenueOn(now))} collected'),
    ];

    return SectionCard(
      title: 'Patient flow today',
      icon: Icons.account_tree,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Column(
                children: [
                  CircleAvatar(radius: 24, child: Icon(steps[i].$2)),
                  const SizedBox(height: 4),
                  Text(
                    steps[i].$1,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    steps[i].$3,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              if (i < steps.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
