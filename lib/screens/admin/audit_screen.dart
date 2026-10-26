import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../reports/reports.dart';
import '../../reports/xlsx.dart';
import '../../reports/save_file.dart';
import '../../widgets/common.dart';
import '../patient_detail_screen.dart';

/// Who changed what, and when (administrators only).
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  String _query = '';
  String? _userId;
  String? _action;
  DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to = DateTime.now();

  static const _actions = [
    'created',
    'updated',
    'deleted',
    'signed in',
    'signed out',
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final q = _query.toLowerCase();
    final start = DateTime(_from.year, _from.month, _from.day);
    final end = DateTime(_to.year, _to.month, _to.day + 1);
    final entries =
        store.auditLog
            .where(
              (e) =>
                  !e.at.isBefore(start) &&
                  e.at.isBefore(end) &&
                  (_userId == null || e.userId == _userId) &&
                  (_action == null || e.action == _action) &&
                  (q.isEmpty ||
                      e.summary.toLowerCase().contains(q) ||
                      e.userName.toLowerCase().contains(q)),
            )
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    final users = {for (final e in store.auditLog) e.userId: e.userName};

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search details or user',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              DropdownButton<String?>(
                value: _userId,
                hint: const Text('Everyone'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Everyone')),
                  for (final e in users.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _userId = v),
              ),
              DropdownButton<String?>(
                value: _action,
                hint: const Text('All actions'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All actions'),
                  ),
                  for (final a in _actions)
                    DropdownMenuItem(value: a, child: Text(a)),
                ],
                onChanged: (v) => setState(() => _action = v),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text('${fmtDate(_from)} – ${fmtDate(_to)}'),
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: DateTimeRange(start: _from, end: _to),
                  );
                  if (r != null) {
                    setState(() {
                      _from = r.start;
                      _to = r.end;
                    });
                  }
                },
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.download),
                label: const Text('Excel'),
                onPressed: () {
                  // Export exactly what is shown, filters included.
                  final r = Report(
                    title: 'Audit log',
                    from: _from,
                    to: _to,
                    summary: [('Entries', entries.length)],
                    sheets: [
                      XlsxSheet(
                        name: 'Audit log',
                        headers: const [
                          'Time',
                          'User',
                          'Action',
                          'Record type',
                          'Patient',
                          'Details',
                        ],
                        widths: const [18, 22, 10, 16, 22, 100],
                        rows: [
                          for (final e in entries.reversed)
                            [
                              e.at,
                              e.userName,
                              e.action,
                              auditRecordType(e.collection),
                              e.patientId == null
                                  ? ''
                                  : store.patientName(e.patientId!),
                              e.summary,
                            ],
                        ],
                      ),
                    ],
                  );
                  saveXlsx(
                    context,
                    reportFileName(r),
                    reportXlsx(
                      r,
                      hospital: store.profile.name,
                      generatedBy: store.currentUser!.name,
                    ),
                  );
                },
              ),
              Text('${entries.length} entries'),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const EmptyState('No matching entries', icon: Icons.history)
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(_icon(e), color: _color(e)),
                      title: Text(e.summary),
                      subtitle: Text(
                        '${fmtDateTime(e.at)} · ${e.userName} · '
                        '${auditRecordType(e.collection)}',
                      ),
                      onTap:
                          e.patientId == null ||
                              store.patientById(e.patientId!) == null
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PatientDetailScreen(
                                  patientId: e.patientId!,
                                ),
                              ),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  IconData _icon(AuditEntry e) => switch (e.action) {
    'created' => Icons.add_circle_outline,
    'updated' => Icons.edit,
    'deleted' => Icons.delete_outline,
    _ => Icons.login,
  };

  Color _color(AuditEntry e) => switch (e.action) {
    'created' => Colors.green,
    'updated' => Colors.blue,
    'deleted' => Colors.red,
    _ => Colors.grey,
  };
}
