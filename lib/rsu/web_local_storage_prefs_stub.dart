import 'package:rsu_results/rsu/prefs_storage.dart';

/// VM stub so Android/iOS builds never import `package:web`. Instantiation only happens when `kIsWeb` is true.
class WebLocalStoragePrefs implements PrefsStorage {
  @override
  String? getString(String key) => throw UnsupportedError('WebLocalStoragePrefs is web-only');

  @override
  int? getInt(String key) => throw UnsupportedError('WebLocalStoragePrefs is web-only');

  @override
  Future<void> setString(String key, String value) async => throw UnsupportedError('WebLocalStoragePrefs is web-only');

  @override
  Future<void> setInt(String key, int value) async => throw UnsupportedError('WebLocalStoragePrefs is web-only');

  @override
  Future<void> remove(String key) async => throw UnsupportedError('WebLocalStoragePrefs is web-only');
}
