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
  --log <file>   Also write messages to this file (for running in the
                 background at start-up)
  --help         Show this help
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
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final webArg = arg('web');
  final webDir = webArg != null
      ? Directory(webArg)
      : Directory('$exeDir${Platform.pathSeparator}web');
  final backupHours = int.tryParse(arg('backup-hours') ?? '') ?? 24;
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
