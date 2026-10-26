import 'package:shared_preferences/shared_preferences.dart';

/// Where the hospital state document is kept. Abstracted so tests can run
/// against memory and a future version can swap in a remote API.
abstract class StorageBackend {
  Future<String?> read();
  Future<void> write(String data);
  Future<void> clear();
}

class SharedPrefsStorage implements StorageBackend {
  static const _key = 'hospital_state_v1';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String data) async =>
      (await SharedPreferences.getInstance()).setString(_key, data);

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

class MemoryStorage implements StorageBackend {
  String? data;

  @override
  Future<String?> read() async => data;

  @override
  Future<void> write(String data) async => this.data = data;

  @override
  Future<void> clear() async => data = null;
}
