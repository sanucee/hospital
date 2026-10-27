import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/connection_settings.dart';
import 'data/firebase_setup.dart';
import 'data/hospital_store.dart';
import 'data/lan_backend.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/portal/portal_shell.dart';
import 'widgets/common.dart';
import 'widgets/naak_logo.dart';

/// Build with `--dart-define=USE_FIREBASE=true` to share data between
/// devices through Firebase. Without it, data stays on this device.
const useFirebase = bool.fromEnvironment('USE_FIREBASE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (useFirebase) {
    final backend = await createFirebaseBackend();
    runApp(HospitalApp(store: HospitalStore(backend: backend)..load()));
    return;
  }
  runApp(NaakRoot(serverAddress: await ConnectionSettings.load()));
}

/// Lets the sign-in screen switch between this computer's own data and a
/// hospital server on the network.
class ServerConnection extends InheritedWidget {
  const ServerConnection({
    super.key,
    required this.address,
    required this.switchTo,
    required super.child,
  });

  /// The hospital server in use, or null for this computer only.
  final String? address;
  final Future<void> Function(String? address) switchTo;

  static ServerConnection? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServerConnection>();

  @override
  bool updateShouldNotify(ServerConnection old) => old.address != address;
}

/// Runs the app on this computer's own data, or on NAAK HMS Server at
/// [serverAddress], and swaps between them when the setting changes.
class NaakRoot extends StatefulWidget {
  const NaakRoot({super.key, this.serverAddress});

  final String? serverAddress;

  @override
  State<NaakRoot> createState() => _NaakRootState();
}

class _NaakRootState extends State<NaakRoot> {
  late String? _address = widget.serverAddress;
  late HospitalStore _store = _create(_address);

  static HospitalStore _create(String? address) => HospitalStore(
    backend: address == null ? null : LanBackend(serverAddress: address),
  )..load();

  Future<void> _switchTo(String? address) async {
    await ConnectionSettings.save(address);
    final old = _store;
    setState(() {
      _address = address;
      _store = _create(address);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ServerConnection(
    address: _address,
    switchTo: _switchTo,
    child: HospitalApp(key: ObjectKey(_store), store: _store),
  );
}

class HospitalApp extends StatelessWidget {
  const HospitalApp({super.key, required this.store});

  final HospitalStore store;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const _Gate(),
      ),
    );
  }

  ThemeData _theme(Brightness b) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: kNaakTeal, brightness: b),
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    if (!store.loaded || store.settingUp) return const _Loading();
    if (store.currentPatient != null) return const PortalShell();
    if (!store.isRemote) {
      return store.currentUser == null
          ? const LoginScreen()
          : const HomeShell();
    }
    return switch (store.session) {
      SessionStatus.signedOut => const LoginScreen(),
      SessionStatus.loading => const _Loading(
        message: 'Syncing hospital data…',
      ),
      SessionStatus.noAccess => const _NoAccess(),
      SessionStatus.ready =>
        store.setupIncomplete
            ? const _FinishSetup()
            : store.currentUser == null
            ? const _NoAccess()
            : const HomeShell(),
    };
  }
}

class _Loading extends StatelessWidget {
  const _Loading({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NaakMark(size: 72),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(message!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown when setup was interrupted after the administrator was created.
class _FinishSetup extends StatefulWidget {
  const _FinishSetup();

  @override
  State<_FinishSetup> createState() => _FinishSetupState();
}

class _FinishSetupState extends State<_FinishSetup> {
  final _name = TextEditingController();
  bool _demo = true;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final store = context.read<HospitalStore>();
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.construction, size: 56),
                const SizedBox(height: 12),
                const Text(
                  'Hospital setup was not finished',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Your name'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _demo,
                  title: const Text('Include demo patients and staff'),
                  onChanged: (v) => setState(() => _demo = v!),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (_name.text.trim().isEmpty) return;
                          setState(() => _busy = true);
                          await guarded(
                            context,
                            () => store.finishSetup(
                              name: _name.text,
                              demoData: _demo,
                            ),
                          );
                          if (mounted) setState(() => _busy = false);
                        },
                  child: const Text('Finish setup'),
                ),
                TextButton(
                  onPressed: store.logout,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_person, size: 56),
              const SizedBox(height: 12),
              const Text(
                'This account has no access to the hospital.',
                textAlign: TextAlign.center,
              ),
              const Text(
                'Ask an administrator to create your staff login.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.read<HospitalStore>().logout(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
