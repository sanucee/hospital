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
  bool _busy = false;

  static const _demoAccounts = [
    ('admin', 'Administrator', Icons.admin_panel_settings),
    ('reception', 'Reception', Icons.badge),
    ('doctor', 'Doctor', Icons.medical_services),
    ('lab', 'Laboratory', Icons.biotech),
    ('pharmacy', 'Pharmacy', Icons.local_pharmacy),
  ];

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<HospitalStore>().login(_user.text, _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remote = context.read<HospitalStore>().isRemote;
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
                    Text(
                      'CareConnect HMS',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      'Doctor · Laboratory · Pharmacy',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.outline),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      key: const Key('username'),
                      controller: _user,
                      keyboardType: remote ? TextInputType.emailAddress : null,
                      decoration: InputDecoration(
                        labelText: remote ? 'Email' : 'Username',
                        prefixIcon: const Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('password'),
                      controller: _pass,
                      obscureText: true,
                      onSubmitted: (_) => _login(),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('login'),
                      onPressed: _busy ? null : _login,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: const Text('Sign in'),
                    ),
                    const SizedBox(height: 24),
                    if (remote) ...[
                      Row(
                        children: [
                          const Icon(Icons.cloud_done, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Data is shared across all devices',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => const _SetupDialog(),
                        ),
                        child: const Text('First time? Set up a new hospital'),
                      ),
                    ] else ...[
                      Text(
                        'Demo accounts (password 1234)',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
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

/// First-run setup for a new Firebase project: creates the administrator.
class _SetupDialog extends StatefulWidget {
  const _SetupDialog();

  @override
  State<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends State<_SetupDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _demo = true;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _pass.text.length < 6) {
      setState(
        () => _error = 'Enter your name, email and a password of 6+ characters',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await context.read<HospitalStore>().setupHospital(
        name: _name.text,
        email: _email.text,
        password: _pass.text,
        demoData: _demo,
      );
      nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set up a new hospital'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This creates the administrator account. It only works '
              'once per Firebase project.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Your name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _demo,
              title: const Text('Include demo patients and staff'),
              subtitle: const Text(
                'Lab tests and medicines are added either way',
              ),
              onChanged: (v) => setState(() => _demo = v!),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create hospital'),
        ),
      ],
    );
  }
}
