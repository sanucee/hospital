import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:naak_server/protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'lan_backend.dart';

/// Set for the web app that NAAK HMS Server hands out: it connects to the
/// server it was loaded from.
const _lanFromOrigin = bool.fromEnvironment('LAN_FROM_ORIGIN');

/// Which hospital server this computer uses, if any (saved on the device).
class ConnectionSettings {
  static const _key = 'lan_server_address';

  /// The saved server address, or null for "this computer only".
  static Future<String?> load() async {
    final saved = (await SharedPreferences.getInstance()).getString(_key);
    if (saved != null && saved.isNotEmpty) return saved;
    if (_lanFromOrigin && Uri.base.hasAuthority) return Uri.base.authority;
    return null;
  }

  static Future<void> save(String? address) async {
    final prefs = await SharedPreferences.getInstance();
    if (address == null || address.trim().isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, address.trim());
    }
  }

  /// Checks that NAAK HMS Server answers at [address]. Returns whether a
  /// hospital is set up on it, or throws [HospitalException] explaining
  /// what's wrong.
  static Future<bool> check(String address) async {
    if (address.trim().isEmpty) {
      throw HospitalException('Enter the server address, e.g. 192.168.1.10');
    }
    final ws = lanServerUri(address);
    final url = ws.replace(
      scheme: ws.scheme == 'wss' ? 'https' : 'http',
      path: '/health',
    );
    final http.Response res;
    try {
      res = await http.get(url).timeout(const Duration(seconds: 5));
    } catch (_) {
      throw HospitalException(
        'No answer from ${ws.host}:${ws.port}. Check the address, that NAAK '
        'HMS Server is running there, and that its firewall allows port '
        '${ws.port}.',
      );
    }
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['name'] != 'NAAK HMS Server') throw const FormatException();
      if ((j['protocol'] as num) != kProtocolVersion) {
        throw HospitalException(
          'That server runs a different version of NAAK HMS. Install the '
          'same version on the server and this computer.',
        );
      }
      return j['setUp'] == true;
    } on HospitalException {
      rethrow;
    } catch (_) {
      throw HospitalException(
        '${ws.host}:${ws.port} answered, but it is not NAAK HMS Server.',
      );
    }
  }
}
