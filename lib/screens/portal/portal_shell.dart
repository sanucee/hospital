import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../print/documents.dart';
import '../../print/print_button.dart';
import '../../widgets/common.dart';
import 'portal_book.dart';

/// What a signed-in patient sees: their appointments, online booking,
/// released results and prescriptions, bills and contact details.
class PortalShell extends StatefulWidget {
  const PortalShell({super.key});

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  int _index = 0;

  static const _pages = [
    ('Appointments', Icons.event, Icons.event_outlined),
    ('Book', Icons.add_circle, Icons.add_circle_outline),
    ('Results', Icons.science, Icons.science_outlined),
    ('Bills', Icons.receipt_long, Icons.receipt_long_outlined),
    ('My details', Icons.person, Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final me = store.currentPatient!;
    return Scaffold(
      appBar: AppBar(
        title: Text(store.profile.name),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text('${me.name} · ${me.mrn}')),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => store.portalSignOut(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: switch (_index) {
            0 => _AppointmentsPage(onBook: () => setState(() => _index = 1)),
            1 => PortalBookPage(onBooked: () => setState(() => _index = 0)),
            2 => const _ResultsPage(),
            3 => const _BillsPage(),
            _ => const _DetailsPage(),
          },
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final (label, selected, icon) in _pages)
            NavigationDestination(
              icon: Icon(icon),
              selectedIcon: Icon(selected),
              label: label,
            ),
        ],
      ),
    );
  }
}

class _AppointmentsPage extends StatelessWidget {
  const _AppointmentsPage({required this.onBook});

  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final upcoming = store.myUpcomingAppointments;
    final past = store.myAppointments
        .where((a) => !upcoming.contains(a))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Upcoming',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: onBook,
              icon: const Icon(Icons.add),
              label: const Text('Book an appointment'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              'No upcoming appointments',
              icon: Icons.event_available,
            ),
          ),
        for (final a in upcoming) _tile(context, store, a, cancellable: true),
        if (past.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Past and cancelled',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final a in past) _tile(context, store, a),
        ],
        const SizedBox(height: 16),
        Text(
          'To change an appointment, cancel it and book a new time, or call '
          '${store.profile.phone.isEmpty ? 'the hospital' : store.profile.phone}.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    HospitalStore store,
    Appointment a, {
    bool cancellable = false,
  }) {
    final doctor = store.userById(a.doctorId);
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.event)),
        title: Text(
          '${fmtDate(a.scheduledAt)} at ${fmtTime(a.scheduledAt)} · '
          '${doctor?.name ?? 'Doctor'}',
        ),
        subtitle: Text(
          [
            if (doctor?.specialization != null) doctor!.specialization!,
            if (a.reason.isNotEmpty) a.reason,
            a.channel.label,
          ].join(' · '),
        ),
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusChip.appointment(a.status),
            if (cancellable)
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Cancel this appointment?'),
                      content: Text(
                        '${doctor?.name} on ${fmtDate(a.scheduledAt)} at '
                        '${fmtTime(a.scheduledAt)}',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Keep it'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Cancel appointment'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await guarded(
                      context,
                      () => store.portalCancel(a.id),
                      success: 'Appointment cancelled',
                    );
                  }
                },
                child: const Text('Cancel'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultsPage extends StatelessWidget {
  const _ResultsPage();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final results = store.myResults;
    final rx = store.myPrescriptions;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text('Lab results', style: text.titleMedium)),
            if (results.isNotEmpty)
              PrintButton(
                tooltip: 'Print or save lab report',
                name: 'lab-results.pdf',
                document: () => labReportPdf(store, results),
              ),
          ],
        ),
        Text(
          'Results appear here once your doctor has reviewed them.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 8),
        if (results.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState('No results yet', icon: Icons.science),
          ),
        for (final o in results)
          Card(
            child: ListTile(
              leading: Icon(
                o.abnormal ? Icons.warning_amber : Icons.check_circle,
                color: o.abnormal ? Colors.orange : Colors.green,
              ),
              title: Text(o.testName),
              subtitle: Text(
                [
                  o.result,
                  if (o.resultRemarks.isNotEmpty) o.resultRemarks,
                  fmtDate(o.completedAt),
                ].join('\n'),
              ),
              isThreeLine: o.resultRemarks.isNotEmpty,
              trailing: o.abnormal
                  ? const StatusChip(
                      'Outside normal range',
                      color: Colors.orange,
                    )
                  : null,
            ),
          ),
        const SizedBox(height: 16),
        Text('Prescriptions', style: text.titleMedium),
        const SizedBox(height: 8),
        if (rx.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState('No prescriptions', icon: Icons.medication),
          ),
        for (final p in rx)
          Card(
            child: ListTile(
              leading: const Icon(Icons.medication),
              title: Text(
                '${fmtDate(p.createdAt)} · ${store.userName(p.doctorId)}',
              ),
              subtitle: Text(
                [
                  for (final i in p.items)
                    '${i.medicineName} ${i.dosage} · ${i.frequency}'
                        '${i.durationDays > 0 ? ' · ${i.durationDays} days' : ''}'
                        '${i.instructions.isEmpty ? '' : ' · ${i.instructions}'}',
                ].join('\n'),
              ),
              trailing: Text(p.status.label),
            ),
          ),
      ],
    );
  }
}

