import 'package:flutter/material.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'patients_screen.dart';

/// Finds the patient on a phone call by the number they're calling from
/// or their name, or registers a new caller.
Future<Patient?> pickCaller(BuildContext context, HospitalStore store) {
  return showDialog<Patient>(
    context: context,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(
        builder: (ctx, setState) {
          final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
          final results = query.trim().isEmpty
              ? <Patient>[]
              : {
                  // Match "0803 111 2233" however it is typed.
                  if (digits.length >= 4)
                    ...store.patients.where(
                      (p) => p.phone
                          .replaceAll(RegExp(r'[^0-9]'), '')
                          .contains(digits),
                    ),
                  ...store.searchPatients(query),
                }.toList();
          final looksLikePhone =
              digits.length >= 4 &&
              RegExp(r'^[0-9\s+()-]+$').hasMatch(query.trim());
          return AlertDialog(
            title: const Text('Phone booking: who is calling?'),
            content: SizedBox(
              width: 440,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    key: const Key('caller-search'),
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.phone_in_talk),
                      hintText: "Caller's number, patient name or MRN",
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: query.trim().isEmpty
                        ? const EmptyState(
                            'Type the number the patient is calling from',
                            icon: Icons.dialpad,
                          )
                        : results.isEmpty
                        ? const EmptyState(
                            'No patient found. Register them as a new caller.',
                          )
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
              OutlinedButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text('New caller'),
                onPressed: () async {
                  final nav = Navigator.of(ctx);
                  final p = await showPatientForm(
                    ctx,
                    initialPhone: looksLikePhone ? query.trim() : '',
                    initialName: looksLikePhone ? '' : query.trim(),
                  );
                  if (p != null) nav.pop(p);
                },
              ),
            ],
          );
        },
      );
    },
  );
}
