import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'backend.dart';

/// Creates a Firebase Auth account without signing the current user out
/// (normally done through a secondary `FirebaseApp`). Returns the new uid.
typedef CreateAuthUser = Future<String> Function(
    String email, String password);

/// Shares the hospital between devices through Cloud Firestore.
///
/// Every record is its own document, and local changes are written as
/// field-level merges, so two departments editing the same record (the lab
/// entering a result while the doctor marks an earlier one reviewed) don't
/// overwrite each other. Fields that several devices change concurrently
/// are written as atomic operations: medicine stock and invoice payments as
/// increments, notification read receipts as array unions. Invoice lines
/// live in their own collection so every department can bill the same visit
/// at once.
///
/// Firestore's offline cache means the app keeps working without a
/// connection; writes are queued and synced when it returns.
class FirebaseBackend implements HospitalBackend {
  FirebaseBackend({
    required this.db,
    required this.auth,
    required this.createAuthUser,
  });

  final FirebaseFirestore db;
  final FirebaseAuth auth;
  final CreateAuthUser createAuthUser;

  BackendListener? _listener;
  final Docs _cache = {};
  final _received = <String>{};
  final _dataSubs = <StreamSubscription>[];
  StreamSubscription? _authSub;
  StreamSubscription? _roleSub;
  String? _staffId;
  bool _ready = false;

  static const _batchLimit = 450;

  @override
  bool get isRemote => true;

  @override
  Future<void> start(BackendListener listener) async {
    _listener = listener;
    _authSub = auth.authStateChanges().listen(_onAuth);
  }