class _BillsPage extends StatelessWidget {
  const _BillsPage();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final bills = store.myInvoices;
    final due = bills.fold<double>(
      0,
      (s, i) => s + (i.balance > 0 ? i.balance : 0),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: due > 0
              ? Theme.of(context).colorScheme.errorContainer
              : Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: Text(
              due > 0 ? 'Balance due: ${money(due)}' : 'Nothing to pay',
            ),
            subtitle: const Text('Pay at the reception or pharmacy counter.'),
          ),
        ),
        const SizedBox(height: 8),
        if (bills.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState('No bills yet', icon: Icons.receipt_long),
          ),
        for (final inv in bills)
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long),
              title: Text('${inv.number} · ${fmtDate(inv.createdAt)}'),
              subtitle: Text(
                'Total ${money(inv.total)} · paid ${money(inv.amountPaid)}'
                '${inv.insurerPaid > 0 ? ' · insurer ${money(inv.insurerPaid)}' : ''}'
                '${inv.balance > 0 ? ' · balance ${money(inv.balance)}' : ''}',
              ),
              trailing: PrintButton(
                tooltip: inv.isPaid ? 'Print receipt' : 'Print bill',
                name: '${inv.number}.pdf',
                document: () => invoicePdf(store, inv),
              ),
            ),
          ),
      ],
    );
  }
}

class _DetailsPage extends StatefulWidget {
  const _DetailsPage();

  @override
  State<_DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<_DetailsPage> {
  late final Patient _me = context.read<HospitalStore>().currentPatient!;
  late final _phone = TextEditingController(text: _me.phone);
  late final _email = TextEditingController(text: _me.email);
  late final _address = TextEditingController(text: _me.address);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final me = store.currentPatient!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge),
            title: Text(me.name),
            subtitle: Text(
              '${me.mrn} · born ${fmtDate(me.dateOfBirth)} · ${me.gender}'
              '${me.bloodGroup.isEmpty ? '' : ' · ${me.bloodGroup}'}'
              '${me.allergies.isEmpty ? '' : '\nAllergies: ${me.allergies}'}',
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Contact details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Mobile number'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          decoration: const InputDecoration(labelText: 'Address'),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => guarded(
              context,
              () => store.portalUpdateContact(
                phone: _phone.text,
                email: _email.text,
                address: _address.text,
              ),
              success: 'Details saved',
            ),
            child: const Text('Save'),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'To change your name, date of birth, allergies or insurance, '
          'please speak to reception.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
