import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/hospital_store.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(HospitalApp(store: HospitalStore()..load()));
}

class HospitalApp extends StatelessWidget {
  const HospitalApp({super.key, required this.store});

  final HospitalStore store;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        title: 'CareConnect HMS',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const _Gate(),
      ),
    );
  }

  ThemeData _theme(Brightness b) => ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: Colors.teal, brightness: b),
        useMaterial3: true,
        inputDecorationTheme:
            const InputDecorationTheme(border: OutlineInputBorder()),
      );
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HospitalStore>();
    if (!store.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return store.currentUser == null ? const LoginScreen() : const HomeShell();
  }
}
