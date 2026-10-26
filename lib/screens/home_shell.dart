import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospital_store.dart';
import '../models/models.dart';
import 'admin/staff_screen.dart';
import 'billing/billing_screen.dart';
import 'dashboard_screen.dart';
import 'doctor/doctor_queue_screen.dart';
import 'lab/lab_screen.dart';
import 'notifications_screen.dart';
import 'pharmacy/pharmacy_screen.dart';
import 'reception/appointments_screen.dart';
import 'reception/patients_screen.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.builder, this.roles);

  final String label;
  final IconData icon;
  final WidgetBuilder builder;
  final Set<UserRole> roles;
}

final _destinations = <_Destination>[
  _Destination(
    'Dashboard',
    Icons.dashboard,
    (_) => const DashboardScreen(),
    UserRole.values.toSet(),
  ),
  _Destination(
    'Patients',
    Icons.people,
    (_) => const PatientsScreen(),
    UserRole.values.toSet(),
  ),
  _Destination('Appointments', Icons.event, (_) => const AppointmentsScreen(), {
    UserRole.admin,
    UserRole.receptionist,
    UserRole.doctor,
  }),
  _Destination(
    'Consultations',
    Icons.medical_services,
    (_) => const DoctorQueueScreen(),
    {UserRole.admin, UserRole.doctor},
  ),
  _Destination('Laboratory', Icons.biotech, (_) => const LabScreen(), {
    UserRole.admin,
    UserRole.labTechnician,
  }),
  _Destination(
    'Pharmacy',
    Icons.local_pharmacy,
    (_) => const PharmacyScreen(),
    {UserRole.admin, UserRole.pharmacist},
  ),
  _Destination('Billing', Icons.receipt_long, (_) => const BillingScreen(), {
    UserRole.admin,
    UserRole.receptionist,
    UserRole.pharmacist,
  }),
  _Destination('Staff', Icons.manage_accounts, (_) => const StaffScreen(), {
    UserRole.admin,
  }),
];

/// Lets any descendant switch the shell's current section by label, so e.g.
/// a dashboard tile can jump to the lab queue.
class ShellNavigator extends InheritedWidget {
  const ShellNavigator({super.key, required this.goTo, required super.child});

  final void Function(String label) goTo;

  static ShellNavigator? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNavigator>();

  @override
  bool updateShouldNotify(ShellNavigator oldWidget) => false;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    final user = store.currentUser!;
    final items = _destinations
        .where((d) => d.roles.contains(user.role))
        .toList();
    if (_index >= items.length) _index = 0;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final unread = store.unreadCount(user);

    void goTo(String label) {
      final i = items.indexWhere((d) => d.label == label);
      if (i >= 0) setState(() => _index = i);
    }

    final appBar = AppBar(
      title: Text(items[_index].label),
      actions: [
        IconButton(
          tooltip: 'Notifications',
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Account',
          icon: CircleAvatar(child: Text(user.name[0])),
          itemBuilder: (_) => [
            PopupMenuItem(
              enabled: false,
              child: ListTile(
                title: Text(user.name),
                subtitle: Text(user.role.label),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'logout', child: Text('Sign out')),
          ],
          onSelected: (v) {
            if (v == 'logout') store.logout();
          },
        ),
        const SizedBox(width: 8),
      ],
    );

    final body = ShellNavigator(
      goTo: goTo,
      child: Column(
        children: [
          if (store.syncError != null)
            MaterialBanner(
              leading: const Icon(Icons.sync_problem),
              content: Text(
                'A change could not be saved to the server and was '
                'undone: ${store.syncError}',
              ),
              actions: [
                TextButton(
                  onPressed: store.clearSyncError,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(items[_index].label),
              child: items[_index].builder(context),
            ),
          ),
        ],
      ),
    );

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1200,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: MediaQuery.sizeOf(context).width >= 1200
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Icon(Icons.local_hospital, size: 32),
              ),
              destinations: [
                for (final d in items)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      drawer: NavigationDrawer(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          Navigator.pop(context);
        },
        children: [
          DrawerHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.local_hospital, size: 40),
                const SizedBox(height: 8),
                Text(user.name, style: Theme.of(context).textTheme.titleMedium),
                Text(user.role.label),
              ],
            ),
          ),
          for (final d in items)
            NavigationDrawerDestination(
              icon: Icon(d.icon),
              label: Text(d.label),
            ),
        ],
      ),
      body: body,
    );
  }
}
