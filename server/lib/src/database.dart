import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A sign-in account. Passwords are stored only as salted PBKDF2 hashes.
class Account {
  Account({
    required this.uid,
    required this.login,
    required this.salt,
    required this.hash,
    required this.role,
    this.staffId,
  });

  final String uid;

  /// Lower-case user name or email.
  final String login;
  final String salt;
  final String hash;
  final String role;
  final String? staffId;

  static Account create({
    required String login,
    required String password,
    required String role,
    String? staffId,
  }) {
    final salt = _randomHex(16);
    return Account(
      uid: 'UID-${_randomHex(12)}',
      login: login.trim().toLowerCase(),
      salt: salt,
      hash: hashPassword(password, salt),
      role: role,
      staffId: staffId,
    );
  }

  bool checkPassword(String password) =>
      _constantTimeEquals(hashPassword(password, salt), hash);

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'login': login,
    'salt': salt,
    'hash': hash,
    'role': role,
    'staffId': staffId,
  };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    uid: j['uid'],
    login: j['login'],
    salt: j['salt'],
    hash: j['hash'],
    role: j['role'],
    staffId: j['staffId'],
  );
}

/// PBKDF2-HMAC-SHA256.
String hashPassword(String password, String salt, {int iterations = 60000}) {
  final hmac = Hmac(sha256, utf8.encode(password));
  var u = hmac.convert([...utf8.encode(salt), 0, 0, 0, 1]).bytes;
  final out = List<int>.of(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return base64.encode(out);
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

final _random = Random.secure();

String _randomHex(int bytes) => [
  for (var i = 0; i < bytes; i++)
    _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();

String newToken() => _randomHex(32);

/// The hospital's data on this computer's disk.
///
/// Everything is held in memory (the app does the same on each device) and
/// every change is appended to `journal.jsonl` before it is acknowledged, so
/// a crash or power cut loses nothing that was confirmed. The journal is
/// regularly folded into `snapshot.json` (written to a temporary file, then
/// swapped in), and dated copies of the snapshot are kept in `backups/`.
class NaakDatabase {
  NaakDatabase(this.dir, {this.keepBackups = 30, this.compactAfter = 2000});

  final Directory dir;
  final int keepBackups;
  final int compactAfter;

  /// collection → id → document.
  final docs = <String, Map<String, Map<String, dynamic>>>{};
  final accounts = <String, Account>{};

  /// Sign-in token → account uid.
  final sessions = <String, String>{};

  IOSink? _journal;
  int _journalEntries = 0;

  File get _snapshotFile => File('${dir.path}/snapshot.json');
  File get _journalFile => File('${dir.path}/journal.jsonl');
  Directory get backupDir => Directory('${dir.path}/backups');

  Future<void> open() async {
    dir.createSync(recursive: true);
    if (_snapshotFile.existsSync()) {
      final s = jsonDecode(_snapshotFile.readAsStringSync()) as Map;
      for (final MapEntry(key: c, value: m) in (s['docs'] as Map).entries) {
        docs[c as String] = {
          for (final MapEntry(key: id, value: d) in (m as Map).entries)
            id as String: (d as Map).cast<String, dynamic>(),
        };
      }
      for (final a in (s['accounts'] as List)) {
        final acct = Account.fromJson((a as Map).cast<String, dynamic>());
        accounts[acct.uid] = acct;
      }
      sessions.addAll((s['sessions'] as Map).cast<String, String>());
    }
    if (_journalFile.existsSync()) {
      for (final line in _journalFile.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        try {
          _replay((jsonDecode(line) as Map).cast<String, dynamic>());
        } on FormatException {
          // A line cut short by a power cut: everything before it is kept.
          break;
        }
      }
    }
    await compact();
  }

  void _replay(Map<String, dynamic> e) {
    switch (e['t']) {
      case 'doc':
        _setDoc(e['c'], e['id'], (e['d'] as Map?)?.cast<String, dynamic>());
      case 'acct':
        if (e['a'] == null) {
          accounts.remove(e['uid']);
        } else {
          accounts[e['uid']] = Account.fromJson(
            (e['a'] as Map).cast<String, dynamic>(),
          );
        }
      case 'sess':
        if (e['uid'] == null) {
          sessions.remove(e['tok']);
        } else {
          sessions[e['tok']] = e['uid'];
        }
    }
  }

  void _setDoc(String c, String id, Map<String, dynamic>? d) {
    if (d == null) {
      docs[c]?.remove(id);
    } else {
      (docs[c] ??= {})[id] = d;
    }
  }

  Map<String, dynamic>? doc(String c, String id) => docs[c]?[id];

  /// Stores new versions of documents (null deletes).
  Future<void> putDocs(
    Iterable<(String, String, Map<String, dynamic>?)> changes,
  ) => _append([
    for (final (c, id, d) in changes) {'t': 'doc', 'c': c, 'id': id, 'd': d},
  ]);

  Future<void> putAccount(Account a) => _append([
    {'t': 'acct', 'uid': a.uid, 'a': a.toJson()},
  ]);

  Future<void> removeAccount(String uid) => _append([
    {'t': 'acct', 'uid': uid, 'a': null},
    for (final MapEntry(key: tok, value: u) in sessions.entries)
      if (u == uid) {'t': 'sess', 'tok': tok, 'uid': null},
  ]);

  /// Gives the account [uid] a new password and signs it out everywhere.
  Future<Account> setPassword(String uid, String password) async {
    final old = accounts[uid]!;
    final fresh = Account.create(
      login: old.login,
      password: password,
      role: old.role,
      staffId: old.staffId,
    );
    final updated = Account(
      uid: old.uid,
      login: old.login,
      salt: fresh.salt,
      hash: fresh.hash,
      role: old.role,
      staffId: old.staffId,
    );
    await _append([
      {'t': 'acct', 'uid': uid, 'a': updated.toJson()},
      for (final MapEntry(key: tok, value: u) in sessions.entries)
        if (u == uid) {'t': 'sess', 'tok': tok, 'uid': null},
    ]);
    return updated;
  }

  Future<void> putSession(String token, String? uid) => _append([
    {'t': 'sess', 'tok': token, 'uid': uid},
  ]);

  Future<void> _append(List<Map<String, dynamic>> entries) async {
    if (entries.isEmpty) return;
    final j = _journal!;
    for (final e in entries) {
      _replay(e);
      j.writeln(jsonEncode(e));
    }
    await j.flush();
    _journalEntries += entries.length;
    if (_journalEntries >= compactAfter) await compact();
  }

  /// Folds the journal into the snapshot.
  Future<void> compact() async {
    await _journal?.flush();
    await _journal?.close();
    final tmp = File('${_snapshotFile.path}.tmp');
    tmp.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'savedAt': DateTime.now().toIso8601String(),
        'docs': docs,
        'accounts': [for (final a in accounts.values) a.toJson()],
        'sessions': sessions,
      }),
      flush: true,
    );
    tmp.renameSync(_snapshotFile.path);
    _journalFile.writeAsStringSync('', flush: true);
    _journal = _journalFile.openWrite(mode: FileMode.append);
    _journalEntries = 0;
  }

  /// Saves a dated copy of the database in `backups/` and removes the
  /// oldest beyond [keepBackups]. Returns the backup's path.
  Future<String> backup() async {
    await compact();
    backupDir.createSync(recursive: true);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'naak-hms-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
    final path = '${backupDir.path}/$name';
    _snapshotFile.copySync(path);
    final old =
        backupDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in old.skip(keepBackups)) {
      f.deleteSync();
    }
    return path;
  }

  Future<void> close() async {
    await compact();
    await _journal?.close();
    _journal = null;
  }
}
