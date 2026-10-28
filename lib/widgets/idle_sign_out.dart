import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/hospital_store.dart';

/// Signs the staff member out after the hospital's idle time (Hospital
/// details → "Sign staff out when not used for"), so nobody can use a shared
/// computer under someone else's name. Any touch, click, scroll or key
/// press counts as use.
class IdleSignOut extends StatefulWidget {
  const IdleSignOut({super.key, required this.child});

  final Widget child;

  @override
  State<IdleSignOut> createState() => _IdleSignOutState();
}

class _IdleSignOutState extends State<IdleSignOut> {
  Timer? _timer;
  int _minutes = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent _) {
    _restart();
    return false;
  }

  void _restart() {
    _timer?.cancel();
    if (_minutes <= 0) return;
    _timer = Timer(Duration(minutes: _minutes), _signOut);
  }

  Future<void> _signOut() async {
    final store = context.read<HospitalStore>();
    if (store.currentUser == null) return;
    // Offline with changes still to send: signing out would lose them, so
    // wait for the connection and try again later.
    if (store.backend.unsentChanges > 0) return _restart();
    try {
      await store.logout();
    } on HospitalException {
      _restart();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = context.select<HospitalStore, int>(
      (s) => s.profile.autoSignOutMinutes,
    );
    if (minutes != _minutes) {
      _minutes = minutes;
      _restart();
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restart(),
      onPointerSignal: (_) => _restart(),
      onPointerHover: (_) => _restart(),
      child: widget.child,
    );
  }
}
