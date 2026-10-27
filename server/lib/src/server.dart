import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../protocol.dart';
import 'database.dart';
import 'permissions.dart';

/// NAAK HMS Server: the hospital's database on the local network.
///
/// Computers running the app connect over a WebSocket ([kSyncPath]), sign
/// in, send their changes and receive everyone else's as they happen. The
/// server checks every change against the role permissions ([kRules]),
/// saves it ([NaakDatabase]) and forwards it to the other computers that
/// may see it. It can also serve the web version of the app, so any
/// computer on the network can open it in a browser.
class NaakServer {
  NaakServer({
    required this.dataDir,
    this.webDir,
    this.backupEvery = const Duration(hours: 24),
    this.log = _print,
  });

  final Directory dataDir;
  final Directory? webDir;
  final Duration? backupEvery;
  final void Function(String) log;

  late final NaakDatabase db = NaakDatabase(dataDir);
  HttpServer? _http;
  Timer? _backupTimer;
  final _clients = <_Client>{};

  /// Requests are handled one at a time so each change sees the result of
  /// the one before.
  Future<void> _queue = Future.value();

  int get port => _http!.port;

  bool get isSetUp => db.accounts.values.any((a) => a.role == 'admin');

  Future<void> start({int port = kDefaultServerPort, Object? address}) async {
    await db.open();
    _http = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _http!.listen(_onRequest);
    if (backupEvery != null) {
      log('Backup: ${await db.backup()}');
      _backupTimer = Timer.periodic(backupEvery!, (_) {
        _serial(() async => log('Backup: ${await db.backup()}'));
      });
    }
  }

  Future<void> stop() async {
    _backupTimer?.cancel();
    for (final c in [..._clients]) {
      await c.socket.close();
    }
    await _http?.close(force: true);
    await _queue;
    await db.close();
  }

