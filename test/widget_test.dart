import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/firebase_backend.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/data/storage.dart';
import 'package:hospital_app/main.dart';
import 'package:hospital_app/models/models.dart';

void main() {
  Future<HospitalStore> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = HospitalStore(storage: MemoryStorage());
    await store.load();
    await tester.pumpWidget(HospitalApp(store: store));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('login shows role-specific navigation', (tester) async {
    await pumpApp(tester);
    expect(find.text('CareConnect HMS'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('username')), 'lab');
    await tester.enterText(find.byKey(const Key('password')), '1234');
    await tester.tap(find.byKey(const Key('login')));
    await tester.pumpAndSettle();

    expect(find.text('Welcome, Kwame Mensah'), findsOneWidget);
    expect(find.text('Laboratory'), findsWidgets);
    expect(find.text('Pharmacy'), findsNothing);
  });

  testWidgets('every section renders for admin', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Administrator'));
    await tester.pumpAndSettle();

    for (final section in [
      'Patients',
      'Appointments',
      'Consultations',
      'Laboratory',
      'Pharmacy',
      'Inpatients',
      'Operation theatre',
      'Billing',
      'Finance',
      'Reports',
      'Staff',
      'Audit log',
      'Dashboard',
    ]) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text(section),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: section);
    }
  });

  testWidgets('doctor opens consultation from queue', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Doctor'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Consultations'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mary Johnson'), findsOneWidget);
    await tester.tap(find.text('Start').first);
    await tester.pumpAndSettle();
    expect(find.text('Consultation – Mary Johnson'), findsOneWidget);
    expect(find.text('Order tests'), findsOneWidget);
    expect(find.text('Prescribe'), findsOneWidget);
  });

  testWidgets('Firebase mode signs in by email and offers first-run setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = HospitalStore(
      backend: FirebaseBackend(
        db: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(),
        createAuthUser: (_, _) async => 'uid',
      ),
    );
    await store.load();
    await tester.pumpWidget(HospitalApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Demo accounts (password 1234)'), findsNothing);
    await tester.tap(find.text('First time? Set up a new hospital'));
    await tester.pumpAndSettle();
    expect(find.text('Create hospital'), findsOneWidget);
  });

  testWidgets('every tab of the new sections renders', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Administrator'));
    await tester.pumpAndSettle();
    final sections = {
      'Inpatients': ['Admitted', 'Rooms', 'Discharged'],
      'Operation theatre': ['Day schedule', 'Upcoming', 'Theatres'],
      'Finance': [
        'Overview',
        'Expenses',
        'Payroll',
        'Salaries',
        'Supplier bills',
      ],
      'Staff': ['Directory', 'Leave'],
      'Billing': ['Invoices', 'Insurance claims', 'Insurers'],
      'Pharmacy': ['To dispense', 'Inventory', 'Purchase orders', 'Suppliers'],
    };
    for (final MapEntry(key: section, value: tabs) in sections.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text(section),
        ),
      );
      await tester.pumpAndSettle();
      for (final t in tabs) {
        await tester.tap(
          find.descendant(
            of: find.byType(TabBar),
            matching: find.textContaining(t),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$section / $t');
      }
    }
    // The seeded inpatient and the expenses show up.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Inpatients'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Admitted ('));
    await tester.pumpAndSettle();
    expect(find.textContaining('Peter Okafor'), findsOneWidget);
    expect(find.textContaining('Room charges so far'), findsOneWidget);
  });

  testWidgets('an insured bill shows the split and runs a claim', (
    tester,
  ) async {
    final store = await pumpApp(tester);
    await tester.tap(find.text('Administrator'));
    await tester.pumpAndSettle();
    final ali = store.patients.firstWhere((p) => p.name == 'Ali Hassan');
    await store.startConsultation(patientId: ali.id, doctorId: 'USR-doc2');
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Billing'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ali Hassan · AXA Health'));
    await tester.pumpAndSettle();

    expect(find.text('Insurance share (estimated)'), findsOneWidget);
    expect(find.text('Patient share'), findsOneWidget);
    await tester.tap(find.text('Create claim'));
    await tester.pumpAndSettle();
    expect(find.text('Submit to insurer'), findsOneWidget);
    await tester.tap(find.text('Submit to insurer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Record decision'), findsOneWidget);
    expect(store.claims.single.status, ClaimStatus.submitted);
  });

  testWidgets('nursing chart: record observations, see them in the audit log', (
    tester,
  ) async {
    final store = await pumpApp(tester);
    await tester.tap(find.text('Administrator'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Inpatients'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nursing chart'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nursing chart – Peter Okafor'), findsOneWidget);
    expect(find.textContaining('NEWS2'), findsWidgets);

    await tester.tap(find.text('Record observations'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Pulse /min'), '125');
    await tester.enterText(
      find.widgetWithText(TextField, 'Resp. rate /min'),
      '26',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('NEWS2 5 (incomplete)'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.patientsAtRisk, isNotEmpty);

    for (final tab in ['Medications', 'Notes']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    expect(find.textContaining('NBM'), findsNothing);
    expect(find.textContaining('Nil by mouth'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Audit log'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Created observations'), findsOneWidget);
  });

  testWidgets('book from free slots, edit hours and skip a reminder', (
    tester,
  ) async {
    final store = await pumpApp(tester);
    await tester.tap(find.text('Administrator'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Appointments'),
      ),
    );
    await tester.pumpAndSettle();

    // Book with the doctor's next free slot.
    final before = store.appointments.length;
    await tester.tap(find.text('Book appointment'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ListTile),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(store.doctors.first.name).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('min'), findsWidgets);
    await tester.tap(find.text('Next available'));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Book'));
    await tester.pumpAndSettle();
    expect(store.appointments.length, before + 1);
    final booked = store.appointments.last;
    expect(booked.scheduledAt.isAfter(DateTime.now()), isTrue);
    // One reminder for each lead time that is still ahead.
    expect(
      store.remindersFor(booked.id),
      hasLength(
        store.profile.reminderHours
            .where(
              (h) => booked.scheduledAt
                  .subtract(Duration(hours: h))
                  .isAfter(DateTime.now()),
            )
            .length,
      ),
    );

    // Edit a doctor's hours.
    await tester.tap(find.text('Doctor schedules'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mon–Fri'), findsWidgets);
    await tester.tap(find.byTooltip('Edit working hours').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Working hours –'), findsOneWidget);
    await tester.tap(
      find.byTooltip('Delete').first,
    ); // drop Mon's first session
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      store.scheduleFor(store.doctors.first.id)!.sessionsOn(DateTime.monday),
      hasLength(1),
    );

    // Skip a queued reminder.
    await tester.tap(find.textContaining('Reminders'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Scheduled ('));
    await tester.pumpAndSettle();
    final queued = store.upcomingReminders.length;
    await tester.tap(find.text('Skip').first);
    await tester.pumpAndSettle();
    expect(store.upcomingReminders.length, queued - 1);
    expect(tester.takeException(), isNull);
  });
}
