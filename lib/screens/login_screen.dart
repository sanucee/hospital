import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospital_store.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _error;

  static const _demoAccounts = [
    ('admin', 'Administrator', Icons.admin_panel_settings),
    ('reception', 'Reception', Icons.badge),
    ('doctor', 'Doctor', Icons.medical_services),
    ('lab', 'Laboratory', Icons.biotech),
    ('pharmacy', 'Pharmacy', Icons.local_pharmacy),
  ];

  void _login() {
    final ok = context.read<HospitalStore>().login(_user.text, _pass.text);
    if (!ok) setState(() => _error = 'Invalid username or password');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.local_hospital, size: 56, color: scheme.primary),
                    const SizedBox(height: 8),
                    Text('CareConnect HMS',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text('Doctor · Laboratory · Pharmacy',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.outline)),
                    const SizedBox(height: 24),
                    TextField(
                      key: const Key('username'),
                      controller: _user,
                      decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('password'),
                      controller: _pass,
                      obscureText: true,
                      onSubmitted: (_) => _login(),
                      decoration: const InputDecoration(
                          labelText: 'Password', prefixIcon: Icon(Icons.lock)),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('login'),
                      onPressed: _login,
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in'),
                    ),
                    const SizedBox(height: 24),
                    Text('Demo accounts (password 1234)',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (u, label, icon) in _demoAccounts)
                          ActionChip(
                            avatar: Icon(icon, size: 18),
                            label: Text(label),
                            onPressed: () {
                              _user.text = u;
                              _pass.text = '1234';
                              _login();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
