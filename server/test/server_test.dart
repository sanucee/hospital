import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:naak_server/naak_server.dart';
import 'package:test/test.dart';

/// A raw protocol client, as the app's LanBackend would talk.
class Client {
  Client._(this._ws) {
    _ws.listen((m) {
      final j = (jsonDecode(m as String) as Map).cast<String, dynamic>();
      if (j['type'] == 'reply') {
        _replies.remove(j['rid'])?.complete(j);
      } else {
        pushed.add(j);
      }
    });
  }

  static Future<Client> connect(int port) async =>
      Client._(await WebSocket.connect('ws://127.0.0.1:$port$kSyncPath'));

  final WebSocket _ws;
  final _replies = <int, Completer<Map<String, dynamic>>>{};
  final pushed = <Map<String, dynamic>>[];
  var _rid = 0;

  Future<Map<String, dynamic>> req(Map<String, dynamic> body) {
    final rid = ++_rid;
    final c = Completer<Map<String, dynamic>>();
    _replies[rid] = c;
    _ws.add(jsonEncode({...body, 'rid': rid}));
    return c.future.timeout(const Duration(seconds: 10));
  }

  Future<Map<String, dynamic>> write(List<Op> ops) => req({
    'type': 'write',
    'ops': [for (final o in ops) o.toJson()],
  });

  Future<void> close() => _ws.close();
}

