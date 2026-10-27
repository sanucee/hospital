import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:naak_server/protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'backend.dart';
import 'storage.dart';

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

/// Shares the hospital through NAAK HMS Server on the local network: the
/// hospital's own database, with no cloud service.
///
/// The device keeps the data as the server last confirmed it, plus a queue
/// of its own changes the server hasn't confirmed yet, both saved on the
/// device. What the app shows is the confirmed data with the queued changes
/// applied on top, so staff keep working while the server is unreachable
/// (a network fault, the server PC restarting); the queue is sent, in
/// order, when the connection returns. The server checks each change
/// against the role permissions; a refused change is dropped and the
/// screen shows the server's version again.
class LanBackend implements HospitalBackend {
  LanBackend({
    required String serverAddress,
    StorageBackend? cache,
    ChannelFactory? connect,
    this.retryDelay = const Duration(seconds: 3),
  }) : serverUri = lanServerUri(serverAddress),
       _cache = cache ?? const SharedPrefsStorage('lan_cache_v1'),
       _connect = connect ?? WebSocketChannel.connect;

  final Uri serverUri;
  final StorageBackend _cache;
  final ChannelFactory _connect;
  final Duration retryDelay;

  BackendListener? _listener;

  /// Documents as the server last confirmed them.
  Docs _confirmed = {};

  /// Changes not yet confirmed, oldest first.
  final List<List<Op>> _pending = [];
  _Session? _session;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _online = false;
  bool _flushing = false;
  bool _disposed = false;
  Timer? _retry;
  Duration _nextDelay = Duration.zero;
  int _rid = 0;
  final _replies = <int, Completer<Map<String, dynamic>>>{};

  /// Audit entries already sent by a role that can't read the audit log.
  final _appended = <String>{};

  Future<void> _lastSave = Future.value();

  /// True while connected to the server.
  bool get online => _online;

  /// Changes waiting to reach the server.
  int get pendingChanges => _pending.fold(0, (s, b) => s + b.length);

  /// Fires whenever [online] or [pendingChanges] may have changed, for the
  /// connection indicator.
  final status = ValueNotifier<int>(0);

  void _statusChanged() {
    if (!_disposed) status.value++;
  }

  @override
  bool get isRemote => true;

  @override
  bool get emailLogins => false;

  @override
  bool get portalAccounts => false;

  // ---------------------------------------------------------------------------
  // Start-up and connection
  // ---------------------------------------------------------------------------