  void _onAuth(User? user) {
    _roleSub?.cancel();
    _roleSub = null;
    _detachData();
    final l = _listener!;
    if (user == null) {
      l.onSession(SessionStatus.signedOut);
      return;
    }
    l.onSession(SessionStatus.loading);
    _roleSub = db
        .doc('roles/${user.uid}')
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      final staffId = snap.data()?['staffId'] as String?;
      if (!snap.exists || staffId == null) {
        _detachData();
        l.onSession(SessionStatus.noAccess);
        return;
      }
      // During first-run setup the role exists locally before the server has
      // accepted it; listening to data now would be rejected.
      if (snap.metadata.hasPendingWrites) return;
      if (staffId == _staffId && _dataSubs.isNotEmpty) return;
      _detachData();
      _staffId = staffId;
      l.onSession(SessionStatus.loading);
      _attachData();
    }, onError: (Object e) {
      _detachData();
      l.onSession(SessionStatus.noAccess);
    });
  }

  void _attachData() {
    for (final c in kCollections) {
      _dataSubs.add(db.collection(c).snapshots().listen((snap) {
        _cache[c] = {for (final d in snap.docs) d.id: _clone(d.data())};
        _received.add(c);
        _emit();
      }, onError: (Object e) => _listener?.onSyncError(e)));
    }
  }

  void _detachData() {
    for (final s in _dataSubs) {
      s.cancel();
    }
    _dataSubs.clear();
    _cache.clear();
    _received.clear();
    _staffId = null;
    _ready = false;
    _listener?.onDocs({});
  }

  void _emit() {
    final l = _listener!;
    l.onDocs({
      for (final c in kCollections)
        c: {
          for (final MapEntry(key: id, value: d) in (_cache[c] ?? {}).entries)
            id: _clone(d),
        },
    });
    if (!_ready && _received.length == kCollections.length) {
      _ready = true;
      l.onSession(SessionStatus.ready, staffId: _staffId);
    }
  }

  @override
  Future<void> push(Docs docs) {
    final ops = <void Function(WriteBatch)>[];
    for (final c in kCollections) {
      final next = {
        for (final MapEntry(key: id, value: d) in (docs[c] ?? {}).entries)
          id: _clone(d),
      };
      final prev = _cache[c] ?? {};
      for (final MapEntry(key: id, value: data) in next.entries) {
        final ref = db.collection(c).doc(id);
        final old = prev[id];
        if (old == null) {
          ops.add((b) => b.set(ref, data));
          continue;
        }
        final changed = <String, dynamic>{
          for (final MapEntry(key: k, value: v) in data.entries)
            if (!jsonEquals(old[k], v)) k: _fieldWrite(c, k, old[k], v),
        };
        if (changed.isNotEmpty) {
          ops.add((b) => b.set(ref, changed, SetOptions(merge: true)));
        }
      }
      for (final id in prev.keys) {
        if (!next.containsKey(id)) {
          ops.add((b) => b.delete(db.collection(c).doc(id)));
        }
      }
      _cache[c] = next;
    }

    // Commits are queued locally and acknowledged by the server later; don't
    // wait for that, or every action would hang while offline.
    for (var i = 0; i < ops.length; i += _batchLimit) {
      final batch = db.batch();
      for (final op in ops.skip(i).take(_batchLimit)) {
        op(batch);
      }
      batch.commit().catchError((Object e) => _listener?.onSyncError(e));
    }
    return Future.value();
  }

  /// How a changed field is written. Counters that several devices change
  /// at once become atomic operations instead of overwrites.
  Object? _fieldWrite(String collection, String field, Object? old, Object? v) {
    if (old is num && v is num) {
      if ((collection == 'medicines' && field == 'stock') ||
          (collection == 'invoices' && field == 'amountPaid')) {
        return FieldValue.increment(v - old);
      }
    }
    if (collection == 'notifications' &&
        field == 'readBy' &&
        old is List &&
        v is List &&
        old.every(v.contains)) {
      return FieldValue.arrayUnion(v.where((e) => !old.contains(e)).toList());
    }
    return v;
  }

  @override
  Future<int?> allocate(String counter) async {
    final ref = db.doc('meta/counters');
    try {
      return await db.runTransaction<int>((tx) async {
        final snap = await tx.get(ref);
        final next = ((snap.data()?[counter] as num?)?.toInt() ?? 0) + 1;
        if (snap.exists) {
          tx.update(ref, {counter: next});
        } else {
          tx.set(ref, {counter: next});
        }
        return next;
      }).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Transactions need the server; callers fall back to a number that's
      // unique without coordination.
      return null;
    }
  }

  @override
  Future<void> initCounters(Map<String, int> counters) async {
    await db.doc('meta/counters').set(counters, SetOptions(merge: true));
  }

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw HospitalException(_authMessage(e));
    }
  }

  @override
  Future<void> signOut() => auth.signOut();

  @override
  String? get signedInUid => auth.currentUser?.uid;

  @override
  String? get signedInEmail => auth.currentUser?.email;

  @override
  Future<String> setupHospital({
    required String email,
    required String password,
    required String staffId,
  }) async {
    final UserCredential cred;
    try {
      cred = await auth.createUserWithEmailAndPassword(
          email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw HospitalException(_authMessage(e));
    }
    final uid = cred.user!.uid;
    // Security rules only allow this pair of writes while meta/setup doesn't
    // exist, so only the first person to set up becomes administrator.
    final batch = db.batch()
      ..set(db.doc('roles/$uid'), {'role': 'admin', 'staffId': staffId})
      ..set(db.doc('meta/setup'),
          {'createdAt': DateTime.now().toIso8601String(), 'by': uid});
    try {
      await batch.commit().timeout(const Duration(seconds: 20));
    } catch (_) {
      await cred.user!.delete().catchError((_) {});
      await auth.signOut();
      throw HospitalException('This Firebase project already has a hospital '
          'set up (or is unreachable). Sign in with an existing account.');
    }
    return uid;
  }

  @override
  Future<String> createLogin({
    required String email,
    required String password,
    required String role,
    required String staffId,
  }) async {
    final String uid;
    try {
      uid = await createAuthUser(email, password);
    } on FirebaseAuthException catch (e) {
      throw HospitalException(_authMessage(e));
    }
    await db.doc('roles/$uid').set({'role': role, 'staffId': staffId});
    return uid;
  }

  @override
  Future<void> revokeLogin(String uid) => db.doc('roles/$uid').delete();

  @override
  Future<void> dispose() async {
    await _authSub?.cancel();
    await _roleSub?.cancel();
    for (final s in _dataSubs) {
      await s.cancel();
    }
  }

  static String _authMessage(FirebaseAuthException e) => switch (e.code) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' ||
        'invalid-email' =>
          'Invalid email or password',
        'email-already-in-use' => 'That email already has an account',
        'weak-password' => 'Password must be at least 6 characters',
        'network-request-failed' => 'No connection to the server',
        'too-many-requests' => 'Too many attempts; try again later',
        _ => e.message ?? e.code,
      };
}

/// Deep copy, so neither side can mutate the other's maps and lists.
Map<String, dynamic> _clone(Map<String, dynamic> m) =>
    m.map((k, v) => MapEntry(k, _cloneValue(v)));

Object? _cloneValue(Object? v) => switch (v) {
      Map() => v.map((k, e) => MapEntry(k as String, _cloneValue(e))),
      List() => v.map(_cloneValue).toList(),
      _ => v,
    };