Future<void> until(bool Function() test) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!test()) {
    if (DateTime.now().isAfter(end)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory dir;
  late NaakServer server;

  Future<NaakServer> startServer({int port = 0, Directory? web}) async {
    final s = NaakServer(
      dataDir: Directory('${dir.path}/data'),
      webDir: web,
      backupEvery: null,
      log: (_) {},
    );
    await s.start(port: port, address: InternetAddress.loopbackIPv4);
    return s;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('naak_server_test');
    server = await startServer();
  });

  tearDown(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  Future<Client> admin() async {
    final c = await Client.connect(server.port);
    final r = await c.req({
      'type': 'setup',
      'login': 'Admin',
      'password': 'secret1',
      'staffId': 'USR-admin',
    });
    expect(r['ok'], isTrue, reason: '$r');
    return c;
  }

  test('the hospital is set up once; sign-in checks the password', () async {
    final a = await admin();
    expect(server.isSetUp, isTrue);
    final b = await Client.connect(server.port);
    final again = await b.req({
      'type': 'setup',
      'login': 'x',
      'password': 'secret1',
      'staffId': 'X',
    });
    expect(again['ok'], isFalse);
    expect(
      (await b.req({
        'type': 'login',
        'login': 'admin',
        'password': 'wrong!',
      }))['ok'],
      isFalse,
    );
    final ok = await b.req({
      'type': 'login',
      'login': ' ADMIN ',
      'password': 'secret1',
    });
    expect(ok['ok'], isTrue);
    expect(ok['role'], 'admin');
    expect(ok['readable'], contains('salaries'));
    // Nothing works before signing in.
    final c = await Client.connect(server.port);
    expect((await c.req({'type': 'subscribe'}))['ok'], isFalse);
    // A saved token resumes the session.
    final d = await Client.connect(server.port);
    final resumed = await d.req({'type': 'resume', 'token': ok['token']});
    expect(resumed['staffId'], 'USR-admin');
    for (final x in [a, b, c, d]) {
      await x.close();
    }
  });

  test('changes are checked by role and forwarded to others', () async {
    final a = await admin();
    final created = await a.req({
      'type': 'createLogin',
      'login': 'lab',
      'password': 'secret2',
      'role': 'labTechnician',
      'staffId': 'USR-lab',
    });
    expect(created['ok'], isTrue);
    expect(
      (await a.req({
        'type': 'createLogin',
        'login': 'LAB',
        'password': 'secret2',
        'role': 'nurse',
      }))['ok'],
      isFalse,
    );

    final lab = await Client.connect(server.port);
    final session = await lab.req({
      'type': 'login',
      'login': 'lab',
      'password': 'secret2',
    });
    expect(session['readable'], isNot(contains('salaries')));
    await lab.req({'type': 'subscribe'});
    await a.req({'type': 'subscribe'});

    await a.write([
      const Op.set('medicines', 'm1', {'name': 'Para', 'stock': 10}),
      const Op.set('salaries', 'USR-lab', {'basic': 900}),
      const Op.set('labOrders', 'o1', {'status': 'ordered', 'result': ''}),
    ]);
    // The lab hears about the medicine and the order, not the salary.
    await until(() => lab.pushed.isNotEmpty);
    final seen = [
      for (final d in lab.pushed.single['docs'] as List) (d as Map)['c'],
    ];
    expect(seen, unorderedEquals(['medicines', 'labOrders']));

    // The lab may result an order but not change stock; a refused batch
    // changes nothing and returns the server's versions.
    final refused = await lab.write([
      const Op.merge('labOrders', 'o1', {'status': 'completed'}),
      const Op.merge('medicines', 'm1', {}, increments: {'stock': -5}),
    ]);
    expect(refused['ok'], isFalse);
    expect(refused['error'], contains('medicines'));
    expect(server.db.doc('labOrders', 'o1')!['status'], 'ordered');
    expect((refused['docs'] as List), hasLength(2));

    final ok = await lab.write([
      const Op.merge('labOrders', 'o1', {'status': 'completed', 'result': '5'}),
    ]);
    expect(ok['ok'], isTrue);
    expect(server.db.doc('labOrders', 'o1')!['result'], '5');
    await until(() => a.pushed.isNotEmpty);

    // The lab may set a patient's blood group, nothing else about them.
    await a.write([
      const Op.set('patients', 'p1', {'name': 'Pat', 'bloodGroup': ''}),
    ]);
    expect(
      (await lab.write([
        const Op.merge('patients', 'p1', {'bloodGroup': 'A+'}),
      ]))['ok'],
      isTrue,
    );
    expect(
      (await lab.write([
        const Op.merge('patients', 'p1', {'name': 'Changed'}),
      ]))['ok'],
      isFalse,
    );
    await a.close();
    await lab.close();
  });

  test('increments from two computers both count', () async {
    final a = await admin();
    await a.write([
      const Op.set('medicines', 'm1', {'name': 'Para', 'stock': 100}),
    ]);
    final b = await Client.connect(server.port);
    await b.req({'type': 'login', 'login': 'admin', 'password': 'secret1'});
    await Future.wait([
      a.write([
        const Op.merge('medicines', 'm1', {}, increments: {'stock': -3}),
      ]),
      b.write([
        const Op.merge('medicines', 'm1', {}, increments: {'stock': -4}),
      ]),
    ]);
    expect(server.db.doc('medicines', 'm1')!['stock'], 93);
    await a.close();
    await b.close();
  });

  test('own-name rules: leave, audit entries, requisitions', () async {
    final a = await admin();
    await a.req({
      'type': 'createLogin',
      'login': 'nurse',
      'password': 'secret3',
      'role': 'nurse',
      'staffId': 'USR-nur',
    });
    final n = await Client.connect(server.port);
    await n.req({'type': 'login', 'login': 'nurse', 'password': 'secret3'});
    Future<bool> ok(Op o) async => (await n.write([o]))['ok'] == true;

    expect(
      await ok(const Op.set('leaves', 'l1', {'staffId': 'USR-nur'})),
      true,
    );
    expect(
      await ok(const Op.set('leaves', 'l2', {'staffId': 'USR-doc'})),
      false,
    );
    expect(
      await ok(const Op.set('auditLog', 'a1', {'userId': 'USR-nur'})),
      true,
    );
    expect(await ok(const Op.merge('auditLog', 'a1', {'userId': 'x'})), false);
    const req = {'requestedBy': 'USR-nur', 'status': 'pending'};
    expect(await ok(const Op.set('requisitions', 'q1', req)), true);
    expect(
      await ok(const Op.merge('requisitions', 'q1', {'status': 'issued'})),
      false,
    );
    expect(
      await ok(const Op.merge('requisitions', 'q1', {'status': 'cancelled'})),
      true,
    );
    expect(await ok(const Op.set('salaries', 'x', {'basic': 1})), false);
    await a.close();
    await n.close();
  });

  test('sequence numbers are shared', () async {
    final a = await admin();
    final b = await Client.connect(server.port);
    await b.req({'type': 'login', 'login': 'admin', 'password': 'secret1'});
    final values = await Future.wait([
      for (var i = 0; i < 5; i++)
        (i.isEven ? a : b).req({'type': 'allocate', 'counter': 'mrn'}),
    ]);
    expect(values.map((v) => v['value']).toSet(), {1, 2, 3, 4, 5});
    await a.close();
    await b.close();
  });

  test('data and sessions survive a restart and a torn journal', () async {
    final a = await admin();
    final token = (await a.req({
      'type': 'login',
      'login': 'admin',
      'password': 'secret1',
    }))['token'];
    await a.write([
      const Op.set('patients', 'p1', {'name': 'Pat'}),
    ]);
    await a.write([
      const Op.merge('patients', 'p1', {'phone': '0803'}),
    ]);
    await a.close();
    await server.stop();
    // A power cut mid-write leaves half a line at the end of the journal.
    File('${dir.path}/data/journal.jsonl').writeAsStringSync(
      '{"t":"doc","c":"patients","id":"p2","d":{"na',
      mode: FileMode.append,
    );
    server = await startServer();
    expect(server.db.doc('patients', 'p1'), {'name': 'Pat', 'phone': '0803'});
    expect(server.db.doc('patients', 'p2'), isNull);
    final b = await Client.connect(server.port);
    expect((await b.req({'type': 'resume', 'token': token}))['ok'], isTrue);
    await b.close();
  });

  test('revoking a login signs that account out everywhere', () async {
    final a = await admin();
    final uid = (await a.req({
      'type': 'createLogin',
      'login': 'rec',
      'password': 'secret4',
      'role': 'receptionist',
      'staffId': 'USR-rec',
    }))['uid'];
    final r = await Client.connect(server.port);
    final token = (await r.req({
      'type': 'login',
      'login': 'rec',
      'password': 'secret4',
    }))['token'];
    await a.req({'type': 'revoke', 'uid': uid});
    await until(() => r.pushed.any((m) => m['type'] == 'revoked'));
    final again = await Client.connect(server.port);
    expect((await again.req({'type': 'resume', 'token': token}))['ok'], false);
    expect(
      (await again.req({
        'type': 'login',
        'login': 'rec',
        'password': 'secret4',
      }))['ok'],
      false,
    );
    await a.close();
    await again.close();
  });

  test('backups are dated copies, keeping the newest', () async {
    final db = NaakDatabase(Directory('${dir.path}/b'), keepBackups: 2);
    await db.open();
    await db.putDocs([
      ('patients', 'p1', {'name': 'Pat'}),
    ]);
    final paths = <String>[];
    for (var i = 0; i < 3; i++) {
      paths.add(await db.backup());
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    }
    final left = db.backupDir.listSync().map((f) => f.path).toList();
    expect(left, hasLength(2));
    final saved = jsonDecode(File(paths.last).readAsStringSync()) as Map;
    expect(saved['docs']['patients']['p1']['name'], 'Pat');
    await db.close();
  });

  test('serves the web app and a health check', () async {
    await server.stop();
    final web = Directory('${dir.path}/web')..createSync();
    File('${web.path}/index.html').writeAsStringSync('<html>NAAK</html>');
    server = await startServer(web: web);
    final http = HttpClient();
    Future<String> get(String path) async {
      final res = await (await http.get(
        '127.0.0.1',
        server.port,
        path,
      )).close();
      return res.transform(utf8.decoder).join();
    }

    expect(jsonDecode(await get('/health'))['name'], 'NAAK HMS Server');
    expect(await get('/'), contains('NAAK'));
    expect(await get('/some/route'), contains('NAAK'));
    expect(await get('/../data/snapshot.json'), contains('NAAK'));
    http.close();
  });
}
