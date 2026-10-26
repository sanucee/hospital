import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/hospital_store.dart';
import '../models/models.dart';

final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
final _date = DateFormat('d MMM yyyy');
final _dateTime = DateFormat('d MMM yyyy, HH:mm');
final _time = DateFormat('HH:mm');

String money(num v) => _money.format(v);
String fmtDate(DateTime? d) => d == null ? '—' : _date.format(d);
String fmtDateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d);
String fmtTime(DateTime? d) => d == null ? '—' : _time.format(d);

/// Runs [action], showing any [HospitalException] (or other error) as a
/// snackbar. Returns true on success.
Future<bool> guarded(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  try {
    await action();
    if (success != null) {
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(e.toString()), backgroundColor: errorColor),
    );
    return false;
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  factory StatusChip.appointment(AppointmentStatus s) => StatusChip(
    s.label,
    color: switch (s) {
      AppointmentStatus.scheduled => Colors.blueGrey,
      AppointmentStatus.checkedIn => Colors.orange,
      AppointmentStatus.inConsultation => Colors.blue,
      AppointmentStatus.completed => Colors.green,
      AppointmentStatus.cancelled => Colors.red,
    },
  );

  factory StatusChip.lab(LabOrder o) => StatusChip(
    o.status.label,
    color: switch (o.status) {
      LabOrderStatus.ordered => Colors.orange,
      LabOrderStatus.sampleCollected => Colors.blue,
      LabOrderStatus.completed => o.abnormal ? Colors.red : Colors.green,
      LabOrderStatus.cancelled => Colors.grey,
    },
  );

  factory StatusChip.prescription(PrescriptionStatus s) => StatusChip(
    s.label,
    color: switch (s) {
      PrescriptionStatus.pending => Colors.orange,
      PrescriptionStatus.partiallyDispensed => Colors.deepPurple,
      PrescriptionStatus.dispensed => Colors.green,
      PrescriptionStatus.cancelled => Colors.grey,
    },
  );

  factory StatusChip.invoice(Invoice i) => i.isPaid
      ? const StatusChip('Paid', color: Colors.green)
      : i.amountPaid > 0
      ? const StatusChip('Part paid', color: Colors.deepPurple)
      : const StatusChip('Unpaid', color: Colors.red);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.icon,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: c),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: c),
            ),
          ],
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  foregroundColor: color,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(label, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Label/value pair used in detail views.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}

/// Bottom-sheet / dialog style search picker for patients.
Future<Patient?> pickPatient(BuildContext context, HospitalStore store) {
  return showDialog<Patient>(
    context: context,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(
        builder: (ctx, setState) {
          final results = store.searchPatients(query);
          return AlertDialog(
            title: const Text('Select patient'),
            content: SizedBox(
              width: 420,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Name, MRN or phone',
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: results.isEmpty
                        ? const EmptyState('No matching patients')
                        : ListView(
                            children: [
                              for (final p in results)
                                ListTile(
                                  leading: CircleAvatar(child: Text(p.name[0])),
                                  title: Text(p.name),
                                  subtitle: Text(
                                    '${p.mrn} · ${p.age}y ${p.gender} · ${p.phone}',
                                  ),
                                  onTap: () => Navigator.pop(ctx, p),
                                ),
                            ],
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
            ],
          );
        },
      );
    },
  );
}
