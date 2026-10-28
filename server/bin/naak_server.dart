import 'dart:async';
import 'dart:io';

import 'package:naak_server/naak_server.dart';

const _usage =
    '''
NAAK HMS Server - the hospital's own database on the local network.

Usage: naak_server [options]

  --port <n>     Port to listen on (default $kDefaultServerPort)
  --data <dir>   Where the database and backups are kept
                 (default: %ProgramData%\\NAAK HMS\\data, or ./data)
  --web <dir>    Folder with the web version of the app to serve
                 (default: the "web" folder next to this program, if any)
  --backup-hours <n>   Hours between automatic backups (default 24)
  --session-days <n>   Sign a computer out after n days without connecting
                 (default 14)
  --session-max-days <n>   ...and n days after signing in at the latest
                 (default 90)
  --keep-audit-days <n>    Archive audit entries older than n days
                 (default 365)
  --keep-notification-days <n>   Archive notifications older than n
                 days (default 90)
  --log <file>   Also write messages to this file (for running in the
                 background at start-up)
  --help         Show this help

       naak_server reset-password <user name> [--data <dir>] [--port <n>]

  Sets a new password for a login, for example an administrator who has
  forgotten theirs. Stop the server first (it must not be running). The
  new password is typed in, not shown.
''';

Future<void> main(List<String> args) async {
  String? arg(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }
  final port = int.tryParse(arg('port') ?? '') ?? kDefaultServerPort;
  final programData = Platform.environment['ProgramData'];
  final dataDir = Directory(
    arg('data') ??
        (programData != null ? '$programData\\NAAK HMS\\data' : 'data'),
  );
  if (args.isNotEmpty && args.first == 'reset-password') {
    exit(await _resetPassword(args, dataDir, port));
  }
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final webArg = arg('web');
  final webDir = webArg != null
      ? Directory(webArg)
      : Directory('$exeDir${Platform.pathSeparator}web');
  final backupHours = int.tryParse(arg('backup-hours') ?? '') ?? 24;
  Duration days(String name, int fallback) =>
      Duration(days: int.tryParse(arg(name) ?? '') ?? fallback);
  final logPath = arg('log');
  final logFile = logPath == null
      ? null
      : (File(logPath)..parent.createSync(recursive: true));
  void say(String s) {
    stdout.writeln(s);
    try {
      logFile?.writeAsStringSync(
        '${DateTime.now()}  $s\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException {
      // Logging must never stop the server.
    }
  }

  final server = NaakServer(
    dataDir: dataDir,
    webDir: webDir.existsSync() ? webDir : null,
    backupEvery: Duration(hours: backupHours),
    sessionIdle: days('session-days', 14),
    sessionMaxAge: days('session-max-days', 90),
    keepAuditLog: days('keep-audit-days', 365),
    keepNotifications: days('keep-notification-days', 90),
    log: (s) => say(s),
  );
  try {
    await server.start(port: port);
  } on SocketException catch (e) {
    say(
      'Could not listen on port $port (${e.osError?.message ?? e.message}). '
      'Is NAAK HMS Server already running?',
    );
    exit(1);
  }

  say('NAAK HMS Server is running.');
  say('  Database: ${dataDir.absolute.path}');
  say(
    server.isSetUp
        ? '  Hospital: set up'
        : '  Hospital: not set up yet - open the app on any computer and '
              'choose "First time? Set up a new hospital".',
  );
  say('  Connect the app on other computers to:');
  for (final ip in await _lanAddresses()) {
    say('    $ip:$port');
  }
  if (webDir.existsSync()) {
    say('  Or open http://<address>:$port in a browser.');
  }
  say('Press Ctrl+C to stop.');

  var stopping = false;
  Future<void> shutdown(ProcessSignal _) async {
    if (stopping) return;
    stopping = true;
    say('Stopping...');
    await server.stop();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}

Future<List<String>> _lanAddresses() async {
  final out = <String>[];
  for (final ni in await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  )) {
    for (final a in ni.addresses) {
      if (!a.isLoopback) out.add(a.address);
    }
  }
  return out.isEmpty ? ['localhost'] : out;
}

/// `naak_server reset-password <login>`: recovery when nobody who can
/// reset passwords in the app can sign in.
Future<int> _resetPassword(
  List<String> args,
  Directory dataDir,
  int port,
) async {
  final login = args.length > 1 && !args[1].startsWith('--') ? args[1] : null;
  if (login == null) {
    stderr.writeln('Usage: naak_server reset-password <user name>');
    return 2;
  }
  // The running server owns the database; changing it underneath would
  // lose the change.
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final res = await (await client.get('127.0.0.1', port, '/health')).close();
    await res.drain<void>();
    client.close(force: true);
    stderr.writeln(
      'NAAK HMS Server is running. Stop it first (as administrator):\n'
      '  schtasks /End /TN "NAAK HMS Server"\n'
      'then run this again, and afterwards start it with:\n'
      '  schtasks /Run /TN "NAAK HMS Server"',
    );
    return 1;
  } on Object {
    // Not running: carry on.
  }
  if (!dataDir.existsSync()) {
    stderr.writeln('No database at ${dataDir.path}.');
    return 1;
  }
  final db = NaakDatabase(dataDir);
  await db.open();
  try {
    final wanted = login.trim().toLowerCase();
    final acct = db.accounts.values.where((a) => a.login == wanted).firstOrNull;
    if (acct == null) {
      final admins = [
        for (final a in db.accounts.values)
          if (a.role == 'admin') a.login,
      ];
      stderr.writeln(
        'There is no login "$login". Administrator logins: '
        '${admins.isEmpty ? 'none' : admins.join(', ')}',
      );
      return 1;
    }
    String ask(String prompt) {
      stdout.write(prompt);
      final hidden = stdin.hasTerminal;
      if (hidden) stdin.echoMode = false;
      try {
        return stdin.readLineSync() ?? '';
      } finally {
        if (hidden) {
          stdin.echoMode = true;
          stdout.writeln();
        }
      }
    }

    final first = ask('New password for ${acct.login} (${acct.role}): ');
    if (first.length < 6) {
      stderr.writeln('The password must be at least 6 characters.');
      return 1;
    }
    if (ask('Type it again: ') != first) {
      stderr.writeln('The passwords did not match; nothing was changed.');
      return 1;
    }
    await db.setPassword(acct.uid, first);
    stdout.writeln(
      'Password changed for ${acct.login}. Start the server again and sign '
      'in with the new password.',
    );
    return 0;
  } finally {
    await db.close();
  }
}
