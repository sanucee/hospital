import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_app/data/hospital_store.dart';
import 'package:hospital_app/data/lan_backend.dart';
import 'package:hospital_app/data/storage.dart';
import 'package:hospital_app/models/models.dart';
import 'package:naak_server/naak_server.dart';

/// Several computers running the app against one NAAK HMS Server.
void main() {
  late Directory dir;
  late NaakServer server;
  late int port;
  final stores = <HospitalStore>[];

  Future<void> startServer() async {
    server = NaakServer(
      dataDir: Directory('${dir.path}/data'),
      backupEvery: null,
      log: (_) {},
    );
    await server.start(port: port, address: InternetAddress.loopbackIPv4);
    port = server.port;
  }

  /// A computer with its own on-device cache.
  Future<HospitalStore> computer({MemoryStorage? cache}) async {
    final s = HospitalStore(
      backend: LanBackend(
        serverAddress: '127.0.0.1:$port',
        cache: cache ?? MemoryStorage(),
        retryDelay: const Duration(milliseconds: 100),
      ),
    );
    stores.add(s);
    await s.load();
    return s;
  }

  Future<void> until(bool Function() test, [String what = '']) async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (!test()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  LanBackend lan(HospitalStore s) => s.backend as LanBackend;

  /// Sets up the hospital with demo data and gives some demo staff logins.
  Future<HospitalStore> setUpHospital() async {
    final admin = await computer();
    await admin.setupHospital(
      name: 'Hospital Admin',
      email: 'admin',
      password: 'admin123',
    );
    for (final (id, login) in [
      ('USR-doc1', 'doctor'),
      ('USR-lab', 'lab'),
      ('USR-pha', 'pharmacy'),
      ('USR-nur', 'nurse'),
      ('USR-rec', 'reception'),
      ('USR-acc', 'accounts'),
    ]) {
      await admin.createLoginFor(id, email: login, password: 'secret1');
    }
    await until(() => lan(admin).pendingChanges == 0, 'setup to sync');
    return admin;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('naak_lan_test');
    port = 0;
    await startServer();
  });

  tearDown(() async {
    for (final s in stores) {
      s.dispose();
    }
    stores.clear();
    await server.stop();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await dir.delete(recursive: true);
  });

  test('setup, sign-in and live updates between departments', () async {
    final admin = await setUpHospital();
    expect(admin.currentUser!.role, UserRole.admin);
    expect(server.isSetUp, isTrue);

    final doctorPc = await computer();
    await doctorPc.login('doctor', 'secret1');
    await until(() => doctorPc.patients.isNotEmpty, 'doctor data');
    expect(doctorPc.currentUser!.id, 'USR-doc1');

    final labPc = await computer();
    await labPc.login('lab', 'secret1');
    await until(() => labPc.patients.isNotEmpty, 'lab data');
    // Salaries never reach the lab's computer.
    expect(labPc.salaries, isEmpty);
    expect(admin.salaries, isNotEmpty);

    // The doctor orders a test; it appears in the lab's queue.
    final mary = doctorPc.patients.firstWhere((p) => p.name == 'Mary Johnson');
    final c = await doctorPc.startConsultation(
      patientId: mary.id,
      doctorId: 'USR-doc1',
    );
    final order = (await doctorPc.orderLabTests(
      consultationId: c.id,
      testIds: ['LT-cbc'],
    )).single;
    await until(
      () => labPc.labQueue.any((o) => o.id == order.id),
      'order at the lab',
    );

    // The lab's result reaches the doctor, with a notification.
    await labPc.enterLabResult(labOrderId: order.id, result: 'Normal');
    await until(
      () =>
          doctorPc.labOrdersFor(consultationId: c.id).single.status ==
          LabOrderStatus.completed,
      'result at the doctor',
    );
    expect(doctorPc.unreadCount(doctorPc.currentUser!), greaterThan(0));
    // Invoice lines from both computers end up on one bill.
    await until(
      () => admin.invoiceForConsultation(c.id)?.lines.length == 2,
      'bill at admin',
    );
  });

  test('a refused change is undone and reported', () async {
    await setUpHospital();
    final labPc = await computer();
    await labPc.login('lab', 'secret1');
    await until(() => labPc.medicines.isNotEmpty, 'lab data');
    final med = labPc.medicines.first;
    final stock = med.stock;
    await labPc.restock(med.id, 50); // the lab may not change stock
    await until(() => labPc.syncError != null, 'refusal');
    await until(
      () => labPc.medicineById(med.id)!.stock == stock,
      'stock undone',
    );
    expect(server.db.doc('medicines', med.id)!['stock'], stock);
  });

  test('two pharmacies dispensing at once both deduct stock', () async {
    await setUpHospital();
    final a = await computer();
    final b = await computer();
    await a.login('pharmacy', 'secret1');
    await b.login('admin', 'admin123');
    await until(() => a.medicines.isNotEmpty && b.medicines.isNotEmpty);
    final id = a.medicines.first.id;
    final start = a.medicineById(id)!.stock;
    await Future.wait([a.restock(id, 10), b.restock(id, 5)]);
    await until(
      () =>
          a.medicineById(id)!.stock == start + 15 &&
          b.medicineById(id)!.stock == start + 15,
      'both restocks everywhere',
    );
    expect(server.db.doc('medicines', id)!['stock'], start + 15);
  });

  test(
    'keeps working offline and catches up when the server is back',
    () async {
      await setUpHospital();
      final labCache = MemoryStorage();
      final labPc = await computer(cache: labCache);
      await labPc.login('lab', 'secret1');
      final doctorPc = await computer();
      await doctorPc.login('doctor', 'secret1');
      await until(
        () => labPc.patients.isNotEmpty && doctorPc.patients.isNotEmpty,
      );

      final ali = doctorPc.patients.firstWhere((p) => p.name == 'Ali Hassan');
      final c = await doctorPc.startConsultation(
        patientId: ali.id,
        doctorId: 'USR-doc1',
      );
      final order = (await doctorPc.orderLabTests(
        consultationId: c.id,
        testIds: ['LT-fbs'],
      )).single;
      await until(() => labPc.labQueue.any((o) => o.id == order.id));

      // The server PC goes down.
      await server.stop();
      await until(() => !lan(labPc).online, 'lab to notice');
      await labPc.enterLabResult(labOrderId: order.id, result: '98 mg/dL');
      expect(lan(labPc).pendingChanges, greaterThan(0));
      expect(
        labPc.labOrdersFor(consultationId: c.id).single.result,
        '98 mg/dL',
      );

      // The lab PC is restarted while still offline: the result is still
      // there, from the device's own copy.
      labPc.dispose();
      stores.remove(labPc);
      final labAgain = await computer(cache: labCache);
      await until(() => labAgain.currentUser != null, 'offline session');
      expect(
        labAgain.labOrdersFor(consultationId: c.id).single.result,
        '98 mg/dL',
      );

      // The server comes back: the queued result is sent and reaches the
      // doctor.
      await startServer();
      await until(() => lan(labAgain).pendingChanges == 0, 'queue sent');
      await until(
        () =>
            doctorPc.labOrdersFor(consultationId: c.id).single.result ==
            '98 mg/dL',
        'result at the doctor',
      );
      expect(server.db.doc('labOrders', order.id)!['result'], '98 mg/dL');
    },
  );

  test('sign-in failures and signing out clear the computer', () async {
    await setUpHospital();
    final pc = await computer();
    await expectLater(
      pc.login('lab', 'wrong-password'),
      throwsA(isA<HospitalException>()),
    );
    await pc.login('nurse', 'secret1');
    await until(() => pc.patients.isNotEmpty);
    await pc.logout();
    await until(() => pc.session == SessionStatus.signedOut);
    expect(pc.patients, isEmpty);

    // A server that isn't there gives a clear message.
    final nowhere = HospitalStore(
      backend: LanBackend(serverAddress: '127.0.0.1:1', cache: MemoryStorage()),
    );
    stores.add(nowhere);
    await nowhere.load();
    await expectLater(
      nowhere.login('admin', 'admin123'),
      throwsA(
        isA<HospitalException>().having(
          (e) => e.message,
          'message',
          contains('Cannot reach the hospital server'),
        ),
      ),
    );
  });

  test('marking a staff member as left revokes their login', () async {
    final admin = await setUpHospital();
    final nursePc = await computer();
    await nursePc.login('nurse', 'secret1');
    await until(() => nursePc.patients.isNotEmpty);
    await admin.setStaffActive('USR-nur', false);
    await until(
      () => nursePc.session == SessionStatus.signedOut,
      'nurse signed out',
    );
    final again = await computer();
    await expectLater(
      again.login('nurse', 'secret1'),
      throwsA(isA<HospitalException>()),
    );
  });

  test('the cashier workflow passes the server money rules', () async {
    await setUpHospital();
    final desk = await computer();
    final accounts = await computer();
    await desk.login('reception', 'secret1');
    await accounts.login('accounts', 'secret1');
    await until(() => desk.patients.isNotEmpty && accounts.patients.isNotEmpty);

    final ali = desk.patients.firstWhere((p) => p.name == 'Ali Hassan');
    final bill = desk.outstandingFor(ali.id).first;
    await desk.openTill(openingFloat: 50);
    final receipt = await desk.takeCounterPayment(
      patientId: ali.id,
      invoiceIds: [bill.id],
      amount: 5,
      method: 'Cash',
      tendered: 5,
    );
    final payment = receipt.payments.first;
    final refund = await desk.requestRefund(
      payment.id,
      amount: 2,
      reason: 'Overcharged',
    );
    await until(() => accounts.refundById(refund.id) != null, 'refund seen');
    await accounts.decideRefund(refund.id, approve: true);
    await until(
      () => desk.refundById(refund.id)?.status == RefundStatus.approved,
      'approval at the desk',
    );
    await desk.payRefund(refund.id);
    await until(
      () => lan(desk).pendingChanges == 0 && lan(accounts).pendingChanges == 0,
      'all sent',
    );
    expect(desk.syncError, isNull);
    expect(accounts.syncError, isNull);
    expect(server.db.doc('refunds', refund.id)!['status'], 'paid');
    final payouts = server.db.docs['payments']!.values.where(
      (p) => p['refundId'] == refund.id,
    );
    expect(payouts.single['amount'], -2);
    final till = desk.myOpenTill!;
    await desk.closeTill(till.id, countedCash: 53);
    await until(() => lan(desk).pendingChanges == 0);
    expect(desk.syncError, isNull);
    expect(server.db.doc('tills', till.id)!['closedAt'], isNotNull);
  });

  test('changing and resetting passwords', () async {
    final admin = await setUpHospital();
    final nursePc = await computer();
    await nursePc.login('nurse', 'secret1');
    await until(() => nursePc.patients.isNotEmpty);
    await expectLater(
      nursePc.changeMyPassword('wrong!', 'better12'),
      throwsA(isA<HospitalException>()),
    );
    await nursePc.changeMyPassword('secret1', 'better12');
    // Still signed in on this computer, with a working session.
    await nursePc.recordVitals(
      admissionId: nursePc.activeAdmissions.first.id,
      pulse: 80,
    );
    await until(() => lan(nursePc).pendingChanges == 0, 'vitals sent');
    expect(nursePc.syncError, isNull);
    final other = await computer();
    await expectLater(
      other.login('nurse', 'secret1'),
      throwsA(isA<HospitalException>()),
    );
    await other.login('nurse', 'better12');

    // The nurse forgets it; the administrator sets a new one.
    await expectLater(
      nursePc.resetStaffPassword('USR-nur', 'nope123'),
      throwsA(isA<HospitalException>()),
    );
    expect(await admin.resetStaffPassword('USR-nur', 'given123'), isTrue);
    await until(
      () =>
          nursePc.session == SessionStatus.signedOut &&
          other.session == SessionStatus.signedOut,
      'nurse signed out everywhere',
    );
    final again = await computer();
    await again.login('nurse', 'given123');
    expect(again.currentUser!.id, 'USR-nur');
  });

  test('passwords on a single computer', () async {
    final s = HospitalStore(storage: MemoryStorage());
    await s.load();
    await s.login('nurse', '1234');
    await s.changeMyPassword('1234', 'better12');
    await s.logout();
    await expectLater(
      s.login('nurse', '1234'),
      throwsA(isA<HospitalException>()),
    );
    await s.login('admin', '1234');
    expect(s.hasLogin(s.userById('USR-nur')!), isTrue);
    expect(s.hasLogin(s.userById('USR-sup1')!), isFalse); // support staff
    await s.resetStaffPassword('USR-nur', 'given123');
    await s.logout();
    await s.login('nurse', 'given123');
    // The audit log records the change but never the password.
    await s.logout();
    await s.login('admin', '1234');
    expect(s.auditLog.any((e) => e.summary.contains('given123')), isFalse);
  });

  test('server address forms', () {
    expect(
      lanServerUri('192.168.1.10').toString(),
      'ws://192.168.1.10:8787/sync',
    );
    expect(
      lanServerUri('192.168.1.10:9000').toString(),
      'ws://192.168.1.10:9000/sync',
    );
    expect(
      lanServerUri('http://server.local:8787/').toString(),
      'ws://server.local:8787/sync',
    );
  });
}
