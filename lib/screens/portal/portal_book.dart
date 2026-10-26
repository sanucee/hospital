import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/hospital_store.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Online booking: pick a doctor, a day and a free time.
class PortalBookPage extends StatefulWidget {
  const PortalBookPage({super.key, required this.onBooked});

  final VoidCallback onBooked;

  @override
  State<PortalBookPage> createState() => _PortalBookPageState();
}

class _PortalBookPageState extends State<PortalBookPage> {
  String? _doctorId;
  DateTime? _day;
  DateTime? _slot;
  final _reason = TextEditingController();
  bool _busy = false;

  /// The days shown to choose from.
  static const _horizon = 28;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final doctors = store.bookableDoctors;
    final text = Theme.of(context).textTheme;
    if (doctors.isEmpty) {
      return EmptyState(
        'Online booking is not available. Please call '
        '${store.profile.phone.isEmpty ? 'the hospital' : store.profile.phone}.',
        icon: Icons.phone,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('1. Choose a doctor', style: text.titleMedium),
        const SizedBox(height: 8),
        for (final d in doctors) _doctorCard(store, d),
        if (_doctorId != null) ...[
          const SizedBox(height: 16),
          Text('2. Choose a day', style: text.titleMedium),
          const SizedBox(height: 8),
          _days(store),
        ],
        if (_day != null) ...[
          const SizedBox(height: 16),
          Text('3. Choose a time', style: text.titleMedium),
          const SizedBox(height: 8),
          _times(store),
        ],
        if (_slot != null) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason for the visit (optional)',
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.event_available),
              title: Text(
                '${store.userName(_doctorId!)} · ${fmtDate(_slot)} at '
                '${fmtTime(_slot)}',
              ),
              subtitle: Text(
                'Consultation fee ${money(store.userById(_doctorId!)?.consultationFee ?? 0)}, '
                'paid at the visit. You will get a confirmation and reminders '
                'by SMS or email.',
              ),
              trailing: FilledButton(
                key: const Key('portal-confirm'),
                onPressed: _busy ? null : () => _book(store),
                child: const Text('Confirm booking'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _doctorCard(HospitalStore store, StaffUser d) {
    final s = store.scheduleFor(d.id)!;
    final next = store.nextAvailableSlot(
      d.id,
      from: DateTime.now().add(PortalOperations.minimumNotice),
      days: _horizon,
    );
    final selected = _doctorId == d.id;
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.medical_services)),
        title: Text(d.name),
        subtitle: Text(
          '${d.specialization ?? 'Doctor'} · ${money(d.consultationFee)}\n'
          '${s.summary}\n'
          '${next == null ? 'No free times in the next 4 weeks' : 'Next free: ${fmtDate(next)} ${fmtTime(next)}'}',
        ),
        isThreeLine: true,
        selected: selected,
        onTap: () => setState(() {
          _doctorId = d.id;
          _day = next == null
              ? null
              : DateTime(next.year, next.month, next.day);
          _slot = null;
        }),
      ),
    );
  }

  List<DateTime> _free(HospitalStore store, DateTime day) {
    final earliest = DateTime.now().add(PortalOperations.minimumNotice);
    return store
        .availableSlots(_doctorId!, day)
        .where((t) => !t.isBefore(earliest))
        .toList();
  }

  Widget _days(HospitalStore store) {
    final today = DateTime.now();
    final days = [
      for (var i = 0; i < _horizon; i++)
        DateTime(today.year, today.month, today.day + i),
    ].where((d) => _free(store, d).isNotEmpty).toList();
    if (days.isEmpty) {
      return const Text('No free times in the next 4 weeks.');
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final d in days)
          ChoiceChip(
            label: Text('${kWeekdays[d.weekday - 1]} ${d.day}/${d.month}'),
            selected: _day == d,
            onSelected: (_) => setState(() {
              _day = d;
              _slot = null;
            }),
          ),
      ],
    );
  }

  Widget _times(HospitalStore store) {
    final slots = _free(store, _day!);
    if (slots.isEmpty) return const Text('That day is now fully booked.');
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (i, t) in slots.indexed)
          ChoiceChip(
            key: Key('portal-time-$i'),
            label: Text(fmtTime(t)),
            selected: _slot == t,
            onSelected: (_) => setState(() => _slot = t),
          ),
      ],
    );
  }

  Future<void> _book(HospitalStore store) async {
    setState(() => _busy = true);
    final at = _slot!;
    final ok = await guarded(
      context,
      () =>
          store.portalBook(doctorId: _doctorId!, at: at, reason: _reason.text),
      success: 'Booked for ${fmtDate(at)} at ${fmtTime(at)}',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onBooked();
  }
}