  Future<T> _serial<T>(Future<T> Function() f) {
    final result = _queue.then((_) => f());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  // ---------------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------------

  Future<void> _onRequest(HttpRequest req) async {
    try {
      if (req.uri.path == kSyncPath &&
          WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        ws.pingInterval = const Duration(seconds: 20);
        final c = _Client(ws, req.connectionInfo?.remoteAddress.address ?? '?');
        _clients.add(c);
        ws.listen(
          (m) => _serial(() => _onMessage(c, m)),
          onDone: () => _clients.remove(c),
          onError: (_) => _clients.remove(c),
        );
        return;
      }
      if (req.uri.path == '/health') {
        _json(req.response, {
          'name': 'NAAK HMS Server',
          'protocol': kProtocolVersion,
          'setUp': isSetUp,
          'connected': _clients.length,
        });
        return;
      }
      await _serveFile(req);
    } catch (e) {
      log('Request failed: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  void _json(HttpResponse res, Object body) {
    res.headers.contentType = ContentType.json;
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.write(jsonEncode(body));
    res.close();
  }

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'application/javascript',
    'mjs': 'application/javascript',
    'json': 'application/json',
    'css': 'text/css',
    'png': 'image/png',
    'ico': 'image/x-icon',
    'svg': 'image/svg+xml',
    'wasm': 'application/wasm',
    'otf': 'font/otf',
    'ttf': 'font/ttf',
    'frag': 'application/octet-stream',
    'bin': 'application/octet-stream',
  };

  Future<void> _serveFile(HttpRequest req) async {
    final res = req.response;
    final root = webDir;
    if (root == null || !root.existsSync()) {
      res.headers.contentType = ContentType.html;
      res.write(
        '<h1>NAAK HMS Server is running</h1>'
        '<p>Connect the NAAK HMS app to this computer\'s address, port '
        '$port.</p>',
      );
      await res.close();
      return;
    }
    final rel = Uri.decodeComponent(req.uri.path).replaceAll('\\', '/');
    var file = File(
      '${root.path}/${rel.isEmpty || rel == '/' ? 'index.html' : rel}',
    );
    final rootPath = root.absolute.path;
    // Stay inside the web folder; unknown paths get the app (it routes).
    if (!file.absolute.path.startsWith(rootPath) ||
        rel.split('/').contains('..') ||
        !file.existsSync()) {
      file = File('${root.path}/index.html');
    }
    final ext = file.path.split('.').last.toLowerCase();
    res.headers.set('Content-Type', _types[ext] ?? 'application/octet-stream');
    res.headers.set('Cache-Control', 'no-cache');
    await res.addStream(file.openRead());
    await res.close();
  }

  // ---------------------------------------------------------------------------
  // Sync protocol
  // ---------------------------------------------------------------------------

  Future<void> _onMessage(_Client c, Object? raw) async {
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final rid = m['rid'];
    void reply(Map<String, dynamic> body) =>
        c.send({'type': 'reply', 'rid': rid, ...body});
    void fail(String error) => reply({'ok': false, 'error': error});

    try {
      switch (m['type']) {
        case 'login':
          final acct = _findLogin(m['login'] as String? ?? '');
          if (acct == null || !acct.checkPassword(m['password'] ?? '')) {
            return fail('Invalid user name or password');
          }
          return reply(await _startSession(c, acct));
        case 'resume':
          final uid = db.sessions[m['token']];
          final acct = uid == null ? null : db.accounts[uid];
          if (acct == null) return fail('expired');
          c.account = acct;
          c.token = m['token'];
          return reply(_sessionInfo(acct, m['token']));
        case 'setup':
          if (isSetUp) {
            return fail(
              'This server already has a hospital set up. Sign in with an '
              'existing account.',
            );
          }
          final err = _checkNewLogin(m['login'], m['password']);
          if (err != null) return fail(err);
          final acct = Account.create(
            login: m['login'],
            password: m['password'],
            role: 'admin',
            staffId: m['staffId'],
          );
          await db.putAccount(acct);
          log('Hospital set up by ${acct.login}');
          return reply(await _startSession(c, acct));
      }

      final acct = c.account;
      if (acct == null) return fail('Sign in first');
      switch (m['type']) {
        case 'logout':
          if (c.token != null) await db.putSession(c.token!, null);
          c
            ..account = null
            ..token = null
            ..subscribed = false;
          return reply({'ok': true});
        case 'subscribe':
          c.subscribed = true;
          return reply({
            'ok': true,
            'docs': {
              for (final col in readableBy(acct.role))
                col: db.docs[col] ?? const {},
            },
          });
        case 'write':
          return reply(await _write(c, acct, m));
        case 'allocate':
          final counter = m['counter'] as String;
          final counters = {...?db.doc('meta', 'counters')};
          final next = ((counters[counter] as num?)?.toInt() ?? 0) + 1;
          counters[counter] = next;
          await db.putDocs([('meta', 'counters', counters)]);
          return reply({'ok': true, 'value': next});
        case 'initCounters':
          if (acct.role != 'admin') return fail('Administrators only');
          await db.putDocs([
            (
              'meta',
              'counters',
              {
                ...?db.doc('meta', 'counters'),
                ...(m['counters'] as Map).cast<String, dynamic>(),
              },
            ),
          ]);
          return reply({'ok': true});
        case 'createLogin':
          if (acct.role != 'admin') return fail('Administrators only');
          final err = _checkNewLogin(m['login'], m['password']);
          if (err != null) return fail(err);
          if (!kStaffRoles.contains(m['role'])) return fail('Unknown role');
          final created = Account.create(
            login: m['login'],
            password: m['password'],
            role: m['role'],
            staffId: m['staffId'],
          );
          await db.putAccount(created);
          return reply({'ok': true, 'uid': created.uid});
        case 'revoke':
          if (acct.role != 'admin') return fail('Administrators only');
          final uid = m['uid'] as String;
          await db.removeAccount(uid);
          for (final other in [..._clients]) {
            if (other.account?.uid == uid) {
              other.send({'type': 'revoked'});
              await other.socket.close();
            }
          }
          return reply({'ok': true});
        case 'changePassword':
          if (!acct.checkPassword(m['old'] ?? '')) {
            return fail('The current password is wrong');
          }
          final err = _checkNewLogin(acct.login, m['password'], self: acct);
          if (err != null) return fail(err);
          final updated = Account(
            uid: acct.uid,
            login: acct.login,
            salt: acct.salt,
            hash: hashPassword(m['password'], acct.salt),
            role: acct.role,
            staffId: acct.staffId,
          );
          await db.putAccount(updated);
          c.account = updated;
          return reply({'ok': true});
      }
      return fail('Unknown request ${m['type']}');
    } catch (e) {
      log('Error handling ${m['type']}: $e');
      return fail('Server error: $e');
    }
  }

  Account? _findLogin(String login) {
    final l = login.trim().toLowerCase();
    for (final a in db.accounts.values) {
      if (a.login == l) return a;
    }
    return null;
  }

  String? _checkNewLogin(Object? login, Object? password, {Account? self}) {
    if (login is! String || login.trim().isEmpty) return 'Enter a user name';
    if (password is! String || password.length < 6) {
      return 'Password must be at least 6 characters';
    }
    final existing = _findLogin(login);
    if (existing != null && existing.uid != self?.uid) {
      return '"${login.trim()}" is already in use';
    }
    return null;
  }

  Future<Map<String, dynamic>> _startSession(_Client c, Account acct) async {
    final token = newToken();
    await db.putSession(token, acct.uid);
    c
      ..account = acct
      ..token = token;
    log('${acct.login} signed in from ${c.address}');
    return _sessionInfo(acct, token);
  }

  Map<String, dynamic> _sessionInfo(Account a, String token) => {
    'ok': true,
    'token': token,
    'uid': a.uid,
    'login': a.login,
    'role': a.role,
    'staffId': a.staffId,
    'readable': readableBy(a.role),
  };

  /// Applies a batch of changes atomically: all are checked first, and if
  /// any is refused none is applied and the sender gets the current
  /// versions back to undo its local copy.
  Future<Map<String, dynamic>> _write(
    _Client c,
    Account acct,
    Map<String, dynamic> m,
  ) async {
    final ops = [
      for (final o in (m['ops'] as List))
        Op.fromJson((o as Map).cast<String, dynamic>()),
    ];
    // Work out the result of every op in order (a batch may touch the same
    // document twice) before saving anything.
    final pending = <String, Map<String, dynamic>?>{};
    Map<String, dynamic>? current(Op o) {
      final key = '${o.collection}\u0000${o.id}';
      return pending.containsKey(key)
          ? pending[key]
          : db.doc(o.collection, o.id);
    }

    for (final o in ops) {
      final cur = current(o);
      final why = refusal(
        o,
        role: acct.role,
        staffId: acct.staffId,
        current: cur,
      );
      if (why != null) {
        log('Refused for ${acct.login}: $why');
        return {
          'ok': false,
          'error': why,
          'docs': [
            for (final x in ops)
              if (canRead(acct.role, x.collection))
                DocState(
                  x.collection,
                  x.id,
                  db.doc(x.collection, x.id),
                ).toJson(),
          ],
        };
      }
      pending['${o.collection}\u0000${o.id}'] = o.applyTo(cur);
    }

    final changes = [
      for (final MapEntry(key: k, value: d) in pending.entries)
        (k.split('\u0000').first, k.split('\u0000').last, d),
    ];
    await db.putDocs(changes);
    final states = [for (final (col, id, d) in changes) DocState(col, id, d)];
    for (final other in _clients) {
      final acc = other.account;
      if (other == c || !other.subscribed || acc == null) continue;
      final visible = [
        for (final s in states)
          if (canRead(acc.role, s.collection)) s.toJson(),
      ];
      if (visible.isNotEmpty) other.send({'type': 'changes', 'docs': visible});
    }
    return {
      'ok': true,
      'docs': [
        for (final s in states)
          if (canRead(acct.role, s.collection)) s.toJson(),
      ],
    };
  }
}

class _Client {
  _Client(this.socket, this.address);

  final WebSocket socket;
  final String address;
  Account? account;
  String? token;
  bool subscribed = false;

  void send(Map<String, dynamic> m) {
    if (socket.readyState == WebSocket.open) socket.add(jsonEncode(m));
  }
}

void _print(String s) => stdout.writeln('${DateTime.now()}  $s');
