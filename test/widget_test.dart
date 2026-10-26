import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/firebase_backend.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/data/storage.dart';
import 'package:hospital_app/main.dart';

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
      'Billing',
      'Staff',
      'Dashboard',
    ]) {
      await tester.tap(find.descendant(
          of: find.byType(NavigationRail), matching: find.text(section)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: section);
    }
  });

  testWidgets('doctor opens consultation from queue', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Doctor'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Consultations')));
    await tester.pumpAndSettle();

    expect(find.text('Mary Johnson'), findsOneWidget);
    await tester.tap(find.text('Start').first);
    await tester.pumpAndSettle();
    expect(find.text('Consultation – Mary Johnson'), findsOneWidget);
    expect(find.text('Order tests'), findsOneWidget);
    expect(find.text('Prescribe'), findsOneWidget);
  });

  testWidgets('Firebase mode signs in by email and offers first-run setup',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = HospitalStore(
        backend: FirebaseBackend(
      db: FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(),
      createAuthUser: (_, _) async => 'uid',
    ));
    await store.load();
    await tester.pumpWidget(HospitalApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Demo accounts (password 1234)'), findsNothing);
    await tester.tap(find.text('First time? Set up a new hospital'));
    await tester.pumpAndSettle();
    expect(find.text('Create hospital'), findsOneWidget);
  });
}
