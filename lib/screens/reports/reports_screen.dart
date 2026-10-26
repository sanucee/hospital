import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../reports/reports.dart';
import '../../reports/save_file.dart';
import '../../widgets/common.dart';

/// Excel exports for the reports the signed-in role may run.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _from;
  late DateTime _to;
  String _preset = 'This month';

  static final _presets = <String, (DateTime, DateTime) Function(DateTime)>{
    'Today': (n) => (n, n),
    'Last 7 days': (n) => (n.subtract(const Duration(days: 6)), n),
    'This month': (n) => (DateTime(n.year, n.month), n),
    'Last month': (n) =>
        (DateTime(n.year, n.month - 1), DateTime(n.year, n.month, 0)),
    'Last 90 days': (n) => (n.subtract(const Duration(days: 89)), n),
  };

  @override
  void initState() {
    super.initState();
    _apply(_preset);
  }

  void _apply(String preset) {
    final (f, t) = _presets[preset]!(DateTime.now());
    _preset = preset;
    _from = DateTime(f.year, f.month, f.day);
    _to = DateTime(t.year, t.month, t.day);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final user = store.currentUser!;
    final reports = kReports.where((r) => r.roles.contains(user.role)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final p in _presets.keys)
              ChoiceChip(
                label: Text(p),
                selected: _preset == p,
                onSelected: (_) => setState(() => _apply(p)),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text('${fmtDate(_from)} – ${fmtDate(_to)}'),
              onPressed: () async {
                final r = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: DateTimeRange(start: _from, end: _to),
                );
                if (r != null) {
                  setState(() {
                    _preset = '';
                    _from = r.start;
                    _to = r.end;
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (reports.isEmpty) const EmptyState('No reports for your role'),
        for (final d in reports)
          Builder(
            builder: (context) {
              final r = d.build(store, _from, _to);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.table_chart, color: Colors.green),
                  title: Text(d.title),
                  subtitle: Text(
                    '${d.description}'
                    '${d.usesPeriod ? '' : ' (as of the end date)'}'
                    ' · ${r.rowCount} row(s)',
                  ),
                  trailing: FilledButton.tonalIcon(
                    icon: const Icon(Icons.download),
                    label: const Text('Excel'),
                    onPressed: () => saveXlsx(
                      context,
                      reportFileName(r),
                      reportXlsx(
                        r,
                        hospital: store.profile.name,
                        generatedBy: user.name,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
