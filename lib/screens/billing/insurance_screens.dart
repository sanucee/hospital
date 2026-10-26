import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../print/documents.dart';
import '../../print/print_button.dart';
import '../../widgets/common.dart';
import 'billing_screen.dart';

StatusChip claimChip(ClaimStatus s) => StatusChip(
  s.label,
  color: switch (s) {
    ClaimStatus.draft => Colors.blueGrey,
    ClaimStatus.submitted => Colors.orange,
    ClaimStatus.approved => Colors.indigo,
    ClaimStatus.rejected => Colors.red,
    ClaimStatus.paid => Colors.green,
  },
);

/// Insurance on one invoice: the insurer, the split, and its claim.
class InvoiceInsuranceCard extends StatelessWidget {
  const InvoiceInsuranceCard({super.key, required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final inv = invoice;
    final insurer = store.insurerById(inv.insurerId);
    final patient = store.patientById(inv.patientId);
    final claim = store.activeClaimFor(inv.id);
    final rejected = store.claims
        .where((c) => c.invoiceId == inv.id && c.status == ClaimStatus.rejected)
        .toList();
    final canEdit = {
      UserRole.admin,
      UserRole.receptionist,
      UserRole.accountant,
    }.contains(store.currentUser!.role);

    return SectionCard(
      title: 'Insurance',
      icon: Icons.health_and_safety,
      trailing: canEdit && claim == null
          ? TextButton(
              onPressed: () => _chooseInsurer(context, inv),
              child: Text(insurer == null ? 'Attach insurer' : 'Change'),
            )
          : null,
      child: insurer == null
          ? const Align(
              alignment: Alignment.centerLeft,
              child: Text('Not insured: the patient pays the whole bill.'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow('Insurer', insurer.name),
                InfoRow(
                  'Policy',
                  [
                    if (patient?.policyNumber.isNotEmpty ?? false)
                      patient!.policyNumber,
                    if (patient?.policyExpiry != null)
                      'valid to ${fmtDate(patient!.policyExpiry)}',
                  ].join(', '),
                ),
                InfoRow(
                  'Coverage',
                  '${inv.coveragePercent.toStringAsFixed(0)}%'
                      '${inv.coverageLimit > 0 ? ', up to ${money(inv.coverageLimit)}' : ''}',
                ),
                for (final r in rejected)
                  InfoRow(
                    'Rejected claim',
                    '${r.number}${r.notes.isEmpty ? '' : ': ${r.notes}'}',
                  ),
                const Divider(),
                if (claim == null)
                  Row(
                    children: [
                      const Expanded(child: Text('No claim yet.')),
                      if (canEdit)
                        FilledButton.icon(
                          icon: const Icon(Icons.note_add),
                          label: const Text('Create claim'),
                          onPressed: () => guarded(
                            context,
                            () => store.createClaim(inv.id),
                            success: 'Claim created',
                          ),
                        ),
                    ],
                  )
                else
                  ClaimSummary(claim: claim, canEdit: canEdit),
              ],
            ),
    );
  }

  Future<void> _chooseInsurer(BuildContext context, Invoice inv) async {
    final store = context.read<HospitalStore>();
    String? chosen = inv.insurerId;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Insurer for this bill'),
          content: SizedBox(
            width: 400,
            child: DropdownButtonFormField<String?>(
              initialValue: chosen,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Insurer'),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                for (final i in store.insurers.where((i) => i.active))
                  DropdownMenuItem(
                    value: i.id,
                    child: Text(
                      '${i.name} (${i.coveragePercent.toStringAsFixed(0)}%)',
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => chosen = v),
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
                  () => store.setInvoiceInsurer(inv.id, chosen),
                )) {
                  nav.pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A claim's figures with the action its status allows.
class ClaimSummary extends StatelessWidget {
  const ClaimSummary({super.key, required this.claim, required this.canEdit});

  final InsuranceClaim claim;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    final c = claim;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Claim ${c.number}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            claimChip(c.status),
            PrintButton(
              tooltip: 'Print claim form',
              name: '${c.number}.pdf',
              document: () => claimPdf(store, c),
            ),
          ],
        ),
        InfoRow('Claimed', money(c.amountClaimed)),
        if (c.submittedAt != null) InfoRow('Submitted', fmtDate(c.submittedAt)),
        if (c.insurerReference.isNotEmpty)
          InfoRow('Insurer ref.', c.insurerReference),
        if (c.approvedAmount != null)
          InfoRow('Approved', money(c.approvedAmount!)),
        if (c.amountPaid > 0) InfoRow('Paid by insurer', money(c.amountPaid)),
        if (c.notes.isNotEmpty) InfoRow('Notes', c.notes),
        if (canEdit)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: switch (c.status) {
                ClaimStatus.draft => [
                  TextButton(
                    onPressed: () =>
                        guarded(context, () => store.deleteClaim(c.id)),
                    child: const Text('Delete'),
                  ),
                  FilledButton(
                    onPressed: () => _textAndAmount(
                      context,
                      title: 'Submit ${c.number}',
                      textLabel: 'Insurer reference / authorisation no.',
                      onSubmit: (text, _) =>
                          store.submitClaim(c.id, reference: text),
                    ),
                    child: const Text('Submit to insurer'),
                  ),
                ],
                ClaimStatus.submitted => [
                  FilledButton(
                    onPressed: () => _textAndAmount(
                      context,
                      title: 'Insurer decision on ${c.number}',
                      amountLabel: 'Approved amount (0 = rejected)',
                      initialAmount: c.amountClaimed,
                      textLabel: 'Notes / reason',
                      onSubmit: (text, amount) => store.decideClaim(
                        c.id,
                        approvedAmount: amount!,
                        notes: text,
                      ),
                    ),
                    child: const Text('Record decision'),
                  ),
                ],
                ClaimStatus.approved => [
                  FilledButton(
                    onPressed: () => _textAndAmount(
                      context,
                      title: 'Payment from insurer',
                      amountLabel: 'Amount received',
                      initialAmount: c.outstanding,
                      textLabel: 'Remittance reference',
                      onSubmit: (text, amount) => store.recordInsurerPayment(
                        c.id,
                        amount!,
                        reference: text,
                      ),
                    ),
                    child: const Text('Record insurer payment'),
                  ),
                ],
                _ => const <Widget>[],
              },
            ),
          ),
      ],
    );
  }

  Future<void> _textAndAmount(
    BuildContext context, {
    required String title,
    required String textLabel,
    String? amountLabel,
    double? initialAmount,
    required Future<void> Function(String text, double? amount) onSubmit,
  }) async {
    final text = TextEditingController();
    final amount = TextEditingController(
      text: initialAmount?.toStringAsFixed(2),
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (amountLabel != null) ...[
                TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: amountLabel),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: text,
                decoration: InputDecoration(labelText: textLabel),
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
              if (await guarded(ctx, () async {
                double? v;
                if (amountLabel != null) {
                  v = double.tryParse(amount.text);
                  if (v == null) throw HospitalException('Enter an amount');
                }
                await onSubmit(text.text, v);
              })) {
                nav.pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class ClaimsTab extends StatefulWidget {
  const ClaimsTab({super.key});

  @override
  State<ClaimsTab> createState() => _ClaimsTabState();
}

class _ClaimsTabState extends State<ClaimsTab> {
  bool _openOnly = true;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final list = store.claimsByDate
        .where(
          (c) =>
              !_openOnly ||
              c.status == ClaimStatus.draft ||
              c.status == ClaimStatus.submitted ||
              c.status == ClaimStatus.approved,
        )
        .toList();
    double sum(ClaimStatus s, double Function(InsuranceClaim) f) =>
        store.claims.where((c) => c.status == s).fold(0, (a, c) => a + f(c));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatTile(
              label: 'Awaiting insurer decision',
              value: money(sum(ClaimStatus.submitted, (c) => c.amountClaimed)),
              icon: Icons.hourglass_top,
              color: Colors.orange,
            ),
            StatTile(
              label: 'Approved, not yet paid',
              value: money(sum(ClaimStatus.approved, (c) => c.outstanding)),
              icon: Icons.account_balance,
              color: Colors.indigo,
            ),
            FilterChip(
              label: const Text('Open claims only'),
              selected: _openOnly,
              onSelected: (v) => setState(() => _openOnly = v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const EmptyState(
            'No claims. Create one from an insured patient\'s invoice.',
            icon: Icons.health_and_safety,
          ),
        for (final c in list)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InvoiceScreen(invoiceId: c.invoiceId),
                      ),
                    ),
                    child: Text(
                      '${store.patientName(c.patientId)} · '
                      '${store.insurerById(c.insurerId)?.name ?? ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ClaimSummary(claim: c, canEdit: true),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class InsurersTab extends StatelessWidget {
  const InsurersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final canEdit = {
      UserRole.admin,
      UserRole.accountant,
    }.contains(store.currentUser!.role);
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Add insurer'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final i in store.insurers)
            ListTile(
              leading: Icon(
                Icons.health_and_safety,
                color: i.active ? Colors.indigo : Colors.grey,
              ),
              title: Text(i.name),
              subtitle: Text(
                [
                  '${i.coveragePercent.toStringAsFixed(0)}% coverage',
                  i.coverageLimit > 0
                      ? 'up to ${money(i.coverageLimit)} per bill'
                      : 'no limit',
                  '${store.patients.where((p) => p.insurerId == i.id).length} patients',
                  if (i.contact.isNotEmpty) i.contact,
                  if (!i.active) 'inactive',
                ].join(' · '),
              ),
              trailing: Text(
                money(
                  store.invoices
                      .where((inv) => inv.insurerId == i.id)
                      .fold(
                        0.0,
                        (s, inv) =>
                            s + inv.insurerBalance.clamp(0, double.infinity),
                      ),
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: canEdit ? () => _edit(context, i) : null,
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, InsuranceProvider? existing) async {
    final store = context.read<HospitalStore>();
    final name = TextEditingController(text: existing?.name);
    final pct = TextEditingController(
      text: (existing?.coveragePercent ?? 80).toStringAsFixed(0),
    );
    final limit = TextEditingController(
      text: (existing?.coverageLimit ?? 0).toStringAsFixed(0),
    );
    final contact = TextEditingController(text: existing?.contact);
    var active = existing?.active ?? true;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Add insurer' : 'Edit insurer'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: pct,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Coverage %',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: limit,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Limit per bill (0 = none)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contact,
                  decoration: const InputDecoration(
                    labelText: 'Claims contact',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text(
                    'Inactive insurers aren\'t applied to new bills',
                  ),
                  value: active,
                  onChanged: (v) => setState(() => active = v),
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
                if (await guarded(ctx, () async {
                  final p = double.tryParse(pct.text);
                  final l = double.tryParse(limit.text) ?? 0;
                  if (name.text.trim().isEmpty) {
                    throw HospitalException('Enter a name');
                  }
                  if (p == null || p < 0 || p > 100) {
                    throw HospitalException('Coverage must be 0 to 100%');
                  }
                  if (l < 0) {
                    throw HospitalException('Limit cannot be negative');
                  }
                  final i =
                      store.insurerById(existing?.id) ??
                      InsuranceProvider(id: store.newId('INS'), name: '');
                  i
                    ..name = name.text.trim()
                    ..coveragePercent = p
                    ..coverageLimit = l
                    ..contact = contact.text.trim()
                    ..active = active;
                  await store.upsertInsurer(i);
                })) {
                  nav.pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