  @override
  Future<void> start(BackendListener listener) async {
    _listener = listener;
    final raw = await _cache.read();
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (j['server'] == serverUri.toString() && j['session'] != null) {
          _session = _Session.fromJson(j['session']);
          _confirmed = _docsFrom(j['confirmed']);
          for (final b in (j['pending'] as List)) {
            _pending.add([
              for (final o in (b as List))
                Op.fromJson((o as Map).cast<String, dynamic>()),
            ]);
          }
        }
      } catch (_) {
        // An unreadable cache is ignored; the server has the data.
      }
    }
    final s = _session;
    if (s != null) {
      // Work from the saved copy straight away, even before (or without) a
      // connection to the server.
      _emit();
      listener.onSession(SessionStatus.ready, staffId: s.staffId);
    } else {
      listener.onSession(SessionStatus.signedOut);
    }
    _open();
  }

  void _open() {
    if (_disposed || _channel != null) return;
    final WebSocketChannel ch;
    try {
      ch = _connect(serverUri);
    } catch (_) {
      _scheduleRetry();
      return;
    }
    _channel = ch;
    _sub = ch.stream.listen(
      _onMessage,
      onDone: () => _closed(ch),
      onError: (_) => _closed(ch),
    );
    ch.ready.then((_) => _connected(ch), onError: (_) => _closed(ch));
  }

  Future<void> _connected(WebSocketChannel ch) async {
    if (_channel != ch) return;
    _online = true;
    _nextDelay = Duration.zero;
    _statusChanged();
    final s = _session;
    if (s == null) return;
    final r = await _request({'type': 'resume', 'token': s.token});
    if (r == null) return;
    if (r['ok'] != true) {
      // Signed out on the server (password reset, login removed).
      await _endSession();
      return;
    }
    _session = _Session.fromJson(r);
    await _flush();
    await _subscribe();
  }

  void _closed(WebSocketChannel ch) {
    if (_channel != ch) return;
    _online = false;
    _channel = null;
    _statusChanged();
    _sub?.cancel();
    _sub = null;
    for (final c in _replies.values) {
      if (!c.isCompleted) c.complete(const {'ok': false, 'offline': true});
    }
    _replies.clear();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _retry?.cancel();
    final delay = _nextDelay;
    _nextDelay = _nextDelay == Duration.zero
        ? retryDelay
        : (_nextDelay * 2 > const Duration(seconds: 30)
              ? const Duration(seconds: 30)
              : _nextDelay * 2);
    _retry = Timer(delay, _open);
  }

  /// Waits up to [timeout] for the connection (for actions that need the
  /// server, such as signing in).
  Future<bool> _ensureOnline({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (_online) return true;
    if (_channel == null) {
      _retry?.cancel();
      _nextDelay = Duration.zero;
      _open();
    }
    final end = DateTime.now().add(timeout);
    while (!_online && DateTime.now().isBefore(end) && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _online;
  }

  HospitalException get _unreachable => HospitalException(
    'Cannot reach the hospital server at ${serverUri.host}:${serverUri.port}. '
    'Check that NAAK HMS Server is running and this computer is on the '
    'hospital network.',
  );

  /// Sends a request and waits for its reply; null if the connection is
  /// lost or the server doesn't answer within [timeout].
  Future<Map<String, dynamic>?> _request(
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final ch = _channel;
    if (ch == null || !_online) return null;
    final rid = ++_rid;
    final c = Completer<Map<String, dynamic>>();
    _replies[rid] = c;
    try {
      ch.sink.add(jsonEncode({...body, 'rid': rid, 'v': kProtocolVersion}));
    } on StateError {
      // The connection closed under us; it will be retried.
      _replies.remove(rid);
      _closed(ch);
      return null;
    }
    try {
      final r = await c.future.timeout(timeout);
      return r['offline'] == true ? null : r;
    } on TimeoutException {
      _replies.remove(rid);
      return null;
    }
  }

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> m;
    try {
      m = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'reply':
        _replies.remove(m['rid'])?.complete(m);
      case 'changes':
        for (final d in (m['docs'] as List)) {
          _setConfirmed(DocState.fromJson((d as Map).cast<String, dynamic>()));
        }
        _save();
        _emit();
      case 'revoked':
        _endSession();
    }
  }

  Future<void> _subscribe() async {
    final r = await _request({'type': 'subscribe'}, timeout: _bigTimeout);
    if (r == null || r['ok'] != true) return;
    _confirmed = _docsFrom(r['docs']);
    _save();
    _emit();
    final s = _session;
    if (s != null) {
      _listener?.onSession(SessionStatus.ready, staffId: s.staffId);
    }
  }

  static const _bigTimeout = Duration(seconds: 60);

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  void _setConfirmed(DocState s) {
    if (s.data == null) {
      _confirmed[s.collection]?.remove(s.id);
    } else {
      (_confirmed[s.collection] ??= {})[s.id] = s.data!;
    }
  }

  /// The confirmed documents with the queued changes applied.
  Docs _visible() {
    final v = <String, Map<String, Map<String, dynamic>>>{
      for (final MapEntry(key: c, value: m) in _confirmed.entries)
        c: {for (final MapEntry(key: id, value: d) in m.entries) id: d},
    };
    for (final batch in _pending) {
      for (final o in batch) {
        final col = v[o.collection] ??= {};
        final next = o.applyTo(col[o.id]);
        if (next == null) {
          col.remove(o.id);
        } else {
          col[o.id] = next;
        }
      }
    }
    return v;
  }

  void _emit() {
    final v = _visible();
    _listener?.onDocs({
      for (final c in kCollections)
        c: {
          for (final MapEntry(key: id, value: d) in (v[c] ?? {}).entries)
            id: _clone(d),
        },
    });
  }

  static const _counterFields = {
    'medicines': {'stock'},
    'storeItems': {'stock'},
    'invoices': {'amountPaid', 'insurerPaid'},
    'claims': {'amountPaid'},
  };

  @override
  Future<void> push(Docs docs) {
    final s = _session;
    if (s == null) return Future.value();
    final visible = _visible();
    final ops = <Op>[];
    for (final c in s.readable) {
      final next = docs[c] ?? const {};
      final prev = visible[c] ?? const {};
      for (final MapEntry(key: id, value: data) in next.entries) {
        final old = prev[id];
        if (old == null) {
          ops.add(Op.set(c, id, _clone(data)));
          continue;
        }
        final changed = <String, dynamic>{};
        final inc = <String, num>{};
        for (final MapEntry(key: k, value: v) in data.entries) {
          if (jsonEquals(old[k], v)) continue;
          final o = old[k];
          if (o is num &&
              v is num &&
              (_counterFields[c]?.contains(k) ?? false)) {
            inc[k] = v - o;
          } else {
            changed[k] = _cloneValue(v);
          }
        }
        for (final k in old.keys) {
          if (!data.containsKey(k)) changed[k] = null;
        }
        if (changed.isNotEmpty || inc.isNotEmpty) {
          ops.add(Op.merge(c, id, changed, increments: inc));
        }
      }
      for (final id in prev.keys) {
        if (!next.containsKey(id)) ops.add(Op.delete(c, id));
      }
    }
    // Roles that can't read the audit log still add their own entries.
    for (final c in kAppendOnlyCollections) {
      if (s.readable.contains(c)) continue;
      for (final MapEntry(key: id, value: d) in (docs[c] ?? {}).entries) {
        if (_appended.add(id)) ops.add(Op.set(c, id, _clone(d)));
      }
    }
    if (ops.isEmpty) return Future.value();
    _pending.add(ops);
    _statusChanged();
    _save();
    _flush();
    return Future.value();
  }

  /// Sends queued changes in order while connected.
  Future<void> _flush() async {
    if (_flushing || !_online || _session == null) return;
    _flushing = true;
    var changed = false;
    try {
      while (_pending.isNotEmpty && _online) {
        final batch = _pending.first;
        final r = await _request({
          'type': 'write',
          'ops': [for (final o in batch) o.toJson()],
        });
        if (r == null) break; // offline: keep it for later
        _pending.removeAt(0);
        for (final d in (r['docs'] as List? ?? const [])) {
          _setConfirmed(DocState.fromJson((d as Map).cast<String, dynamic>()));
        }
        changed = true;
        if (r['ok'] != true) {
          _listener?.onSyncError(
            HospitalException(r['error'] as String? ?? 'Change refused'),
          );
        }
      }
    } finally {
      _flushing = false;
    }
    _statusChanged();
    if (changed) {
      _save();
      _emit();
    }
  }

  void _save() {
    final s = _session;
    final data = s == null
        ? null
        : jsonEncode({
            'server': serverUri.toString(),
            'session': s.toJson(),
            'confirmed': _confirmed,
            'pending': [
              for (final b in _pending) [for (final o in b) o.toJson()],
            ],
          });
    _lastSave = _lastSave.then(
      (_) => data == null ? _cache.clear() : _cache.write(data),
    );
  }

  @override
  Future<int?> allocate(String counter) async {
    final r = await _request({
      'type': 'allocate',
      'counter': counter,
    }, timeout: const Duration(seconds: 5));
    return r?['ok'] == true ? (r!['value'] as num).toInt() : null;
  }

  @override
  Future<void> initCounters(Map<String, int> counters) async {
    await _request({'type': 'initCounters', 'counters': counters});
  }

  // ---------------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------------

  Future<void> _beginSession(Map<String, dynamic>? r) async {
    if (r == null) throw _unreachable;
    if (r['ok'] != true) {
      throw HospitalException(r['error'] as String? ?? 'Sign-in failed');
    }
    _session = _Session.fromJson(r);
    _pending.clear();
    _confirmed = {};
    _listener?.onSession(SessionStatus.loading);
    await _subscribe();
  }

  @override
  Future<void> signIn(String login, String password) async {
    if (!await _ensureOnline()) throw _unreachable;
    await _beginSession(
      await _request({'type': 'login', 'login': login, 'password': password}),
    );
  }

  @override
  Future<void> signOut() async {
    // Hand over anything still queued before leaving this computer.
    if (_pending.isNotEmpty && _online) await _flush();
    await _request({'type': 'logout'}, timeout: const Duration(seconds: 3));
    await _endSession();
  }

  Future<void> _endSession() async {
    _session = null;
    _confirmed = {};
    _pending.clear();
    _appended.clear();
    _save();
    await _lastSave;
    _listener?.onDocs({});
    _listener?.onSession(SessionStatus.signedOut);
  }

  @override
  String? get signedInUid => _session?.uid;

  @override
  String? get signedInEmail => _session?.login;

  @override
  Future<String> setupHospital({
    required String email,
    required String password,
    required String staffId,
  }) async {
    if (!await _ensureOnline()) throw _unreachable;
    await _beginSession(
      await _request({
        'type': 'setup',
        'login': email,
        'password': password,
        'staffId': staffId,
      }),
    );
    return _session!.uid;
  }

  @override
  Future<String> createLogin({
    required String email,
    required String password,
    required String role,
    required String staffId,
  }) async {
    if (!await _ensureOnline()) throw _unreachable;
    final r = await _request({
      'type': 'createLogin',
      'login': email,
      'password': password,
      'role': role,
      'staffId': staffId,
    });
    if (r == null) throw _unreachable;
    if (r['ok'] != true) throw HospitalException(r['error'] as String);
    return r['uid'] as String;
  }

  @override
  Future<void> revokeLogin(String uid) async {
    if (!await _ensureOnline()) throw _unreachable;
    final r = await _request({'type': 'revoke', 'uid': uid});
    if (r == null) throw _unreachable;
    if (r['ok'] != true) throw HospitalException(r['error'] as String);
  }

  static final _noPortal = HospitalException(
    'Patient portal accounts need the Firebase edition; they are not '
    'available with a hospital server.',
  );

  @override
  Future<void> registerPortalAccount({
    required String email,
    required String password,
    required String patientId,
    required Map<String, dynamic> patient,
  }) => Future.error(_noPortal);

  @override
  Future<String> createPortalLogin({
    required String email,
    required String password,
    required String patientId,
  }) => Future.error(_noPortal);

  @override
  Future<void> dispose() async {
    _disposed = true;
    status.dispose();
    _retry?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    await _lastSave;
  }
}

