import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';
import 'firebase_backend.dart';

/// Set with `--dart-define=FIREBASE_EMULATOR_HOST=localhost` to run against
/// the local Firebase emulators instead of a real project.
const _emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');

/// Options for the emulators; they accept any project with a `demo-` id.
const _emulatorOptions = FirebaseOptions(
  apiKey: 'demo-key',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-hospital',
);

Future<FirebaseBackend> createFirebaseBackend() async {
  final useEmulator = _emulatorHost.isNotEmpty;
  final options = useEmulator
      ? _emulatorOptions
      : DefaultFirebaseOptions.currentPlatform;
  await Firebase.initializeApp(options: options);

  final db = FirebaseFirestore.instance;
  // Keep a full offline copy so every department can keep working through a
  // network outage; queued writes sync when the connection returns.
  db.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  if (useEmulator) {
    db.useFirestoreEmulator(_emulatorHost, 8080);
    await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
  }

  return FirebaseBackend(
    db: db,
    auth: FirebaseAuth.instance,
    createAuthUser: (email, password) async {
      // Creating an account signs into it, so do that on a secondary app to
      // keep the administrator signed in on the main one.
      const name = 'staff-admin';
      final isNew = !Firebase.apps.any((a) => a.name == name);
      final app = isNew
          ? await Firebase.initializeApp(name: name, options: options)
          : Firebase.app(name);
      final auth = FirebaseAuth.instanceFor(app: app);
      if (isNew && useEmulator) {
        await auth.useAuthEmulator(_emulatorHost, 9099);
      }
      final cred = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await auth.signOut();
      return cred.user!.uid;
    },
  );
}
