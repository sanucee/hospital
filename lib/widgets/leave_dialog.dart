import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospital_store.dart';
import '../models/models.dart';
import 'common.dart';

/// Lets the signed-in staff member request leave and see their requests.
Future<void> showLeaveRequestDialog(BuildContext context) async {
  final store = context.read<HospitalStore>();
  final me = store.currentUser!;
  var type = LeaveType.annual;
  DateTime? from;
  DateTime? to;
  final reason = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<DateTime?> pick(DateTime? initial) => showDatePicker(
          context: ctx,
          initialDate: initial ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 30)),
          lastDate: DateTime(2100),
        );
        final mine = store.leavesFor(me.id);
        return AlertDialog(
          title: const Text('Request leave'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<LeaveType>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final t in LeaveType.values)
                        DropdownMenuItem(value: t, child: Text(t.label)),
                    ],
                    onChanged: (v) => setState(() => type = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final d = await pick(from);
                            if (d != null) setState(() => from = d);
                          },
                          child: Text(from == null ? 'From' : fmtDate(from)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final d = await pick(to ?? from);
                            if (d != null) setState(() => to = d);
                          },
                          child: Text(to == null ? 'To' : fmtDate(to)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                  ),
                  if (type == LeaveType.unpaid)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Unpaid leave is deducted from your salary.'),
                    ),
                  if (mine.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Your requests',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    for (final l in mine.take(5))
                      Text(
                        '${l.type.label}: ${fmtDate(l.from)} – '
                        '${fmtDate(l.to)} · ${l.status.name}',
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: from == null || to == null
                  ? null
                  : () async {
                      final nav = Navigator.of(ctx);
                      if (await guarded(
                        ctx,
                        () => store.requestLeave(
                          staffId: me.id,
                          type: type,
                          from: from!,
                          to: to!,
                          reason: reason.text,
                        ),
                        success: 'Leave requested',
                      )) {
                        nav.pop();
                      }
                    },
              child: const Text('Request'),
            ),
          ],
        );
      },
    ),
  );
}