/// `ws://host:port/sync` for an address typed as `192.168.1.10`,
/// `192.168.1.10:8787` or `http://server:8787`.
Uri lanServerUri(String address) {
  var a = address.trim();
  if (!a.contains('://')) a = 'ws://$a';
  final u = Uri.parse(a);
  return Uri(
    scheme: u.scheme == 'https' || u.scheme == 'wss' ? 'wss' : 'ws',
    host: u.host,
    port: u.hasPort ? u.port : kDefaultServerPort,
    path: kSyncPath,
  );
}

class _Session {
  _Session({
    required this.token,
    required this.uid,
    required this.login,
    required this.role,
    required this.staffId,
    required this.readable,
  });

  final String token;
  final String uid;
  final String login;
  final String role;
  final String? staffId;
  final List<String> readable;

  Map<String, dynamic> toJson() => {
    'token': token,
    'uid': uid,
    'login': login,
    'role': role,
    'staffId': staffId,
    'readable': readable,
  };

  factory _Session.fromJson(Map<String, dynamic> j) => _Session(
    token: j['token'],
    uid: j['uid'],
    login: j['login'] ?? '',
    role: j['role'],
    staffId: j['staffId'],
    readable: (j['readable'] as List).cast<String>(),
  );
}

Docs _docsFrom(Object? raw) => {
  for (final MapEntry(key: c, value: m) in ((raw as Map?) ?? const {}).entries)
    c as String: {
      for (final MapEntry(key: id, value: d) in (m as Map).entries)
        id as String: (d as Map).cast<String, dynamic>(),
    },
};

Map<String, dynamic> _clone(Map<String, dynamic> m) =>
    m.map((k, v) => MapEntry(k, _cloneValue(v)));

Object? _cloneValue(Object? v) => switch (v) {
  Map() => v.map((k, e) => MapEntry(k as String, _cloneValue(e))),
  List() => v.map(_cloneValue).toList(),
  _ => v,
};
