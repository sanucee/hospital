import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/connection_settings.dart';
import '../data/hospital_store.dart';
import '../data/lan_backend.dart';
import '../main.dart' show ServerConnection;
import '../widgets/naak_logo.dart';
import 'portal/portal_login.dart';

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
  bool _patient = false;

  static const _demoAccounts = [
    ('admin', 'Administrator', Icons.admin_panel_settings),
    ('reception', 'Reception', Icons.badge),
    ('doctor', 'Doctor', Icons.medical_services),
    ('lab', 'Laboratory', Icons.biotech),
    ('pharmacy', 'Pharmacy', Icons.local_pharmacy),
    ('nurse', 'Nurse', Icons.healing),
    ('radiology', 'Radiology', Icons.monitor_heart),
    ('stores', 'Stores', Icons.inventory_2),
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
    final store = context.read<HospitalStore>();
    final remote = store.isRemote;
    final emailLogin = store.backend.emailLogins;
    final portal = !remote || store.backend.portalAccounts;
    final connection = ServerConnection.of(context);
    final server = connection?.address;
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
                    const Center(child: NaakMark(size: 72)),
                    const SizedBox(height: 12),
                    Text(
                      kAppName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      kAppTagline,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.outline),
                    ),
                    const SizedBox(height: 16),
                    if (portal) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Staff'),
                            icon: Icon(Icons.badge),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Patients'),
                            icon: Icon(Icons.person),
                          ),
                        ],
                        selected: {_patient},
                        onSelectionChanged: (v) =>
                            setState(() => _patient = v.first),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_patient && portal)
                      const PortalLoginForm()
                    else ...[
                      TextField(
                        key: const Key('username'),
                        controller: _user,
                        keyboardType: emailLogin
                            ? TextInputType.emailAddress
                            : null,
                        decoration: InputDecoration(
                          labelText: emailLogin ? 'Email' : 'Username',
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                                server == null
                                    ? 'Data is shared across all devices'
                                    : 'Hospital server $server',
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
                          child: const Text(
                            'First time? Set up a new hospital',
                          ),
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
                    if (connection != null) ...[
                      const Divider(height: 32),
                      _ServerSetting(connection: connection),
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

/// Shows which data this computer uses and lets the user switch between
/// its own data and a hospital server on the network.
class _ServerSetting extends StatelessWidget {
  const _ServerSetting({required this.connection});

  final ServerConnection connection;

  @override
  Widget build(BuildContext context) {
    final address = connection.address;
    final store = context.watch<HospitalStore>();
    final lan = store.backend is LanBackend
        ? store.backend as LanBackend
        : null;
    return Row(
      children: [
        Icon(
          address == null ? Icons.computer : Icons.lan,
          size: 18,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            address == null
                ? 'Data on this computer only'
                : 'Hospital server: $address'
                      '${lan != null && !lan.online ? ' (not reachable yet)' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(
          key: const Key('server-settings'),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => _ServerDialog(connection: connection),
          ),
          child: const Text('Change'),
        ),
      ],
    );
  }
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog({required this.connection});

  final ServerConnection connection;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late bool _network = widget.connection.address != null;
  late final _address = TextEditingController(
    text: widget.connection.address ?? '',
  );
  String? _message;
  bool _ok = false;
  bool _busy = false;

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final setUp = await ConnectionSettings.check(_address.text);
      _ok = true;
      _message = setUp
          ? 'Connected to NAAK HMS Server.'
          : 'Connected. No hospital is set up on this server yet: after '
                'saving, choose "First time? Set up a new hospital".';
    } catch (e) {
      _ok = false;
      _message = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Where is the hospital data?'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<bool>(
              groupValue: _network,
              onChanged: (v) => setState(() => _network = v!),
              child: const Column(
                children: [
                  RadioListTile<bool>(
                    value: false,
                    title: Text('This computer only'),
                    subtitle: Text('For one PC, or to try NAAK HMS'),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    title: Text('Hospital server on the network'),
                    subtitle: Text(
                      'All computers share the data held on the server PC',
                    ),
                  ),
                ],
              ),
            ),
            if (_network) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('server-address'),
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Server address',
                  hintText: '192.168.1.10 or 192.168.1.10:8787',
                  helperText: 'Shown in the NAAK HMS Server window',
                ),
                onChanged: (_) => setState(() => _message = null),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _test,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Test connection'),
              ),
            ],
            if (_message != null && _network)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _message!,
                  style: TextStyle(color: _ok ? Colors.green : scheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('server-save'),
          onPressed: _network && _address.text.trim().isEmpty
              ? null
              : () {
                  final nav = Navigator.of(context);
                  final next = _network ? _address.text.trim() : null;
                  nav.pop();
                  if (next != widget.connection.address) {
                    widget.connection.switchTo(next);
                  }
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// First-run setup for a new Firebase project or hospital server: creates
/// the administrator.
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
        () => _error =
            'Enter your name, a sign-in name and a password of 6+ characters',
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
    final email = context.read<HospitalStore>().backend.emailLogins;
    return AlertDialog(
      title: const Text('Set up a new hospital'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This creates the administrator account. It only works '
              'once per ${email ? 'Firebase project' : 'hospital server'}.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Your name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: email ? TextInputType.emailAddress : null,
              decoration: InputDecoration(
                labelText: email ? 'Email' : 'Administrator user name',
              ),
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
